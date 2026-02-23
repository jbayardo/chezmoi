$SyncPath = "~/ZotSync" | Resolve-Path -ErrorAction Stop
$ZoteroPath = "~/Zotero" | Resolve-Path -ErrorAction Stop
$ZoteroStoragePath = Join-Path $ZoteroPath "storage"

# Ensure target path exists
New-Item -Type Directory $SyncPath
New-Item -Type Directory (Join-Path $SyncPath "tablet")
New-Item -Type Directory (Join-Path $SyncPath "pending")
$SyncStoragePath = Join-Path $SyncPath "storage"
New-Item -Type Directory $SyncStoragePath

New-Item -ItemType SymbolicLink -Path $ZoteroStoragePath -Target $SyncStoragePath
