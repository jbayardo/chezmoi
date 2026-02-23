-- Pull in the wezterm API
local wezterm = require 'wezterm'
local act = wezterm.action

-- This will hold the configuration.
local config = wezterm.config_builder()

local is_windows = wezterm.target_triple:find('windows') ~= nil
local is_linux = not is_windows

-- Required to work in Windows via Remote Desktop, matching for dev box
if is_windows and wezterm.hostname():match('^CPC') then
  config.prefer_egl = true
end

-- Font
config.font = wezterm.font_with_fallback {
  'JetBrains Mono',
  'Fira Code Nerd Font Mono',
  'Cascadia Code'
}

if is_linux then
  config.font_size = 10
  config.initial_cols = 120
  config.initial_rows = 28
end

-- Default working directory
if is_windows then
  if wezterm.glob('Q:/src') then
    config.default_cwd = "Q:/src/"
  else
    config.default_cwd = "C:/src/"
  end
else
  config.default_cwd = "/home/jbayardo/src"
end

-- Window behavior
config.enable_scroll_bar = true
config.window_close_confirmation = 'NeverPrompt'
config.skip_close_confirmation_for_processes_named = {
  'bash', 'sh', 'zsh', 'fish', 'tmux',
  'cmd.exe', 'pwsh.exe', 'powershell.exe', 'wsl.exe',
  'conhost.exe', 'Windows PowerShell',
}
config.exit_behavior = 'CloseOnCleanExit'
config.exit_behavior_messaging = 'Verbose'

config.scrollback_lines = 20000

-- Hyperlink rules
config.hyperlink_rules = {
   {
      regex = '\\((\\w+://\\S+)\\)',
      format = '$1',
      highlight = 1,
   },
   {
      regex = '\\[(\\w+://\\S+)\\]',
      format = '$1',
      highlight = 1,
   },
   {
      regex = '\\{(\\w+://\\S+)\\}',
      format = '$1',
      highlight = 1,
   },
   {
      regex = '<(\\w+://\\S+)>',
      format = '$1',
      highlight = 1,
   },
   {
      regex = '\\b\\w+://\\S+[)/a-zA-Z0-9-]+',
      format = '$0',
   },
   {
      regex = '\\b\\w+@[\\w-]+(\\.[\\w-]+)+\\b',
      format = 'mailto:$0',
   },
}

-- Default shell
if is_windows then
  local launch_menu = {}

  table.insert(launch_menu, {
    label = 'pwsh',
    args = { 'pwsh.exe', '-NoLogo' },
  })

  table.insert(launch_menu, {
    label = 'powershell',
    args = { 'powershell.exe', '-NoLogo' },
  })

  for _, vsvers in
    ipairs(
      wezterm.glob('Microsoft Visual Studio/20*', 'C:/Program Files (x86)')
    )
  do
    local year = vsvers:gsub('Microsoft Visual Studio/', '')
    table.insert(launch_menu, {
      label = 'x64 Native Tools VS ' .. year,
      args = {
        'cmd.exe',
        '/k',
        'C:/Program Files (x86)/'
          .. vsvers
          .. '/BuildTools/VC/Auxiliary/Build/vcvars64.bat',
      },
    })
  end

  config.launch_menu = launch_menu
  config.default_prog = { 'C:/Program Files/PowerShell/7/pwsh.exe', '-NoLogo' }
else
  config.default_prog = { "/home/jbayardo/.cargo/bin/zellij", "-l", "welcome" }
end

-- Color scheme
if is_windows then
  config.color_scheme = "Catppuccin Mocha"
else
  function get_appearance()
    if wezterm.gui then
      return wezterm.gui.get_appearance()
    end
    return "Dark"
  end

  function scheme_for_appearance(appearance)
    if appearance:find("Dark") then
      return "tokyonight"
    else
      return "tokyonight-day"
    end
  end

  config.color_scheme = scheme_for_appearance(get_appearance())
end

-- Custom tab title formatting with OSC-driven color support
wezterm.on('format-tab-title', function(tab, tabs, panes, config, hover, max_width)
  local title = tab.active_pane.title
  local index = tab.tab_index + 1
  local label = ' ' .. index .. ': ' .. title .. ' '

  local tab_color = tab.active_pane.user_vars.tab_color
  if tab_color and tab_color ~= '' then
    if tab.is_active then
      return {
        { Background = { Color = tab_color } },
        { Foreground = { Color = '#1e1e2e' } },
        { Text = label },
      }
    else
      return {
        { Background = { Color = tab_color } },
        { Foreground = { Color = '#1e1e2e' } },
        { Attribute = { Intensity = 'Half' } },
        { Text = label },
      }
    end
  end

  return label
end)

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true

-- Plugins (Windows has richer plugin support)
if is_windows then
  wezterm.plugin.require("https://github.com/aureolebigben/wezterm-cmd-sender").apply_to_config(config, {
    key = 'C',
    mods = 'LEADER',
    description = 'Enter command to send to all panes of active tab'
  })

  wezterm.plugin.require("https://gitlab.com/xarvex/presentation.wez").apply_to_config(config, {
    font_size_multiplier = 1.8,
    presentation = {
      enabled = true,
    },
    presentation_full = {
      enabled = true,
    }
  })

  local domains = wezterm.plugin.require("https://github.com/DavidRR-F/quick_domains.wezterm")
  domains.apply_to_config(config, {})

  local workspace_switcher = wezterm.plugin.require("https://github.com/MLFlexer/smart_workspace_switcher.wezterm")
  workspace_switcher.apply_to_config(config)

  config.default_workspace = "Default"
  config.leader = { key = 'b', mods = 'CTRL' }

  -- Spawn new tabs next to the current tab instead of at the end
  wezterm.on('spawn-new-tab', function(window, pane)
    local mux_window = window:mux_window()
    local tabs = mux_window:tabs_with_info()
    local current_index = 0
    for _, tab_info in ipairs(tabs) do
      if tab_info.is_active then
        current_index = tab_info.index
        break
      end
    end
    mux_window:spawn_tab{}
    window:perform_action(act.MoveTab(current_index + 1), pane)
  end)

  config.keys = {
    {
      key = 't',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.EmitEvent('spawn-new-tab'),
    },
    {
      key = "s",
      mods = "LEADER",
      action = workspace_switcher.switch_workspace({ extra_args = " | rg -iSP --sort=path src.\\w+(?!src)$" }),
    },
    {
      key = "S",
      mods = "LEADER",
      action = workspace_switcher.switch_to_prev_workspace(),
    },
    {
      key = 'd',
      mods = 'CTRL|SHIFT',
      action = wezterm.action.EmitEvent('spawn-new-tab'),
    },
  }
end

-- Mouse bindings
config.mouse_bindings = {
  -- Change the default click behavior so that it only selects
  -- text and doesn't open hyperlinks
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'ClipboardAndPrimarySelection',
  },

  -- CTRL-Click opens hyperlinks
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'CTRL',
    action = act.OpenLinkAtMouseCursor,
  },

  -- Scrolling up while holding CTRL increases the font size
  {
    event = { Down = { streak = 1, button = { WheelUp = 1 } } },
    mods = 'CTRL',
    action = act.IncreaseFontSize,
  },

  -- Scrolling down while holding CTRL decreases the font size
  {
    event = { Down = { streak = 1, button = { WheelDown = 1 } } },
    mods = 'CTRL',
    action = act.DecreaseFontSize,
  },
}

return config
