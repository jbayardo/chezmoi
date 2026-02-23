#!/usr/bin/env dotnet-script
#r "nuget: ModelContextProtocol, 0.2.0-preview.1"
#r "nuget: Microsoft.Extensions.Hosting, 9.0.0"
#r "nuget: Microsoft.Cloud.Metrics.Client, 2.2025.724.3"

using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.ComponentModel;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Cloud.Metrics.Client;
using Microsoft.Cloud.Metrics.Client.Metrics;
using Microsoft.Cloud.Metrics.Client.Query;
using Microsoft.Cloud.Metrics.Client.Query.Kqlm;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Cloud.Metrics.Client.Logging;
using Microsoft.Online.Metrics.Serialization.Configuration;
using ModelContextProtocol.Server;

// ============================================================================
// Geneva Metrics MCP Server - Single-file C# script for MDM metric queries
// Run with: dotnet script geneva-metrics-mcp.csx
//
// NuGet feed required: https://msblox.pkgs.visualstudio.com/DefaultCollection/_packaging/AzureGenevaMonitoring/nuget/v3/index.json
// ============================================================================

#region Metrics Client Service

public class MetricsClientService
{
    // Reuse a single MetricReader per environment (best practice: reuse client objects)
    private readonly ConcurrentDictionary<string, MetricReader> _readerCache = new();

    public MetricReader GetReader(string environment = "Production")
    {
        return _readerCache.GetOrAdd(environment, env =>
        {
            var mdmEnv = env.Equals("PPE", StringComparison.OrdinalIgnoreCase)
                ? MdmEnvironment.PPE
                : MdmEnvironment.Production;

            // User-based AAD auth (default); ClientId helps with debugging (best practice)
            var connectionInfo = new ConnectionInfo(mdmEnv);
            return new MetricReader(connectionInfo, "GenevaMetricsMcpServer");
        });
    }

    public string FormatQueryResultV3(IQueryResultListV3 results, int maxRows)
    {
        if (results?.Results == null || results.Results.Count == 0)
            return "No results.";

        var sb = new StringBuilder();
        sb.AppendLine($"Time range: {results.StartTimeUtc:u} to {results.EndTimeUtc:u} (resolution: {results.TimeResolutionInMinutes}m)");
        sb.AppendLine();

        int count = 0;
        foreach (var series in results.Results)
        {
            if (count >= maxRows) break;

            sb.AppendLine($"### Series {count + 1}");

            // Dimension values
            if (series.DimensionList != null && series.DimensionList.Count > 0)
            {
                sb.AppendLine("**Dimensions:**");
                foreach (var kvp in series.DimensionList)
                    sb.AppendLine($"  - {kvp.Key} = {kvp.Value}");
            }

            sb.AppendLine($"**Evaluated result:** {series.EvaluatedResult}");
            sb.AppendLine();
            count++;
        }

        if (results.Results.Count > maxRows)
            sb.AppendLine($"*Results truncated. Showing {maxRows} of {results.Results.Count} series.*");

        return sb.ToString().TrimEnd();
    }

    public string FormatKqlmResult(IKqlmQueryResult result, int maxRows)
    {
        if (result == null)
            return "No results.";

        var sb = new StringBuilder();

        // Show execution state
        sb.AppendLine($"**Query state:** {result.State}");
        if (!string.IsNullOrEmpty(result.RequestID))
            sb.AppendLine($"**Request ID:** {result.RequestID}");

        // Show execution messages (warnings, errors)
        if (result.ExecutionMessages != null)
        {
            foreach (var msg in result.ExecutionMessages)
            {
                sb.AppendLine($"**[{msg.Severity}]** {msg.Text}");
                if (!string.IsNullOrEmpty(msg.DocumentationLink))
                    sb.AppendLine($"  Doc: {msg.DocumentationLink}");
            }
        }
        sb.AppendLine();

        // KQL-M results contain TimeSeriesSets
        if (result.TimeSeriesSets != null)
        {
            int setIdx = 0;
            foreach (var tsSet in result.TimeSeriesSets)
            {
                setIdx++;
                var meta = tsSet.ResultsMetadata;
                if (meta != null)
                {
                    sb.AppendLine($"### Result Set {setIdx}");
                    sb.AppendLine($"Time range: {meta.StartTimeUtc:u} to {meta.EndTimeUtc:u} (resolution: {meta.DataResolution})");
                    if (meta.ResultantDimensions != null)
                        sb.AppendLine($"Dimensions: {string.Join(", ", meta.ResultantDimensions)}");
                    if (meta.ResultantSamplingTypes != null)
                        sb.AppendLine($"Sampling types: {string.Join(", ", meta.ResultantSamplingTypes)}");
                    sb.AppendLine($"Datapoints: {meta.DatapointsCount}");
                    sb.AppendLine();
                }

                if (tsSet.TimeSeriesData != null)
                {
                    int count = 0;
                    foreach (var series in tsSet.TimeSeriesData)
                    {
                        if (count >= maxRows) break;

                        sb.AppendLine($"**Series {count + 1}:**");

                        if (series.DimensionValues != null)
                        {
                            foreach (var dim in series.DimensionValues)
                                sb.AppendLine($"  - {dim.Key} = {dim.Value}");
                        }

                        if (series.SamplingTypesData != null)
                        {
                            foreach (var st in series.SamplingTypesData)
                            {
                                var values = st.Value?.ToList();
                                if (values != null && values.Count > 0)
                                {
                                    // Show first/last few values to keep output manageable
                                    if (values.Count <= 10)
                                        sb.AppendLine($"  **{st.Key}:** [{string.Join(", ", values)}]");
                                    else
                                        sb.AppendLine($"  **{st.Key}:** [{string.Join(", ", values.Take(5))}, ... , {string.Join(", ", values.Skip(values.Count - 3))}] ({values.Count} points)");
                                }
                            }
                        }

                        sb.AppendLine();
                        count++;
                    }

                    var totalCount = tsSet.TimeSeriesData.Count();
                    if (totalCount > maxRows)
                        sb.AppendLine($"*Results truncated. Showing {maxRows} of {totalCount} series.*");
                }
            }
        }

        var text = sb.ToString().TrimEnd();
        return string.IsNullOrEmpty(text) ? "Query executed successfully. No data returned." : text;
    }
}

#endregion

#region MCP Tools

[McpServerToolType]
public class GenevaMetricsTools
{
    private readonly MetricsClientService _metrics;

    public GenevaMetricsTools(MetricsClientService metrics)
    {
        _metrics = metrics;
    }

    [McpServerTool(Name = "execute_kqlm"), Description("Execute a KQL-M (Kusto Query Language for Metrics) query against Geneva Metrics.")]
    public async Task<string> ExecuteKqlm(
        [Description("The Geneva monitoring account name (e.g., 'MetricTeamInternalMetrics')")] string monitoringAccount,
        [Description("The metric namespace (e.g., 'PlatformMetrics')")] string metricNamespace,
        [Description("The KQL-M query text (e.g., 'metric(\"MetricName\").dimensions(\"Dim1\").samplingTypes(\"Sum\")')")] string query,
        [Description("Start time in UTC ISO 8601 format (e.g., '2024-01-15T00:00:00Z'). If not provided, defaults to 1 hour ago.")] string startTimeUtc = null,
        [Description("End time in UTC ISO 8601 format (e.g., '2024-01-15T01:00:00Z'). If not provided, defaults to now.")] string endTimeUtc = null,
        [Description("Maximum number of result rows/series to return (default: 20, max: 500)")] int limit = 20,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            limit = Math.Max(1, Math.Min(limit, 500));

            var endTime = string.IsNullOrEmpty(endTimeUtc)
                ? DateTime.UtcNow
                : DateTime.Parse(endTimeUtc).ToUniversalTime();
            var startTime = string.IsNullOrEmpty(startTimeUtc)
                ? endTime.AddHours(-1)
                : DateTime.Parse(startTimeUtc).ToUniversalTime();

            var reader = _metrics.GetReader(environment);
            var result = await reader.ExecuteKqlmQueryAsync(
                monitoringAccount,
                metricNamespace,
                query,
                startTime,
                endTime,
                cancellationToken);

            return _metrics.FormatKqlmResult(result, limit);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_namespaces"), Description("List all metric namespaces in a Geneva monitoring account.")]
    public async Task<string> GetNamespaces(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            var reader = _metrics.GetReader(environment);
            var namespaces = await reader.GetNamespacesAsync(monitoringAccount);

            if (namespaces == null || !namespaces.Any())
                return "No namespaces found.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Namespaces in {monitoringAccount}");
            sb.AppendLine();
            foreach (var ns in namespaces.OrderBy(n => n))
                sb.AppendLine($"- {ns}");

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_metric_names"), Description("List all metric names in a namespace within a Geneva monitoring account.")]
    public async Task<string> GetMetricNames(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("The metric namespace")] string metricNamespace,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            var reader = _metrics.GetReader(environment);
            var names = await reader.GetMetricNamesAsync(monitoringAccount, metricNamespace);

            if (names == null || !names.Any())
                return "No metrics found.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Metrics in {monitoringAccount}/{metricNamespace}");
            sb.AppendLine();
            foreach (var name in names.OrderBy(n => n))
                sb.AppendLine($"- {name}");

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_dimension_names"), Description("List all dimension names for a specific metric.")]
    public async Task<string> GetDimensionNames(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("The metric namespace")] string metricNamespace,
        [Description("The metric name")] string metricName,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            var reader = _metrics.GetReader(environment);
            var metricId = new MetricIdentifier(monitoringAccount, metricNamespace, metricName);
            var dimensions = await reader.GetDimensionNamesAsync(metricId);

            if (dimensions == null || !dimensions.Any())
                return "No dimensions found.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Dimensions for {monitoringAccount}/{metricNamespace}/{metricName}");
            sb.AppendLine();
            foreach (var dim in dimensions.OrderBy(d => d))
                sb.AppendLine($"- {dim}");

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_dimension_values"), Description("List values for a specific dimension of a metric within a time window (day resolution).")]
    public async Task<string> GetDimensionValues(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("The metric namespace")] string metricNamespace,
        [Description("The metric name")] string metricName,
        [Description("The dimension name to get values for")] string dimensionName,
        [Description("Start time in UTC ISO 8601 format. If not provided, defaults to 1 day ago.")] string startTimeUtc = null,
        [Description("End time in UTC ISO 8601 format. If not provided, defaults to now.")] string endTimeUtc = null,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            var endTime = string.IsNullOrEmpty(endTimeUtc)
                ? DateTime.UtcNow
                : DateTime.Parse(endTimeUtc).ToUniversalTime();
            var startTime = string.IsNullOrEmpty(startTimeUtc)
                ? endTime.AddDays(-1)
                : DateTime.Parse(startTimeUtc).ToUniversalTime();

            var reader = _metrics.GetReader(environment);
            var metricId = new MetricIdentifier(monitoringAccount, metricNamespace, metricName);
            var dimensionFilters = new List<DimensionFilter>
            {
                DimensionFilter.CreateIncludeFilter(dimensionName)
            };

            var values = await reader.GetDimensionValuesAsync(
                metricId,
                dimensionFilters,
                dimensionName,
                startTime,
                endTime);

            if (values == null || !values.Any())
                return $"No values found for dimension '{dimensionName}'.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Values for dimension '{dimensionName}'");
            sb.AppendLine($"Metric: {monitoringAccount}/{metricNamespace}/{metricName}");
            sb.AppendLine($"Time range: {startTime:u} to {endTime:u}");
            sb.AppendLine();
            foreach (var val in values.OrderBy(v => v))
                sb.AppendLine($"- {val}");

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_preaggregates"), Description("Get pre-aggregate configurations for a metric. Pre-aggregates define which dimension combinations are pre-computed for efficient querying.")]
    public async Task<string> GetPreAggregates(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("The metric namespace")] string metricNamespace,
        [Description("The metric name")] string metricName,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            var reader = _metrics.GetReader(environment);
            var metricId = new MetricIdentifier(monitoringAccount, metricNamespace, metricName);
            var configs = await reader.GetPreAggregateConfigurationsAsync(metricId);

            if (configs == null || !configs.Any())
                return "No pre-aggregate configurations found.";

            var sb = new StringBuilder();
            sb.AppendLine($"## Pre-aggregate configurations for {metricName}");
            sb.AppendLine();

            int idx = 0;
            foreach (var config in configs)
            {
                sb.AppendLine($"### Configuration {++idx}: {config.DisplayName ?? "(unnamed)"}");
                if (config.Dimensions != null)
                    sb.AppendLine($"**Dimensions:** {string.Join(", ", config.Dimensions)}");
                sb.AppendLine($"**Min/Max enabled:** {config.MinMaxMetricsEnabled}");
                sb.AppendLine($"**Percentile enabled:** {config.PercentileMetricsEnabled}");
                if (config.DistinctCountColumns != null && config.DistinctCountColumns.Count > 0)
                    sb.AppendLine($"**Distinct count columns:** {string.Join(", ", config.DistinctCountColumns)}");
                sb.AppendLine();
            }

            return sb.ToString().TrimEnd();
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }

    [McpServerTool(Name = "get_timeseries"), Description("Query time series data using structured (non-KQL-M) API with dimension filters. Returns top N series ordered by a sampling type.")]
    public async Task<string> GetTimeSeries(
        [Description("The Geneva monitoring account name")] string monitoringAccount,
        [Description("The metric namespace")] string metricNamespace,
        [Description("The metric name")] string metricName,
        [Description("Sampling types to retrieve, comma-separated (e.g., 'Sum,Count,Average,Min,Max'). Default: 'Sum'")] string samplingTypes = "Sum",
        [Description("Dimension filters as JSON array of objects with 'name' and optional 'values' (e.g., '[{\"name\":\"Datacenter\",\"values\":[\"EastUS\"]}]'). Empty values means all.")] string dimensionFiltersJson = "[]",
        [Description("Start time in UTC ISO 8601 format. If not provided, defaults to 1 hour ago.")] string startTimeUtc = null,
        [Description("End time in UTC ISO 8601 format. If not provided, defaults to now.")] string endTimeUtc = null,
        [Description("Top N series to return ordered by first sampling type descending (default: 10, max: 100)")] int top = 10,
        [Description("Environment: 'Production' or 'PPE' (default: 'Production')")] string environment = "Production",
        CancellationToken cancellationToken = default)
    {
        try
        {
            top = Math.Max(1, Math.Min(top, 100));

            var endTime = string.IsNullOrEmpty(endTimeUtc)
                ? DateTime.UtcNow
                : DateTime.Parse(endTimeUtc).ToUniversalTime();
            var startTime = string.IsNullOrEmpty(startTimeUtc)
                ? endTime.AddHours(-1)
                : DateTime.Parse(startTimeUtc).ToUniversalTime();

            var reader = _metrics.GetReader(environment);
            var metricId = new MetricIdentifier(monitoringAccount, metricNamespace, metricName);

            // Parse sampling types
            var stList = new List<SamplingType>();
            foreach (var st in samplingTypes.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
            {
                stList.Add(st.ToLower() switch
                {
                    "sum" => SamplingType.Sum,
                    "count" => SamplingType.Count,
                    "average" or "avg" => SamplingType.Average,
                    "min" => SamplingType.Min,
                    "max" => SamplingType.Max,
                    "rate" => SamplingType.Rate,
                    _ => new SamplingType(st)
                });
            }

            // Parse dimension filters
            var dimFilters = new List<DimensionFilter>();
            if (!string.IsNullOrWhiteSpace(dimensionFiltersJson) && dimensionFiltersJson != "[]")
            {
                var filtersDoc = JsonDocument.Parse(dimensionFiltersJson);
                foreach (var filterEl in filtersDoc.RootElement.EnumerateArray())
                {
                    var name = filterEl.GetProperty("name").GetString();
                    var values = new List<string>();
                    if (filterEl.TryGetProperty("values", out var valuesEl))
                    {
                        foreach (var v in valuesEl.EnumerateArray())
                            values.Add(v.GetString());
                    }

                    dimFilters.Add(values.Count > 0
                        ? DimensionFilter.CreateIncludeFilter(name, values.ToArray())
                        : DimensionFilter.CreateIncludeFilter(name));
                }
            }

            var selectionClause = new SelectionClauseV3(
                new PropertyDefinition(PropertyAggregationType.Average, stList[0]),
                top,
                OrderBy.Descending);

            var results = await reader.GetFilteredDimensionValuesAsyncV3(
                metricId,
                dimFilters,
                startTime,
                endTime,
                stList,
                selectionClause);

            return _metrics.FormatQueryResultV3(results, top);
        }
        catch (Exception ex)
        {
            return $"Error: {ex.GetType().Name}: {ex.Message}";
        }
    }
}

#endregion

#region Main

// Disable the Geneva SDK's internal logger to prevent stdout pollution
// (MCP uses stdout exclusively for JSON-RPC)
Logger.DisableLogging = true;

var builder = Host.CreateApplicationBuilder(Args.ToArray());

builder.Services.AddSingleton<MetricsClientService>();

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<GenevaMetricsTools>();

// MCP uses stdout for JSON-RPC protocol - all logs MUST go to stderr
builder.Logging.SetMinimumLevel(LogLevel.Warning);
builder.Logging.AddConsole(options =>
{
    options.LogToStandardErrorThreshold = LogLevel.Trace;
});

await builder.Build().RunAsync();

#endregion
