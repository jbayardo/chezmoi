function global:Search-Code {
  # check if PSFzf is loaded
  if (Get-Command Invoke-PsFzfRipgrep -ErrorAction SilentlyContinue) {
    Invoke-PsFzfRipgrep $args
    return
  }
  else {
    $InitialQuery = $args
    $CommandPrefix = "rg --column --color=always --line-number --no-heading "
    $Env:FZF_DEFAULT_COMMAND = "$CommandPrefix $InitialQuery"; fzf --ansi --disabled --color "hl:-1:underline,hl+:-1:underline:reverse" --delimiter : --preview 'bat --color=always {1} --highlight-line {2}' --preview-window 'up,60%,border-bottom,+{2}+3/3,~3' --bind 'enter:execute-silent(code --reuse-window -g {1}:{2}:{3})' --bind "change:reload:sleep 0.1; $CommandPrefix {q} || true" --bind "alt-enter:unbind(change,alt-enter)+change-prompt(2. fzf> )+enable-search+clear-query" --prompt '1. ripgrep> ' --query "$InitialQuery" 
  }
}
New-Alias -Name cs -Value Search-Code -Force