[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing") 
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms") 

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Mouse {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int x, int y);

    public static void MoveMouse(int x, int y) {
        SetCursorPos(x, y);
    }
}
"@

while($true) {
    Start-Sleep -Seconds 1

    # Get the current cursor position
    $pos = [System.Windows.Forms.Cursor]::Position

    # Move the mouse cursor slightly
    [Mouse]::MoveMouse([int]$pos.X + 10, [int]$pos.Y + 10)
}
