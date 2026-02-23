Import-Module PSReadLine

# Remove the annoying bell sound
Set-PSReadLineOption -BellStyle None

# Enable searching history the usual way in UNIX shells
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete
Set-PSReadlineKeyHandler -Key UpArrow -Function HistorySearchBackward
Set-PSReadlineKeyHandler -Key DownArrow -Function HistorySearchForward

# Enable predictive intellisense
Import-Module CompletionPredictor
Import-Module DirectoryPredictor
Set-PSReadLineOption -PredictionSource HistoryAndPlugin 
Set-PSReadLineOption -PredictionViewStyle ListView

# See: https://learn.microsoft.com/en-us/powershell/azure/az-predictor?view=azps-11.2.0

try {
  Enable-AzPredictor
  Disable-AzDataCollection
}
catch {

}

function Get-SyncPath {
  $SyncPath = "~/Sync" | Resolve-Path
  if (Test-Path -PathType Container $SyncPath) {
    return $SyncPath;
  }

  if (-not $IsWindows) {
    return $null;
  }

  # Unrolls the loop to prevent accessing env / registry unnecessarily
  $Path = $env:OneDriveCommercial
  if (($null -ne $Path) -and (Test-Path -PathType Container $Path)) {
    return $Path;
  }

  $Path = $env:OneDriveConsumer
  if (($null -ne $Path) -and (Test-Path -PathType Container $Path)) {
    return $Path;
  }

  $Path = $env:OneDrive
  if (($null -ne $Path) -and (Test-Path -PathType Container $Path)) {
    return $Path;
  }

  $Path = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Business1").UserFolder
  if (($null -ne $Path) -and (Test-Path -PathType Container $Path)) {
    return $Path;
  }

  $Path = (Get-ItemProperty -Path "HKCU:\SOFTWARE\Microsoft\OneDrive\Accounts\Personal").UserFolder
  if (($null -ne $Path) -and (Test-Path -PathType Container $Path)) {
    return $Path;
  }

  return $null;
}

# TODO: history handler to filter sensitive commands
# TODO: command validation handler for help
# TODO: predictor using LLM. See: https://learn.microsoft.com/en-us/powershell/scripting/dev-cross-plat/create-cmdline-predictor?view=powershell-7.4
Set-PSReadLineOption -MaximumHistoryCount 32768
Set-PSReadLineOption -HistoryNoDuplicates
Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
Set-PSReadLineOption -HistorySearchCursorMovesToEnd

# Make Ctrl + Backspace delete the previous word when using vscode.
if ($env:TERM_PROGRAM -eq "vscode") {
  Set-PSReadLineKeyHandler -Chord 'Ctrl+w' -Function BackwardKillWord
}

Set-PSReadlineKeyHandler -Key Ctrl+Shift+P `
  -BriefDescription CopyPathToClipboard `
  -LongDescription "Copies the current path to the clipboard" `
  -ScriptBlock {
  Set-Clipboard ((Resolve-Path -LiteralPath $pwd).ProviderPath.Trim())
}

Set-PSReadLineKeyHandler -Key Ctrl+b `
  -BriefDescription BuildCurrentDirectory `
  -LongDescription "Build the current directory" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet build")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+i `
  -BriefDescription OpenIDE `
  -LongDescription "Open IDE for the current directory" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("vs")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+t `
  -BriefDescription RunTest `
  -LongDescription "Run tests for the current directory" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet test")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+e `
  -BriefDescription Edit `
  -LongDescription "Fuzzy find a place to edit" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("edit")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+g `
  -BriefDescription GoTo `
  -LongDescription "Fuzzy name search on subfolders" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("goto")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Key Ctrl+h `
  -BriefDescription GoToRepo `
  -LongDescription "Fuzzy name search on repositories" `
  -ScriptBlock {
  [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert("gg")
  [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadlineKeyHandler -Chord Ctrl+\ `
  -BriefDescription SearchForwardPipeChar `
  -Description "Searches forward for the next pipeline character" `
  -ScriptBlock {
  param($key, $arg)
  [Microsoft.PowerShell.PSConsoleReadLine]::CharacterSearch($key, '|')
}

Set-PSReadlineKeyHandler -Chord Ctrl+Shift+\ `
  -BriefDescription SearchBackwardPipeChar `
  -Description "Searches backward for the next pipeline character" `
  -ScriptBlock {
  param($key, $arg)
  [Microsoft.PowerShell.PSConsoleReadLine]::CharacterSearchBackward($key, '|')
}

Set-PSReadLineKeyHandler -Key '"', "'" `
  -BriefDescription SmartInsertQuote `
  -LongDescription "Insert paired quotes if not already on a quote" `
  -ScriptBlock {
  param($key, $arg)

  $quote = $key.KeyChar

  $selectionStart = $null
  $selectionLength = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

  $line = $null
  $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

  # If text is selected, just quote it without any smarts
  if ($selectionStart -ne -1) {
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $quote + $line.SubString($selectionStart, $selectionLength) + $quote)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
    return
  }

  $ast = $null
  $tokens = $null
  $parseErrors = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$ast, [ref]$tokens, [ref]$parseErrors, [ref]$null)

  function FindToken {
    param($tokens, $cursor)

    foreach ($token in $tokens) {
      if ($cursor -lt $token.Extent.StartOffset) { continue }
      if ($cursor -lt $token.Extent.EndOffset) {
        $result = $token
        $token = $token -as [StringExpandableToken]
        if ($token) {
          $nested = FindToken $token.NestedTokens $cursor
          if ($nested) { $result = $nested }
        }

        return $result
      }
    }
    return $null
  }

  $token = FindToken $tokens $cursor

  # If we're on or inside a **quoted** string token (so not generic), we need to be smarter
  if ($token -is [StringToken] -and $token.Kind -ne [TokenKind]::Generic) {
    # If we're at the start of the string, assume we're inserting a new string
    if ($token.Extent.StartOffset -eq $cursor) {
      [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote ")
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
      return
    }

    # If we're at the end of the string, move over the closing quote if present.
    if ($token.Extent.EndOffset -eq ($cursor + 1) -and $line[$cursor] -eq $quote) {
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
      return
    }
  }

  if ($null -eq $token -or
    $token.Kind -eq [TokenKind]::RParen -or $token.Kind -eq [TokenKind]::RCurly -or $token.Kind -eq [TokenKind]::RBracket) {
    if ($line[0..$cursor].Where{ $_ -eq $quote }.Count % 2 -eq 1) {
      # Odd number of quotes before the cursor, insert a single quote
      [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
    }
    else {
      # Insert matching quotes, move cursor to be in between the quotes
      [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$quote$quote")
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
    }
    return
  }

  # If cursor is at the start of a token, enclose it in quotes.
  if ($token.Extent.StartOffset -eq $cursor) {
    if ($token.Kind -eq [TokenKind]::Generic -or $token.Kind -eq [TokenKind]::Identifier -or 
      $token.Kind -eq [TokenKind]::Variable -or $token.TokenFlags.hasFlag([TokenFlags]::Keyword)) {
      $end = $token.Extent.EndOffset
      $len = $end - $cursor
      [Microsoft.PowerShell.PSConsoleReadLine]::Replace($cursor, $len, $quote + $line.SubString($cursor, $len) + $quote)
      [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($end + 2)
      return
    }
  }

  # We failed to be smart, so just insert a single quote
  [Microsoft.PowerShell.PSConsoleReadLine]::Insert($quote)
}

Set-PSReadLineKeyHandler -Key '(', '{', '[' `
  -BriefDescription InsertPairedBraces `
  -LongDescription "Insert matching braces" `
  -ScriptBlock {
  param($key, $arg)

  $closeChar = switch ($key.KeyChar) {
    <#case#> '(' { [char]')'; break }
    <#case#> '{' { [char]'}'; break }
    <#case#> '[' { [char]']'; break }
  }

  $selectionStart = $null
  $selectionLength = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetSelectionState([ref]$selectionStart, [ref]$selectionLength)

  $line = $null
  $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
  
  if ($selectionStart -ne -1) {
    # Text is selected, wrap it in brackets
    [Microsoft.PowerShell.PSConsoleReadLine]::Replace($selectionStart, $selectionLength, $key.KeyChar + $line.SubString($selectionStart, $selectionLength) + $closeChar)
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($selectionStart + $selectionLength + 2)
  }
  else {
    # No text is selected, insert a pair
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)$closeChar")
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
  }
}

Set-PSReadLineKeyHandler -Key ')', ']', '}' `
  -BriefDescription SmartCloseBraces `
  -LongDescription "Insert closing brace or skip" `
  -ScriptBlock {
  param($key, $arg)

  $line = $null
  $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

  if ($line[$cursor] -eq $key.KeyChar) {
    [Microsoft.PowerShell.PSConsoleReadLine]::SetCursorPosition($cursor + 1)
  }
  else {
    [Microsoft.PowerShell.PSConsoleReadLine]::Insert("$($key.KeyChar)")
  }
}

Set-PSReadLineKeyHandler -Key Backspace `
  -BriefDescription SmartBackspace `
  -LongDescription "Delete previous character or matching quotes/parens/braces" `
  -ScriptBlock {
  param($key, $arg)

  $line = $null
  $cursor = $null
  [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

  if ($cursor -gt 0) {
    $toMatch = $null
    if ($cursor -lt $line.Length) {
      switch ($line[$cursor]) {
        <#case#> '"' { $toMatch = '"'; break }
        <#case#> "'" { $toMatch = "'"; break }
        <#case#> ')' { $toMatch = '('; break }
        <#case#> ']' { $toMatch = '['; break }
        <#case#> '}' { $toMatch = '{'; break }
      }
    }

    if ($toMatch -ne $null -and $line[$cursor - 1] -eq $toMatch) {
      [Microsoft.PowerShell.PSConsoleReadLine]::Delete($cursor - 1, 2)
    }
    else {
      [Microsoft.PowerShell.PSConsoleReadLine]::BackwardDeleteChar($key, $arg)
    }
  }
}

# $env:ATUIN_SESSION = (atuin uuid | Out-String).Trim()
# $env:ATUIN_HISTORY_ID = $null

# Set-PSReadLineKeyHandler -Chord Enter -ScriptBlock {
#   $line = $null
#   $cursor = $null
#   [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

#   if (-not $env:ATUIN_HISTORY_ID) {
#     $env:ATUIN_HISTORY_ID = (atuin history start -- $line | Out-String).Trim()
#     $global:ATUIN_HISTORY_ELAPSED = [System.Diagnostics.Stopwatch]::StartNew()
#   }

#   [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
# }

# $existingPromptFunction = Get-Item -Path Function:\prompt
# Remove-Item -Path Function:\prompt
# function prompt {
#   if ($env:ATUIN_HISTORY_ID) {
#     $durationNs = $global:ATUIN_HISTORY_ELAPSED.ElapsedTicks * 100
#     $exitCode = $LASTEXITCODE
#     atuin history end --duration $durationNs --exit $exitCode -- $env:ATUIN_HISTORY_ID | Out-Null

#     Remove-Item -Path env:ATUIN_HISTORY_ID -ErrorAction SilentlyContinue
#   }

#   & $existingPromptFunction.ScriptBlock
# }

# # TODO: Fix all the bindings below
# $InvokeAtuinSearch = {
#   $keymapMode = "emacs"

#   $line = $null
#   $cursor = $null
#   [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)

#   $suggestion = (atuin search --keymap-mode=$keymapMode -i -- $line | Out-String).Trim()

#   [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()

#   if ($suggestion.StartsWith("__atuin_accept__:")) {
#     $suggestion = $suggestion.Substring(16)
#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion)
#     [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
#   }
#   else {
#     [Microsoft.PowerShell.PSConsoleReadLine]::Insert($suggestion)
#   }
# }

# $InvokeAtuinUpSearch = {
#   $bufferContent = [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferContent()
#   if (-not $bufferContent.Contains("`n")) {
#     & $InvokeAtuinSearch -keymapMode "vim-normal"
#   }
#   else {
#     [Microsoft.PowerShell.PSConsoleReadLine]::HistorySearchBackward()
#   }
# }

# Set-PSReadLineKeyHandler -Chord "Ctrl+r" -ScriptBlock $InvokeAtuinSearch -BriefDescription "AtuinSearch" -Description "Invoke Atuin search for command history"
# Set-PSReadLineKeyHandler -Chord "UpArrow" -ScriptBlock $InvokeAtuinUpSearch -BriefDescription "AtuinUpSearch" -Description "Invoke Atuin up search or navigate history"