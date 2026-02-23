$KanataPort = 3567
$DefaultLayerName = 'Default'
$KomokanaConfigPath = '~/.dev/input/komokana.yaml' | Resolve-Path
$KanataConfigPath = '~/.dev/input/lenovo-T15p.kbd' | Resolve-Path

# Startup win-vind. See: https://pit-ray.github.io/win-vind
# Allows using vim keybindings in Windows.
$WinVindPath = 'C:\Program Files\win-vind\win-vind.exe'
Start-Process $WinVindPath -WindowStyle hidden

# Startup kanata. See: https://github.com/jtroo/kanata
# Allows rebinding keys in Windows.
Start-Process kanata.exe -ArgumentList "-p $KanataPort -c $KanataConfigPath" -WindowStyle hidden

# Startup komorebi. See: https://github.com/LGUG2Z/komorebi
# Tiling window manager for Windows.
Start-Process komorebi.exe -ArgumentList "--await-configuration" -WindowStyle hidden
. komorebi.ahk

# Startup komokana. See: https://github.com/LGUG2Z/komokana
# Bridge beteen kanata and komorebi. Allows kanata to change layers depending on the currently active window.
Start-Process komokana.exe -ArgumentList "-p $KanataPort -d $DefaultLayerName -c $KomokanaConfigPath" -WindowStyle hidden

# Startup espanso. See: https://espanso.org/

# Startup autohotkey scripts