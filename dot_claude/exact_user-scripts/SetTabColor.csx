// SetTabColor.csx - Run with: dotnet script SetTabColor.csx -- <colorIndex>
// Changes Windows Terminal tab color using DECAC escape sequence
//
// Documentation:
//   - GitHub Issue: https://github.com/microsoft/terminal/issues/6574
//   - DECAC (DEC Assign Color) format: ESC [ 2 ; Pf ; Pb , |
//   - Color indices: 0-15 = standard colors, 257 = default background

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;

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

bool WriteToCurrentConsole(string text)
{
    // Use CreateFile to get a direct handle to CONOUT$, bypassing any redirections
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

// Parse args
int colorIndex = Args.Count > 0 && int.TryParse(Args[0], out int p) ? p : 4;

bool isWezTerm = Environment.GetEnvironmentVariable("TERM_PROGRAM") == "WezTerm";

string sequence;
if (isWezTerm)
{
    // OSC 1337 SetUserVar for WezTerm tab colors (Catppuccin Mocha palette)
    var colorMap = new System.Collections.Generic.Dictionary<int, string>
    {
        { 1, "#f38ba8" }, // red - failure
        { 2, "#a6e3a1" }, // green - done
        { 3, "#f9e2af" }, // yellow - permission request
        { 4, "#89b4fa" }, // blue - working
    };
    string hexColor = colorIndex >= 0 && colorMap.ContainsKey(colorIndex) ? colorMap[colorIndex] : "";
    string b64 = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(hexColor));
    sequence = $"\x1b]1337;SetUserVar=tab_color={b64}\x07";
}
else
{
    // DECAC for Windows Terminal tab color
    string colorSeq = colorIndex < 0 ? "\x1b[2;0;257,|" : $"\x1b[2;0;{colorIndex},|";

    // OSC 9;4 progress bar: state 0=hidden, 1=normal, 2=error, 3=indeterminate, 4=warning
    string progressSeq = colorIndex switch
    {
        -1 => "\x1b]9;4;0;0\x07",   // reset - hide progress
        1 => "\x1b]9;4;2;100\x07",   // red/failure - error state
        2 => "\x1b]9;4;0;0\x07",     // green/done - hide progress
        3 => "\x1b]9;4;4;100\x07",   // yellow/permission - warning state
        4 => "\x1b]9;4;3;0\x07",     // blue/working - indeterminate
        _ => "\x1b]9;4;0;0\x07",
    };

    sequence = colorSeq + progressSeq;
}

// Find first ancestor with a visible console window and write to it
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
        if (WriteToCurrentConsole(sequence))
            return;
    }
    currentPid = parentPid;
}
