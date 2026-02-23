#!/usr/bin/env dotnet-script
#r "nuget: ModelContextProtocol, 0.2.0-preview.1"
#r "nuget: Microsoft.Extensions.Hosting, 9.0.0"
#r "nuget: Microsoft.Azure.Kusto.Data, 12.2.0"
#r "nuget: Microsoft.Azure.Kusto.Language, 12.3.2"
#r "nuget: Azure.Identity, 1.13.1"

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Azure.Core;
using Azure.Identity;
using Kusto.Data;
using Kusto.Data.Common;
using Kusto.Data.Net.Client;
using Kusto.Language;
using Kusto.Language.Editor;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

// ============================================================================
// Kusto MCP Server - Single-file C# script for Azure Data Explorer queries
// Run with: dotnet script kusto-mcp.csx
// ============================================================================

#region Azure CLI Token Credential

// Custom TokenCredential that calls Azure CLI directly
// This bypasses the Azure.Identity SDK's process spawning timeout issues
public class AzureCliTokenCredential : TokenCredential
{
    private readonly ConcurrentDictionary<string, (AccessToken Token, DateTimeOffset Expiry)> _tokenCache = new();

    public override AccessToken GetToken(TokenRequestContext requestContext, CancellationToken cancellationToken)
    {
        return GetTokenAsync(requestContext, cancellationToken).GetAwaiter().GetResult();
    }

    public override async ValueTask<AccessToken> GetTokenAsync(TokenRequestContext requestContext, CancellationToken cancellationToken)
    {
        var resource = requestContext.Scopes.FirstOrDefault()?.Replace("/.default", "") ?? throw new InvalidOperationException("No scope provided");

        // Check cache first
        if (_tokenCache.TryGetValue(resource, out var cached) && cached.Expiry > DateTimeOffset.UtcNow.AddMinutes(5))
        {
            return cached.Token;
        }

        // Use cmd.exe to run az with non-interactive settings
        var psi = new ProcessStartInfo
        {
            FileName = "cmd.exe",
            Arguments = $"/c az account get-access-token --resource \"{resource}\" --output json",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            RedirectStandardInput = true,  // Redirect stdin to prevent interactive prompts
            UseShellExecute = false,
            CreateNoWindow = true
        };

        // Set environment to disable interactive/telemetry features
        psi.Environment["AZURE_CORE_NO_COLOR"] = "1";
        psi.Environment["AZURE_CORE_ONLY_SHOW_ERRORS"] = "1";
        psi.Environment["AZURE_CORE_COLLECT_TELEMETRY"] = "0";

        // Copy environment variables
        foreach (System.Collections.DictionaryEntry env in Environment.GetEnvironmentVariables())
        {
            psi.Environment[(string)env.Key] = (string)env.Value;
        }

        var sw = System.Diagnostics.Stopwatch.StartNew();

        // Use event-based output capture to avoid deadlocks
        var outputBuilder = new StringBuilder();
        var errorBuilder = new StringBuilder();
        var outputDone = new TaskCompletionSource<bool>();
        var errorDone = new TaskCompletionSource<bool>();

        var proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
        proc.OutputDataReceived += (s, e) =>
        {
            if (e.Data == null)
                outputDone.TrySetResult(true);
            else
                outputBuilder.AppendLine(e.Data);
        };
        proc.ErrorDataReceived += (s, e) =>
        {
            if (e.Data == null)
                errorDone.TrySetResult(true);
            else
                errorBuilder.AppendLine(e.Data);
        };

        if (!proc.Start())
            throw new InvalidOperationException("Failed to start az CLI");

        // Close stdin to signal no input (prevents interactive prompts)
        proc.StandardInput.Close();

        proc.BeginOutputReadLine();
        proc.BeginErrorReadLine();

        try
        {
            // Wait for process with short timeout (5 seconds) - fail fast to allow credential chain fallback
            var completed = proc.WaitForExit(5000);
            sw.Stop();

            if (!completed)
            {
                proc.Kill();
                throw new CredentialUnavailableException("Azure CLI timed out after 5 seconds");
            }

            // Wait for output streams to finish (should be immediate after process exits)
            await Task.WhenAll(outputDone.Task, errorDone.Task);

            var output = outputBuilder.ToString();
            var error = errorBuilder.ToString();

            if (proc.ExitCode != 0)
            {
                throw new CredentialUnavailableException($"Azure CLI authentication failed (exit code {proc.ExitCode}): {error}. Output: {output}");
            }

            if (string.IsNullOrWhiteSpace(output))
            {
                throw new CredentialUnavailableException($"Azure CLI returned empty output. Stderr: {error}");
            }

            var doc = JsonDocument.Parse(output);
            var root = doc.RootElement;

            var accessToken = root.GetProperty("accessToken").GetString()!;
            var expiresOn = root.GetProperty("expiresOn").GetString()!;
            var expiry = DateTimeOffset.Parse(expiresOn);

            var token = new AccessToken(accessToken, expiry);
            _tokenCache[resource] = (token, expiry);

            return token;
        }
        finally
        {
            proc.Dispose();
        }
    }
}

#endregion

#region Kusto Client Service

public class KustoClientService
{
    private readonly ConcurrentDictionary<string, ICslQueryProvider> _clientCache = new();

    // Credential chain: try Azure CLI first (fast), then fall back to other methods
    private readonly TokenCredential _credential = new ChainedTokenCredential(
        new AzureCliTokenCredential(),           // Try CLI first (5s timeout)
        new EnvironmentCredential(),             // Service principal via env vars
        new ManagedIdentityCredential(),         // Azure VM/container managed identity
        new VisualStudioCredential(),            // VS login
        new VisualStudioCodeCredential()         // VS Code login
    );

    public ICslQueryProvider GetClient(string clusterUrl)
    {
        return _clientCache.GetOrAdd(clusterUrl, url =>
        {
            var kcsb = new KustoConnectionStringBuilder(url)
                .WithAadAzureTokenCredentialsAuthentication(_credential);
            return KustoClientFactory.CreateCslQueryProvider(kcsb);
        });
    }

    public async Task<IDataReader> ExecuteQueryAsync(string clusterUrl, string database, string query, CancellationToken cancellationToken = default)
    {
        var client = GetClient(clusterUrl);
        return await client.ExecuteQueryAsync(database, query, new ClientRequestProperties(), cancellationToken);
    }

    public async Task<(List<string> Columns, List<List<object>> Rows)> ReadResultsAsync(IDataReader reader, CancellationToken cancellationToken = default)
    {
        var columns = new List<string>();
        for (int i = 0; i < reader.FieldCount; i++)
            columns.Add(reader.GetName(i));

        var rows = new List<List<object>>();
        while (await Task.Run(() => reader.Read(), cancellationToken))
        {
            var row = new List<object>();
            for (int i = 0; i < reader.FieldCount; i++)
                row.Add(reader.IsDBNull(i) ? null : reader.GetValue(i));
            rows.Add(row);
        }

        return (columns, rows);
    }

    public string FormatTable(List<string> columns, List<List<object>> rows, int? maxRows = null)
    {
        if (rows.Count == 0)
            return "No results.";

        var actualRows = maxRows.HasValue ? rows.Take(maxRows.Value).ToList() : rows;
        var truncated = maxRows.HasValue && rows.Count > maxRows.Value;

        var sb = new StringBuilder();
        sb.AppendLine("| " + string.Join(" | ", columns) + " |");
        sb.AppendLine("|" + string.Join("|", columns.Select(_ => "---")) + "|");

        foreach (var row in actualRows)
        {
            var cells = row.Select(v => v?.ToString() ?? "").ToList();
            sb.AppendLine("| " + string.Join(" | ", cells) + " |");
        }

        if (truncated)
            sb.AppendLine($"\n*Results truncated. Showing {maxRows} of {rows.Count} rows.*");

        return sb.ToString().TrimEnd();
    }

    public string ExtractClusterName(string clusterUrl)
    {
        if (Uri.TryCreate(clusterUrl, UriKind.Absolute, out var uri))
            return uri.Host.Split('.')[0];
        return clusterUrl.Split('.')[0];
    }
}

#endregion

#region MCP Tools

[McpServerToolType]
public class KustoTools
{
    private readonly KustoClientService _kusto;

    public KustoTools(KustoClientService kusto)
    {
        _kusto = kusto;
    }

    [McpServerTool(Name = "show_databases"), Description("List all databases in a Kusto cluster.")]
    public async Task<string> ShowDatabases(
        [Description("The Kusto cluster URL (e.g., https://1es.kusto.windows.net)")] string clusterUrl,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, "", ".show databases", cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);
            return _kusto.FormatTable(columns, rows);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "show_tables"), Description("List all tables in a Kusto database.")]
    public async Task<string> ShowTables(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, database, ".show tables", cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);
            return _kusto.FormatTable(columns, rows);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "show_table"), Description("Show the schema (columns) of a specific table.")]
    public async Task<string> ShowTable(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        [Description("The name of the table to describe")] string tableName,
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Use getschema operator for cleaner column listing
            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, database,
                $"['{tableName}'] | getschema | project ColumnName, ColumnType", cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);

            if (rows.Count == 0)
                return $"Table '{tableName}' not found or has no columns.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Schema for {tableName}");
            sb.AppendLine();
            sb.AppendLine("| Column | Type |");
            sb.AppendLine("|--------|------|");

            foreach (var row in rows)
            {
                var colName = row.Count > 0 ? row[0]?.ToString() : "";
                var colType = row.Count > 1 ? row[1]?.ToString() : "";
                sb.AppendLine($"| {colName} | {colType} |");
            }

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "show_functions"), Description("List all functions in a Kusto database.")]
    public async Task<string> ShowFunctions(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, database, ".show functions", cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);
            return _kusto.FormatTable(columns, rows);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "show_function"), Description("Show details of a specific function including its code and parameters.")]
    public async Task<string> ShowFunction(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        [Description("The name of the function to show")] string functionName,
        CancellationToken cancellationToken = default)
    {
        try
        {
            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, database, $".show function ['{functionName}']", cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);

            if (rows.Count == 0)
                return $"Function '{functionName}' not found.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Function: {functionName}");
            sb.AppendLine();

            var row = rows[0];
            for (int i = 0; i < columns.Count && i < row.Count; i++)
            {
                var col = columns[i];
                var value = row[i]?.ToString();
                if (!string.IsNullOrEmpty(value))
                {
                    if (col.Equals("Body", StringComparison.OrdinalIgnoreCase))
                    {
                        sb.AppendLine($"### {col}");
                        sb.AppendLine("```kql");
                        sb.AppendLine(value);
                        sb.AppendLine("```");
                    }
                    else
                    {
                        sb.AppendLine($"**{col}:** {value}");
                    }
                }
            }

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "execute_kql"), Description("Execute a KQL query and return results.")]
    public async Task<string> ExecuteKql(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        [Description("The KQL query to execute")] string query,
        [Description("Maximum number of rows to return (default: 20, max: 1000)")] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        try
        {
            limit = Math.Max(1, Math.Min(limit, 1000));

            using var reader = await _kusto.ExecuteQueryAsync(clusterUrl, database, query, cancellationToken);
            var (columns, rows) = await _kusto.ReadResultsAsync(reader, cancellationToken);
            return _kusto.FormatTable(columns, rows, limit);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "generate_web_link"), Description("Generate a shareable Kusto Web Explorer link for a KQL query.")]
    public async Task<string> GenerateWebLink(
        [Description("The Kusto cluster URL")] string clusterUrl,
        [Description("The database name")] string database,
        [Description("The KQL query to encode in the link")] string query)
    {
        var queryBytes = Encoding.UTF8.GetBytes(query);
        using var memoryStream = new MemoryStream();
        await using (var gzipStream = new GZipStream(memoryStream, CompressionMode.Compress))
        {
            await gzipStream.WriteAsync(queryBytes, 0, queryBytes.Length);
        }
        var compressed = memoryStream.ToArray();
        var encoded = Convert.ToBase64String(compressed);
        var urlEncoded = Uri.EscapeDataString(encoded);
        var clusterName = _kusto.ExtractClusterName(clusterUrl);

        return $"https://dataexplorer.azure.com/clusters/{clusterName}/databases/{database}?query={urlEncoded}";
    }

    [McpServerTool(Name = "format_kql"), Description("Format a KQL query using the official Microsoft Kusto Language library.")]
    public Task<string> FormatKql(
        [Description("The KQL query to format")] string query,
        [Description("Number of spaces per indentation level (default: 4)")] int indentSize = 4,
        [Description("Pipe operator placement style - 'Smart', 'NewLine', or 'None' (default: 'Smart')")] string pipeStyle = "Smart")
    {
        var placement = pipeStyle.ToLower() switch
        {
            "smart" => PlacementStyle.Smart,
            "newline" => PlacementStyle.NewLine,
            "none" => PlacementStyle.None,
            _ => PlacementStyle.Smart
        };

        var options = FormattingOptions.Default
            .WithIndentationSize(indentSize)
            .WithPipeOperatorStyle(placement);

        var code = KustoCode.Parse(query);
        var codeService = new KustoCodeService(code);
        var formattedResult = codeService.GetFormattedText(options);

        return Task.FromResult(formattedResult.Text);
    }

    [McpServerTool(Name = "parse_web_link"), Description("Extract cluster URL, database, and query from a Kusto Web Explorer link.")]
    public async Task<string> ParseWebLink(
        [Description("The Kusto Web Explorer URL to parse")] string url)
    {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
            return "Error: Invalid URL format.";

        // Parse path: /clusters/{cluster}/databases/{database}
        var segments = uri.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);

        string clusterName = null;
        string database = null;

        for (int i = 0; i < segments.Length - 1; i++)
        {
            if (segments[i].Equals("clusters", StringComparison.OrdinalIgnoreCase))
                clusterName = segments[i + 1];
            else if (segments[i].Equals("databases", StringComparison.OrdinalIgnoreCase))
                database = segments[i + 1];
        }

        if (string.IsNullOrEmpty(clusterName))
            return "Error: Could not extract cluster name from URL.";

        // Build cluster URL
        var clusterUrl = $"https://{clusterName}.kusto.windows.net";

        // Extract query parameter manually
        string encodedQuery = null;
        var queryString = uri.Query.TrimStart('?');
        foreach (var param in queryString.Split('&', StringSplitOptions.RemoveEmptyEntries))
        {
            var parts = param.Split('=', 2);
            if (parts.Length == 2 && parts[0].Equals("query", StringComparison.OrdinalIgnoreCase))
            {
                encodedQuery = parts[1];
                break;
            }
        }

        string query = null;
        if (!string.IsNullOrEmpty(encodedQuery))
        {
            // URL decode -> Base64 decode -> Gzip decompress
            var base64 = Uri.UnescapeDataString(encodedQuery);
            var compressed = Convert.FromBase64String(base64);

            using var inputStream = new MemoryStream(compressed);
            using var gzipStream = new GZipStream(inputStream, CompressionMode.Decompress);
            using var outputStream = new MemoryStream();
            await gzipStream.CopyToAsync(outputStream);
            query = Encoding.UTF8.GetString(outputStream.ToArray());
        }

        var sb = new StringBuilder();
        sb.AppendLine($"**Cluster URL:** {clusterUrl}");
        sb.AppendLine($"**Database:** {database ?? "(not specified)"}");
        sb.AppendLine();
        if (!string.IsNullOrEmpty(query))
        {
            sb.AppendLine("**Query:**");
            sb.AppendLine("```kql");
            sb.AppendLine(query);
            sb.AppendLine("```");
        }
        else
        {
            sb.AppendLine("**Query:** (none)");
        }

        return sb.ToString().TrimEnd();
    }
}

#endregion

#region Main

var builder = Host.CreateApplicationBuilder(Args.ToArray());

builder.Services.AddSingleton<KustoClientService>();

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<KustoTools>();

// MCP uses stdout for JSON-RPC protocol - all logs MUST go to stderr
builder.Logging.SetMinimumLevel(LogLevel.Debug);
builder.Logging.AddConsole(options =>
{
    options.LogToStandardErrorThreshold = LogLevel.Trace;
});

await builder.Build().RunAsync();

#endregion
