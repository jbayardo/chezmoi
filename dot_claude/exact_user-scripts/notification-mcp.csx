#!/usr/bin/env dotnet-script
#r "nuget: ModelContextProtocol, 0.2.0-preview.1"
#r "nuget: Microsoft.Extensions.Hosting, 9.0.0"

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using ModelContextProtocol.Server;

// ============================================================================
// Notification MCP Server - Toast notifications + terminal tab color flashing
// Run with: dotnet script notification-mcp.csx
// ============================================================================

#region Console Helper (P/Invoke for tab color)

public class ConsoleHelper
{
    [DllImport("kernel32.dll")] static extern bool AttachConsole(uint pid);
    [DllImport("kernel32.dll")] static extern bool FreeConsole();
    [DllImport("kernel32.dll")] static extern IntPtr GetConsoleWindow();
    [DllImport("kernel32.dll")] static extern bool GetConsoleMode(IntPtr h, out uint m);
    [DllImport("kernel32.dll")] static extern bool SetConsoleMode(IntPtr h, uint m);
    [DllImport("kernel32.dll")] static extern bool WriteConsole(IntPtr h, string s, uint n, out uint w, IntPtr r);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    static extern IntPtr CreateFile(string fn, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr h, int c, ref PBI p, int l, out int r);

    [StructLayout(LayoutKind.Sequential)]
    struct PBI { public IntPtr R1, Peb, R2a, R2b, Pid, ParentPid; }

    const uint GENERIC_READ = 0x80000000;
    const uint GENERIC_WRITE = 0x40000000;
    const uint FILE_SHARE_WRITE = 0x2;
    const uint OPEN_EXISTING = 3;
    const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;

    int GetParentPid(int pid)
    {
        try
        {
            var pbi = new PBI();
            if (NtQueryInformationProcess(Process.GetProcessById(pid).Handle, 0, ref pbi, Marshal.SizeOf(pbi), out _) == 0)
                return pbi.ParentPid.ToInt32();
        }
        catch { }
        return -1;
    }

    bool WriteToConsole(string text)
    {
        IntPtr handle = CreateFile("CONOUT$", GENERIC_READ | GENERIC_WRITE, FILE_SHARE_WRITE, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (handle == IntPtr.Zero || handle == (IntPtr)(-1))
            return false;

        try
        {
            if (GetConsoleMode(handle, out uint mode))
                SetConsoleMode(handle, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
            return WriteConsole(handle, text, (uint)text.Length, out uint written, IntPtr.Zero) && written > 0;
        }
        finally
        {
            CloseHandle(handle);
        }
    }

    public bool WriteEscapeSequence(string sequence)
    {
        int currentPid = Process.GetCurrentProcess().Id;
        var visited = new System.Collections.Generic.HashSet<int>();

        for (int i = 0; i < 20; i++)
        {
            int parentPid = GetParentPid(currentPid);
            if (parentPid <= 0 || visited.Contains(parentPid)) break;
            visited.Add(parentPid);

            FreeConsole();
            if (AttachConsole((uint)parentPid) && GetConsoleWindow() != IntPtr.Zero)
            {
                if (WriteToConsole(sequence))
                    return true;
            }
            currentPid = parentPid;
        }
        return false;
    }
}

#endregion

#region MCP Tools

[McpServerToolType]
public class NotificationTools
{
    private readonly ConsoleHelper _console;

    public NotificationTools(ConsoleHelper console)
    {
        _console = console;
    }

    [McpServerTool(Name = "send_toast"), Description("Send a Windows toast notification.")]
    public Task<string> SendToast(
        [Description("The notification message")] string message,
        [Description("The notification title (default: 'Claude Code')")] string title = "Claude Code",
        CancellationToken cancellationToken = default)
    {
        try
        {
            // Escape for PowerShell/XML
            string escapedTitle = EscapeXml(title);
            string escapedMessage = EscapeXml(message);

            string psCommand = $@"
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
$template = @'
<toast>
    <visual>
        <binding template=""ToastText02"">
            <text id=""1"">{escapedTitle}</text>
            <text id=""2"">{escapedMessage}</text>
        </binding>
    </visual>
    <audio src=""ms-winsoundevent:Notification.Default""/>
</toast>
'@
$xml = New-Object Windows.Data.Xml.Dom.XmlDocument
$xml.LoadXml($template)
$toast = New-Object Windows.UI.Notifications.ToastNotification $xml
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('Claude Code').Show($toast)
";

            var psi = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{psCommand.Replace("\"", "\\\"")}\"",
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };

            using var process = Process.Start(psi);
            process?.WaitForExit(5000);

            return Task.FromResult($"Toast notification sent: [{title}] {message}");
        }
        catch (Exception ex)
        {
            return Task.FromResult($"Error sending toast: {ex.Message}");
        }
    }

    // Color definitions: (WezTerm hex, Windows Terminal DECAC index, WT progress state)
    // Progress states: 0=hidden, 1=normal, 2=error, 3=indeterminate, 4=warning
    static readonly Dictionary<string, (string Hex, int Index, int Progress)> Colors = new(StringComparer.OrdinalIgnoreCase)
    {
        // Semantic colors
        ["reset"]     = ("",        -1, 0),

        // Catppuccin Mocha palette
        ["rosewater"] = ("#f5e0dc",  9, 1),
        ["flamingo"]  = ("#f2cdcd",  9, 1),
        ["pink"]      = ("#f5c2e7", 13, 1),
        ["mauve"]     = ("#cba6f7",  5, 1),
        ["red"]       = ("#f38ba8",  1, 2),
        ["maroon"]    = ("#eba0ac",  9, 2),
        ["peach"]     = ("#fab387", 11, 4),
        ["yellow"]    = ("#f9e2af",  3, 4),
        ["green"]     = ("#a6e3a1",  2, 0),
        ["teal"]      = ("#94e2d5",  6, 1),
        ["sky"]       = ("#89dceb", 14, 1),
        ["sapphire"]  = ("#74c7ec", 12, 3),
        ["blue"]      = ("#89b4fa",  4, 3),
        ["lavender"]  = ("#b4befe", 13, 1),

        // Standard terminal colors
        ["black"]     = ("#45475a",  0, 1),
        ["white"]     = ("#cdd6f4", 15, 1),
        ["cyan"]      = ("#94e2d5",  6, 1),
        ["magenta"]   = ("#cba6f7",  5, 1),
        ["orange"]    = ("#fab387", 11, 4),
        ["purple"]    = ("#cba6f7",  5, 1),
        ["gray"]      = ("#6c7086",  8, 1),
        ["grey"]      = ("#6c7086",  8, 1),
    };

    static readonly string AvailableColors = string.Join(", ", Colors.Keys);

    [McpServerTool(Name = "flash_tab"), Description("Change terminal tab color for visual attention. Works with both WezTerm and Windows Terminal.")]
    public Task<string> FlashTab(
        [Description("Color name: 'blue' (working), 'green' (success), 'yellow' (attention), 'red' (error), 'reset' (clear). Also supports: rosewater, flamingo, pink, mauve, maroon, peach, teal, sky, sapphire, lavender, black, white, cyan, magenta, orange, purple, gray. Or pass a hex color like '#ff6600'.")] string color,
        CancellationToken cancellationToken = default)
    {
        try
        {
            bool isWezTerm = Environment.GetEnvironmentVariable("TERM_PROGRAM") == "WezTerm";
            string sequence;

            // Try named color first, then hex color
            if (Colors.TryGetValue(color, out var entry))
            {
                if (isWezTerm)
                {
                    string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(entry.Hex));
                    sequence = $"\x1b]1337;SetUserVar=tab_color={b64}\x07";
                }
                else
                {
                    string colorSeq = entry.Index < 0 ? "\x1b[2;0;257,|" : $"\x1b[2;0;{entry.Index},|";
                    string progressSeq = $"\x1b]9;4;{entry.Progress};{(entry.Progress == 0 ? 0 : 100)}\x07";
                    sequence = colorSeq + progressSeq;
                }
            }
            else if (Regex.IsMatch(color, @"^#?[0-9a-fA-F]{6}$"))
            {
                // Raw hex color (e.g., "#ff6600" or "ff6600")
                string hex = color.StartsWith("#") ? color : $"#{color}";

                if (isWezTerm)
                {
                    string b64 = Convert.ToBase64String(Encoding.UTF8.GetBytes(hex));
                    sequence = $"\x1b]1337;SetUserVar=tab_color={b64}\x07";
                }
                else
                {
                    // For Windows Terminal, find the nearest standard color index
                    int nearest = FindNearestColorIndex(hex);
                    string colorSeq = $"\x1b[2;0;{nearest},|";
                    string progressSeq = "\x1b]9;4;1;100\x07"; // normal progress for custom colors
                    sequence = colorSeq + progressSeq;
                }
            }
            else
            {
                return Task.FromResult($"Unknown color '{color}'. Available: {AvailableColors}, or a hex color like '#ff6600'");
            }

            bool success = _console.WriteEscapeSequence(sequence);
            string terminal = isWezTerm ? "WezTerm" : "Windows Terminal";
            return Task.FromResult(success
                ? $"Tab color set to '{color}' on {terminal}"
                : $"Could not find console to write to (tried {terminal} escape sequences)");
        }
        catch (Exception ex)
        {
            return Task.FromResult($"Error setting tab color: {ex.Message}");
        }
    }

    // Map the 16 standard terminal color indices to approximate RGB values
    static readonly (int R, int G, int B)[] TerminalRgb =
    {
        (0, 0, 0),       // 0  black
        (197, 15, 31),   // 1  red
        (19, 161, 14),   // 2  green
        (193, 156, 0),   // 3  yellow
        (0, 55, 218),    // 4  blue
        (136, 23, 152),  // 5  magenta
        (58, 150, 221),  // 6  cyan
        (204, 204, 204), // 7  white
        (118, 118, 118), // 8  bright black (gray)
        (231, 72, 86),   // 9  bright red
        (22, 198, 12),   // 10 bright green
        (249, 241, 165), // 11 bright yellow
        (59, 120, 255),  // 12 bright blue
        (180, 0, 158),   // 13 bright magenta
        (97, 214, 214),  // 14 bright cyan
        (242, 242, 242), // 15 bright white
    };

    static int FindNearestColorIndex(string hex)
    {
        hex = hex.TrimStart('#');
        int r = int.Parse(hex.Substring(0, 2), NumberStyles.HexNumber);
        int g = int.Parse(hex.Substring(2, 2), NumberStyles.HexNumber);
        int b = int.Parse(hex.Substring(4, 2), NumberStyles.HexNumber);

        int bestIndex = 0;
        int bestDist = int.MaxValue;
        for (int i = 0; i < TerminalRgb.Length; i++)
        {
            var (tr, tg, tb) = TerminalRgb[i];
            int dist = (r - tr) * (r - tr) + (g - tg) * (g - tg) + (b - tb) * (b - tb);
            if (dist < bestDist)
            {
                bestDist = dist;
                bestIndex = i;
            }
        }
        return bestIndex;
    }

    static string EscapeXml(string s) =>
        s.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;")
         .Replace("\"", "&quot;").Replace("'", "&apos;");
}

#endregion

#region Main

var builder = Host.CreateApplicationBuilder(Args.ToArray());

builder.Services.AddSingleton<ConsoleHelper>();

builder.Services
    .AddMcpServer()
    .WithStdioServerTransport()
    .WithTools<NotificationTools>();

// MCP uses stdout for JSON-RPC protocol - all logs MUST go to stderr
builder.Logging.SetMinimumLevel(LogLevel.Warning);
builder.Logging.AddConsole(options =>
{
    options.LogToStandardErrorThreshold = LogLevel.Trace;
});

await builder.Build().RunAsync();

#endregion
