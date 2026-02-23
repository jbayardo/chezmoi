// SendNotification.csx - Run with: dotnet script SendNotification.csx
// Reads hook JSON from stdin and sends a Windows toast notification with task context

using System;
using System.IO;
using System.Text.Json;

// Read JSON input from stdin
string jsonInput = Console.In.ReadToEnd();
string title = "Claude Code";
string message = "Task completed";

try
{
    using var doc = JsonDocument.Parse(jsonInput);
    var root = doc.RootElement;

    // Try to get transcript path and extract last assistant message
    if (root.TryGetProperty("transcript_path", out var transcriptPathEl))
    {
        string transcriptPath = transcriptPathEl.GetString();
        if (!string.IsNullOrEmpty(transcriptPath) && File.Exists(transcriptPath))
        {
            // Read last few lines of transcript to find context
            var lines = File.ReadAllLines(transcriptPath);
            string lastAssistantMessage = null;

            // Search backwards for last assistant message
            for (int i = lines.Length - 1; i >= 0 && i >= lines.Length - 20; i--)
            {
                try
                {
                    using var lineDoc = JsonDocument.Parse(lines[i]);
                    var lineRoot = lineDoc.RootElement;

                    if (lineRoot.TryGetProperty("type", out var typeEl) &&
                        typeEl.GetString() == "assistant" &&
                        lineRoot.TryGetProperty("message", out var msgEl) &&
                        msgEl.TryGetProperty("content", out var contentEl))
                    {
                        // Extract text from content array
                        foreach (var item in contentEl.EnumerateArray())
                        {
                            if (item.TryGetProperty("type", out var itemType) &&
                                itemType.GetString() == "text" &&
                                item.TryGetProperty("text", out var textEl))
                            {
                                lastAssistantMessage = textEl.GetString();
                                break;
                            }
                        }
                        if (lastAssistantMessage != null) break;
                    }
                }
                catch { }
            }

            if (!string.IsNullOrEmpty(lastAssistantMessage))
            {
                // Truncate to reasonable length for notification
                message = lastAssistantMessage.Length > 200
                    ? lastAssistantMessage.Substring(0, 197) + "..."
                    : lastAssistantMessage;
                // Clean up newlines for notification
                message = message.Replace("\r\n", " ").Replace("\n", " ").Trim();
            }
        }
    }
}
catch
{
    // Fall back to default message on any parse error
}

// Escape for PowerShell/XML
string escapedTitle = title.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&apos;");
string escapedMessage = message.Replace("&", "&amp;").Replace("<", "&lt;").Replace(">", "&gt;").Replace("\"", "&quot;").Replace("'", "&apos;");

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

var psi = new System.Diagnostics.ProcessStartInfo
{
    FileName = "powershell.exe",
    Arguments = $"-NoProfile -ExecutionPolicy Bypass -Command \"{psCommand.Replace("\"", "\\\"")}\"",
    UseShellExecute = false,
    CreateNoWindow = true,
    RedirectStandardOutput = true,
    RedirectStandardError = true
};

try
{
    using var process = System.Diagnostics.Process.Start(psi);
    process?.WaitForExit(5000);
}
catch
{
    // Silently fail - notification is non-critical
}
