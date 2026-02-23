New-Alias -Force cm chezmoi

function cmpath {
  return (Resolve-Path "~/.local/share/chezmoi")
}

function global:cmh {
  Set-Location $(cmpath)
}

function global:cme {
  code $(cmpath)
}

function global:cmw {
  cme
  watchexec -vv -r -w $(cmpath) -- chezmoi apply --keep-going --force --no-pager --no-tty --refresh-externals=never
}

function global:cma {
  chezmoi apply --keep-going --force --no-pager --no-tty --refresh-externals=never
}

function global:cmr {
  cma
  reload
}
