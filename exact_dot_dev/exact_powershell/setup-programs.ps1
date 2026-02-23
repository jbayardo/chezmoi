# - Enable Developer mode
# - Enable PowerShell scripts
# - Install Git (winget)
# - Install Chezmoi (winget)
# - Install Visual Studio (installer?)
param(
  [Parameter(Mandatory)]
  [ValidateSet("Work", "Personal")]
  $Setup,

  [switch]$PowerShell,
  [switch]$Python,
  [switch]$Winget,
  [switch]$Scoop,
  [switch]$Rust,
  [switch]$Go,
  [switch]$Dotnet
)

if ($Node) {
  if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    throw "Node.js is not installed"
  }

  npm install -g @github/copilot
  npm install -g @openai/codex
  npm install -g @anthropic-ai/claude-code
}

if ($Python) {
  if (-not (Get-Command uv -ErrorAction SilentlyContinue)) {
    powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
  }

  uv tool install aider-chat
  uv tool install llm
  uv tool install paginate-json
  uv tool install csvkit
  uv tool install toolong
  uv tool install visidata

  llm install llm-cmd
  llm install llm-python
  llm install llm-cluster
  llm install llm-gpt4all
  llm install llm-sentence-transformers
  llm install llm-clip
  llm install llm-embed-onnx
  # llm install llm-llama-cpp
  # llm install llama-cpp-python
}

if ($PowerShell) {
  if (-not (Get-Command aish -ErrorAction SilentlyContinue)) {
    Invoke-Expression "& { $(Invoke-RestMethod 'https://aka.ms/install-aishell.ps1') }"
  }

  if (Get-Command "oh-my-posh") {
    oh-my-posh disable notice
  }

  # Download modules
  $Modules = @(
    @{Name = "posh-git"; RequiredVersion = $null },
    @{Name = "Posh-SSH"; RequiredVersion = $null },
    @{Name = "PSReadLine"; RequiredVersion = $null },
    @{Name = "PSFzf"; RequiredVersion = "2.6.7" },
    @{Name = "PSParseHTML"; RequiredVersion = $null },
    @{Name = "PSWriteHTML"; RequiredVersion = $null },
    @{Name = "PSWritePDF"; RequiredVersion = $null },
    @{Name = "PSWriteOffice"; RequiredVersion = $null },
    @{Name = "BurntToast"; RequiredVersion = $null },
    @{Name = "Az"; RequiredVersion = $null },
    @{Name = "Az.Tools.Predictor"; RequiredVersion = $null },
    @{Name = "CompletionPredictor"; RequiredVersion = $null },
    @{Name = "DirectoryPredictor"; RequiredVersion = $null },
    @{Name = "Terminal-Icons"; RequiredVersion = $null },
    @{Name = "Microsoft.Graph"; RequiredVersion = $null }
  )

  Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
  foreach ($module in $Modules) {
    $moduleName = $module.Name
    if (Get-Module -Name $moduleName -ListAvailable) {
      Write-Output "Module $moduleName is already installed"
      continue
    }
    
    Write-Output "Installing module $moduleName"
    $params = @{
      Name               = $moduleName
      Scope              = "CurrentUser"
      SkipPublisherCheck = $true
      AllowPrerelease    = $true
      Force              = $true
    }
    
    if ($module.RequiredVersion) {
      $params.RequiredVersion = $module.RequiredVersion
      Write-Output "Using specific version: $($module.RequiredVersion)"
    }
    
    Install-Module @params
  }
}

$Baseline = @(
  "twpayne.chezmoi",
  "KeePassXCTeam.KeePassXC",
  "Git.Git",
  "Microsoft.PowerShell",
  "Microsoft.WindowsTerminal",
  "Microsoft.VisualStudioCode",
  "9P7KNL5RWT25", # Sysinternals Suite
  "Microsoft.WinDbg",
  "Microsoft.OpenJDK.21",
  "GoLang.Go",
  "rustup",
  "CoreyButler.NVMforWindows", # https://github.com/coreybutler/nvm-windows
  "VideoLAN.VLC",
  "Gyan.FFmpeg",
  "Microsoft.OpenSSH.Preview",
  "NathanBeals.WinSSH-Pageant",
  "GnuPG.GnuPG",
  "7zip.7zip",
  "hpjansson.Chafa" # https://hpjansson.org/chafa/download/
)

$Cosmetic = @(
  "Microsoft.PowerToys",
  "XP8JK4HZBVF435", # Auto Dark Mode
  # "pit-ray.win-vind",
  # "LGUG2Z.komorebi",
  # "LGUG2Z.komokana",
  # "LGUG2Z.whkd",
  # "emoacht.Monitorian",
  "AntibodySoftware.WizTree"
  # "Espanso.Espanso", # https://espanso.org
  # "9MVPJXNSKDRR", # CtrlHelp
  # "Ditto.Ditto",
  # "BlastApps.FluentSearch"
)

$Development = @(
  "Docker.DockerDesktop",
  "Anaconda.Miniconda3",
  "SWI-Prolog.SWI-Prolog",
  "UniversalCtags.Ctags",
  # Standard UNIX tooling
  "mbuilov.sed",
  "GnuWin32.Bison",
  "GnuWin32.Cpio",
  "GnuWin32.DiffUtils",
  "GnuWin32.File",
  "GnuWin32.Flex",
  "GnuWin32.GetText",
  "GnuWin32.Grep",
  "GnuWin32.Gzip",
  "GnuWin32.M4",
  "GnuWin32.Make",
  "GnuWin32.UnZip",
  "GnuWin32.Zip",
  "GnuWin32.FindUtils",
  "GnuWin32.Gperf",
  "GnuWin32.Tar",
  "GnuWin32.Tree",
  "GnuWin32.Which",
  "GNU.Wget2",
  "JernejSimoncic.Wget",
  "cURL.cURL",
  "waterlan.dos2unix",
  "SQLite.SQLite"
  # "beekeeper-studio.beekeeper-studio",
  # "Genivia.ugrep",
  # "hoppscotch.Hoppscotch"
  # TODO: qgrep https://github.com/zeux/qgrep
)

$CppDevelopment = @(
  "LLVM",
  "cmake"
)

$CommandLine = @(
  "stedolan.jq",
  "jftuga.less",
  "sharkdp.bat",
  "fzf",
  "noborus.ov", # https://github.com/noborus/ov
  "JesseDuffield.lazygit", # https://github.com/jesseduffield/lazygit
  "sharkdp.hyperfine", # https://github.com/sharkdp/hyperfine
  "aria2.aria2", # https://github.com/aria2/aria2 
  "Neovim.Neovim", # https://github.com/neovim/neovim
  "dziemborowicz.hourglass",
  "GitHub.cli",
  "The Silver Searcher", # https://github.com/ggreer/the_silver_searcher
  "yq", # https://github.com/mikefarah/yq
  "PaddiM8.kalker",
  "dandavison.delta", # https://github.com/dandavison/delta
  "Miller.Miller", # https://github.com/johnkerl/miller
  "gokcehan.lf", # TODO: customize
  "simonmichael.hledger",
  "ImageMagick.Q16-HDRI" # https://imagemagick.org
)

$Pwsh = @(
  "Microsoft.PowerShell",
  "JanDeDobbeleer.OhMyPosh",
  "zoxide"
)

$Networking = @(
  "WiresharkFoundation.Wireshark",
  "Insecure.Nmap",
  "Rclone.Rclone"
)

$Privacy = @(
  "Safing.Portmaster"
)

$Work = @(
  "Helm.Helm",
  "Hashicorp.Terraform",
  "JetBrains.Toolbox",
  "LINQPad.LINQPad.7",
  "icsharpcode.ILSpy",
  "KirillOsenkov.MSBuildStructuredLogViewer",
  "9WZDNCRDMDM3", # NuGet Package Explorer
  "9NDD8CVPBZB6", # Regex Hero
  "Microsoft.AzureCLI",
  "Microsoft.Azure.StorageExplorer",
  "Microsoft.Azure.StorageEmulator",
  "Microsoft.Azure.AZCopy.10",
  "Bonnefon.glogg",
  "Telerik.Fiddler.Classic",
  "Meld.Meld"
)

# Microsoft.VisualStudio.2022.Community

$HardwareDrivers = @(
  "Garmin.Express",
  "Logitech.OptionsPlus", # Logitech Vertical Mouse
  "9NK75KF67S2N", # Tobii Gaming Experience
  "MichaelTippach.ASIO4ALL"
  # TODO: bose updater
  # TODO: zoleo?
  # TODO: gopro
  # TODO: footswitch
  # TODO: elektron, arturia, ableton live
)

$Gaming = @(
  "Mega.MEGASync",
  "Valve.Steam"
)

$Extra = @(
  "calibre.calibre",
  "Anki.Anki",
  "qBittorrent.qBittorrent",
  "OpenBB-finance.OpenBBTerminal",
  "yt-dlp.yt-dlp",
  "9WZDNCRFHWQT", # Drawboard PDF
  "9NKSQGP7F2NH", # WhatsApp
  "OpenShot.OpenShot",
  "DigitalScholar.Zotero",
  "Mozilla.Firefox",
  "Adobe.Acrobat.Reader.64-bit",
  "Cyanfish.NAPS2",
  "SyncTrayzor.SyncTrayzor",
  "Spotify.Spotify"
)

# # TODO: ghcup
if ($Setup -eq "Personal") {
  $WingetPackages = $Baseline + $Cosmetic + $Development + $CppDevelopment + $CommandLine + $Pwsh + $Networking + $Privacy + $HardwareDrivers + $Gaming + $Extra
}
elseif ($Setup -eq "Work") {
  $WingetPackages = $Baseline + $Cosmetic + $Development + $CppDevelopment + $CommandLine + $Pwsh + $Networking + $Work
}

if ($Winget) {
  foreach ($package in $WingetPackages) {
    winget install --accept-package-agreements --accept-source-agreements --silent --disable-interactivity $package
  }

  winget install --accept-package-agreements --accept-source-agreements --silent --disable-interactivity --location C:\ahk AutoHotkey.AutoHotkey
  Add-PathVariable C:\ahk\v2

  if ($null -ne (Get-Command nvm -ErrorAction SilentlyContinue)) {
    nvm install latest
    nvm use latest
  }
}

$ScoopPackages = @(
  "ack",
  "gawk",
  "bind",
  "fq",
  "qsv", # https://github.com/jqnatividad/qsv
  "duf", # https://github.com/muesli/duf
  "fx",
  "dua",
  "firacode",
  "pipx", # https://github.com/pypa/pipx
  "kanata", # https://github.com/jtroo/kanata
  # WHY: Supports PDF previews in yazi
  "poppler", # https://poppler.freedesktop.org/

  "FiraCode-NF-Mono",
  "FiraCode"
)

if ($Scoop) {
  if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
    Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
  }

  scoop bucket add w-bucket https://github.com/hors-org/w-bucket
  scoop bucket add extras
  scoop bucket add nerd-fonts

  foreach ($package in $ScoopPackages) {
    scoop install $package
  }
}

if ($null -ne (Get-Command gh -ErrorAction SilentlyContinue)) {
  $authStatus = gh auth status | Out-String
  if ($authStatus -notmatch "Logged in to github.com") {
    gh auth login
  }

  $extensions = gh extension list | Out-String
  if ($extensions -notmatch "gh-copilot") {
    gh extension install github/gh-copilot
  }
  else {
    gh extension upgrade gh-copilot
  }
}

# goobook
# https://github.com/zix99/rare
# https://github.com/homeport/dyff
# https://github.com/newsboat/newsboat
# https://github.com/wustho/epr
# https://github.com/jarun/Buku
# https://github.com/GothenburgBitFactory/timewarrior
# https://github.com/TailorDev/Watson
# https://taskwarrior.org/
# https://dianne.skoll.ca/projects/remind/
# https://github.com/benibela/xidel/
# https://github.com/saulpw/visidata
# https://taskell.app/
# Translate
# Spelling
# Search google
# Sed
# Awk
# Fdupes
# https://github.com/dbohdan/structured-text-tools
# https://github.com/anishathalye/periscope
# https://charm.sh/
$CargoPackages = @(
  "cargo-update",
  "cargo-binstall",
  
  # Navigation
  "broot", # https://github.com/Canop/broot

  # Searching
  "ripgrep", # https://github.com/BurntSushi/ripgrep
  "fselect", # https://github.com/jhspetersson/fselect
  "fd-find", # https://github.com/sharkdp/fd
  "ag", # https://crates.io/crates/ag
  "ast-grep", # https://ast-grep.github.io/

  # Networking
  "gping", # https://github.com/orf/gping
  "trippy", # https://github.com/fujiapple852/trippy

  # Disk Usage
  "kondo", # https://github.com/tbillington/kondo

  # Monitoring
  "bottom", # https://github.com/ClementTsang/bottom

  # Visualization
  "tidy-viewer", # https://crates.io/crates/tidy-viewer
  "csvlens", # https://github.com/YS-L/csvlens

  # Code Manipulation
  "difftastic", # https://github.com/Wilfred/difftastic
  "grex", # https://crates.io/crates/grex
  "tokei", # https://github.com/XAMPPRocky/tokei
  "sensei", # https://crates.io/crates/sensei

  # Automation
  "just", # https://github.com/casey/just
  "watchexec-cli", # https://github.com/watchexec/watchexec
  "sd", # https://github.com/chmln/sd
  "choose" # https://github.com/theryangeary/choose

  # Renaming
  "rnr", # https://github.com/ismaelgv/rnr
  "pipe-rename", # https://crates.io/crates/pipe-rename
  "ruplacer", # https://crates.io/crates/ruplacer
  "nomino", # https://github.com/yaa110/nomino
  
  # Data Manipulation
  "htmlq", # https://crates.io/crates/htmlq
  "rpdf", # https://crates.io/crates/rpdf
  "names", # https://crates.io/crates/names
  "qsv", # https://github.com/dathere/qsv
  "csview", # https://github.com/wfxr/csview

  "topgrade", # https://github.com/topgrade-rs/topgrade
  "bandwhich", # https://github.com/imsnif/bandwhich/
  "gping", # https://github.com/orf/gping
  "navi",
  "aichat",
  "srgn", # https://github.com/alexpovel/srgn

  "gfold", # https://github.com/nickgerace/gfold
  "sigrs", # https://github.com/ynqa/sigrs
  "logu", # https://github.com/ynqa/logu
  "television", # https://github.com/alexpasmantier/television/
  "wthrr", # https://github.com/ttytm/wthrr-the-weathercrab
  "procs", # https://github.com/dalance/procs

  "yazi-fm", # https://yazi-rs.github.io/docs/installation
  "yazi-cli",

  "rage", # https://github.com/str4d/rage
  "viddy", # https://github.com/sachaos/viddy
  "numbat-cli", # https://github.com/sharkdp/numbat

  "rustic-rs" # https://github.com/rustic-rs/rustic
)

$CargoUninstall = @(
  "gitoxide", # https://crates.io/crates/gitoxide
  "lethe", # https://crates.io/crates/Lethe
  "asn-tools", # https://sr.ht/~jpastuszek/asn-tools/
  "coreutils", # https://crates.io/crates/coreutils
  "geolocate", # https://crates.io/crates/geolocate
  "grex", # https://github.com/pemistahl/grex
  "hoard-rs", # https://crates.io/crates/hoard-rs
  "killport", # https://github.com/jkfran/killport
  "lowcharts", # https://github.com/juan-leon/lowcharts
  "lsd", # https://crates.io/crates/lsd
  "qsv", # https://github.com/tbillington/kondo
  "ripcalc", # https://crates.io/crates/ripcalc
  "rust-wc", # https://crates.io/crates/rust-wc
  "rz", # https://crates.io/crates/rz
  "screenlocker", # https://crates.io/crates/screenlocker
  "superdiff", # https://crates.io/crates/superdiff
  "tbr", # https://crates.io/crates/tbr
  "tealdeer", # https://crates.io/crates/tealdeer
  "tmplt", # https://crates.io/crates/tmplt
  "ttyper", # https://crates.io/crates/ttyper
  "tu", # https://github.com/ad-si/tu
  "watchdiff", # https://crates.io/crates/watchdiff
  "when-cli", # https://github.com/mitsuhiko/when
  "tree-sitter-cli"
)


if ($Rust) {
  $InstallFailures = @()
  $UninstallFailures = @()

  if ($null -eq (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Error "Rust is not installed"
  }
  else {
    $GithubToken = $null
    if (Get-Command gh -ErrorAction SilentlyContinue) {
      $GithubToken = (gh auth token | Out-String).Trim()
    }

    cargo install --locked cargo-binstall
    cargo install --locked cargo-update

    # cargo install qsv --locked --bin qsv -F all_features, magic

    foreach ($package in $CargoPackages) {
      if ($null -ne $GithubToken) {
        cargo binstall --github-token $GithubToken --force --no-confirm --locked $package
      }
      else {
        cargo binstall --no-discover-github-token --force --no-confirm --locked $package
      }

      # cargo install --locked $package
      $ExitCode = $LASTEXITCODE
      if ($ExitCode -ne 0) {
        $InstallFailures += $package
      }
    }

    foreach ($package in $CargoUninstall) {
      cargo uninstall $package
      $ExitCode = $LASTEXITCODE
      if ($ExitCode -ne 0) {
        $UninstallFailures += $package
      }
    }
  }

  if ($InstallFailures.Count -gt 0) {
    Write-Error "Failed to install $InstallFailures"
  }

  if ($UninstallFailures.Count -gt 0) {
    Write-Error "Failed to uninstall $UninstallFailures"
  }
}

if ($Go) {
  if ($null -eq (Get-Command go -ErrorAction SilentlyContinue)) {
    Write-Error "Go is not installed"
  }
  else {
    $GoPath = "~/.go/path"
    $GoBin = "~/.go/bin"
    mkdir -ErrorAction SilentlyContinue $GoPath
    mkdir -ErrorAction SilentlyContinue $GoBin
    $GoPath = (Resolve-Path $GoPath).Path
    $GoBin = (Resolve-Path $GoBin).Path

    Add-PathVariable $GoPath
    Set-EnvironmentVariable -Name "GOBIN" -Value $GoBin

    go install github.com/Code-Hex/pget/cmd/pget@latest
    go install github.com/sibprogrammer/xq@latest
    go install github.com/tomwright/dasel/v2/cmd/dasel@master
    go install github.com/google/codesearch/cmd/...@latest
    go install github.com/sinclairtarget/git-who@latest
  }
}

if ($Dotnet) {
  if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    Write-Error "Dotnet is not installed"
  }
  else {
    $DotnetTools = @(
      "dotnet-dump",
      "dotnet-interactive",
      "dotnet-trace",
      "dotnet-coverage",
      "dotnet-counters",
      "dotnet-gcdump",
      "dotnet-format",
      "dotnet-sos",
      "dotnet-stack",
      "dotnet-ef",
      "dotnet-aspnet-codegenerator",
      "Microsoft.VisualStudio.SlnGen.Tool",
      "Swashbuckle.AspNetCore.Cli",
      "Sarif.Multitool"
    )
    foreach ($tool in $DotnetTools) {
      dotnet tool install -g $tool
    }

    dotnet-sos install
  }
}

# create folder for symbols (example: C:\Symbols), add an environment variable _NT_SYMBOL_PATH as SRV*c:\Symbols*https://symweb. This will direct debugging tools to use the internal Microsoft symbol server, and to cache them on a common folder

# In about:config set browser.vpn_promo.enabled to false.
