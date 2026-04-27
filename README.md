# SwiftKHD

A simple hotkey daemon for macOS, written in Swift. SwiftKHD is a Swift port of [skhd.zig](https://github.com/jackielii/skhd.zig) (itself a Zig port of the original [skhd](https://github.com/koekeishiya/skhd) by Åsmund Vikane). It is **fully compatible with existing skhd configuration files** — your `.skhdrc` will work without modification.

**Requires macOS 13 (Ventura) or later.**

---

## Features

- Full skhd config DSL compatibility
- Modal hotkey system
- Process-specific bindings (per-app hotkeys)
- Process groups — bind a set of apps with a single definition
- Key forwarding and remapping
- Media key support
- Passthrough mode — execute a command while still sending the keypress
- Live config hot reload (FSEvents, no restart needed)
- Observe mode — print raw key events to identify keycodes
- Service management via `launchctl`
- Zero allocations in the event loop at runtime

---

## Installation

### Build from Source

Requires Xcode 15+ (Swift 5.9+).

```bash
git clone https://github.com/trodemaster/SwiftKHD
cd SwiftKHD
swift build -c release
```

The binary is at `.build/release/SwiftKHD`. Copy it somewhere on your `$PATH`:

```bash
sudo cp .build/release/SwiftKHD /usr/local/bin/swiftkHD
```

---

## Accessibility Permission

SwiftKHD requires Accessibility permission to capture keyboard events system-wide.

```bash
swiftkHD -V   # run once to trigger the permission prompt
```

Then open **System Settings → Privacy & Security → Accessibility** and enable SwiftKHD. If the daemon is running as a service, restart it after granting permission:

```bash
swiftkHD --restart-service
```

---

## Service Management

SwiftKHD can install itself as a launchd user agent so it starts automatically at login.

```bash
swiftkHD --install-service      # write plist to ~/Library/LaunchAgents/ and bootstrap
swiftkHD --start-service        # kickstart the service
swiftkHD --stop-service         # send SIGTERM
swiftkHD --restart-service      # kickstart -k (replace running instance)
swiftkHD --status               # print launchctl service status
swiftkHD --uninstall-service    # bootout and remove the plist
```

The service plist points to whichever binary ran `--install-service`, so run this command from the final installed location of the binary.

---

## CLI Reference

```
USAGE: swiftkHD [OPTIONS]

OPTIONS:
  -c, --config <file>       Config file path (default: ~/.config/skhd/skhdrc)
  -V, --verbose             Enable verbose logging
  -o, --observe             Observe mode: print raw keyboard events
  -P, --profile             Enable profiling/tracing (Debug/ReleaseSafe builds)
  -k, --key <keyspec>       Synthesize a keypress  (e.g. 'cmd - a')
  -t, --text <text>         Synthesize text input
  -r, --reload              Send reload signal to the running instance
      --no-hotload          Disable config hot reload via FSEvents
      --install-service     Install launchd service
      --uninstall-service   Uninstall launchd service
      --start-service       Start the service
      --stop-service        Stop the service
      --restart-service     Restart the service
      --status              Show service status
      --version             Show version
  -h, --help                Show help
```

### Config file resolution order

1. `$XDG_CONFIG_HOME/skhd/skhdrc`
2. `$HOME/.config/skhd/skhdrc`
3. `$HOME/.skhdrc`
4. `./skhdrc`

---

## Configuration

SwiftKHD uses the same config syntax as skhd. The default config file is `~/.config/skhd/skhdrc`.

### Basic hotkeys

```
# modifier - key : command
cmd - return : open -a Terminal
ctrl + shift - r : brew upgrade

# Multiple modifiers
cmd + shift - 3 : screencapture -i ~/Desktop/screenshot.png

# No modifier
f5 : open -a Safari
```

### Forwarding / remapping

Use `|` to remap a key to another:

```
# Remap Ctrl+Left to Alt+Left in all apps except terminals
ctrl - left [
    "kitty"   ~
    "wezterm" ~
    *         | alt - left
]
```

The `->` prefix sends the keypress to the application as well as running the command:

```
cmd - s -> : echo "saved"   # cmd-s still reaches the app
```

### Passthrough

```
cmd - p -> : notify send "printing..."   # key still reaches app
```

### Unbound (`~`)

```
ctrl - c [
    "terminal" ~    # terminal handles ctrl-c natively; don't intercept
    *          : echo "ctrl-c pressed"
]
```

### Modal system

```
# Declare a mode
:: window

# Enter window mode
cmd - w ; window

# Bindings inside window mode
window < h : yabai -m window --focus west
window < j : yabai -m window --focus south
window < k : yabai -m window --focus north
window < l : yabai -m window --focus east

# Exit window mode
window < escape ; default

# Capture mode: block all unbound keys while active
:: resize @

# Enter with a command executed on activation
cmd - r ; resize : echo "resize mode"
```

### Process-specific bindings

```
cmd - c [
    "terminal"  ~           # terminal handles this itself
    "emacs"     : emacsclient --eval "(kill-ring-save ...)"
    *           : pbcopy
]
```

### Process groups

Define a group once, reference it anywhere with `@`:

```
.define terminal_apps ["kitty", "wezterm", "terminal", "iterm2", "alacritty"]
.define browser_apps  ["chrome", "safari", "firefox", "edge", "brave"]

ctrl - backspace [
    @terminal_apps ~
    *              | alt - backspace
]

shift - home [
    @terminal_apps ~
    @browser_apps  ~
    *              | cmd + shift - left
]
```

### Command definitions (templates)

```
.define resize_win : yabai -m window --resize {{1}}:{{2}}:0

cmd + alt - h : @resize_win("left", "-20")
cmd + alt - l : @resize_win("right", "20")
cmd + alt - k : @resize_win("top", "-20")
cmd + alt - j : @resize_win("bottom", "20")
```

### Load additional config files

```
.load "~/.config/skhd/modes.skhdrc"
.load "~/.config/skhd/apps.skhdrc"
```

### Blacklist applications

```
.blacklist [
    "loginwindow"
    "screensaver"
]
```

### Custom shell

```
.shell "/bin/zsh"
```

### Hex keycodes

Find unknown keycodes with `-o` (observe mode), then bind them directly:

```
cmd - 0x32 : echo "backtick"
```

### Media keys

```
play     : playerctl play-pause
sound_up : pactl set-sink-volume @DEFAULT_SINK@ +5%
mute     : pactl set-sink-mute @DEFAULT_SINK@ toggle
```

### Literal key reference

| Key        | Description             |
|------------|-------------------------|
| `return`   | Return / Enter          |
| `tab`      | Tab                     |
| `space`    | Space                   |
| `backspace`| Backspace               |
| `escape`   | Escape                  |
| `delete`   | Forward Delete          |
| `home`     | Home                    |
| `end`      | End                     |
| `pageup`   | Page Up                 |
| `pagedown` | Page Down               |
| `left`     | Left arrow              |
| `right`    | Right arrow             |
| `up`       | Up arrow                |
| `down`     | Down arrow              |
| `f1`–`f20`| Function keys [^fnkeys] |
| `sound_up` | Volume Up               |
| `sound_down`| Volume Down            |
| `mute`     | Mute                   |
| `play`     | Play/Pause              |
| `previous` | Previous track          |
| `next`     | Next track              |
| `rewind`   | Rewind                  |
| `fast`     | Fast forward            |
| `brightness_up` | Brightness Up      |
| `brightness_down`| Brightness Down   |

[^fnkeys]: By default macOS maps F-keys to system functions (brightness, volume, etc.). To bind `f1`–`f20` directly, enable **System Settings → Keyboard → "Use F1, F2, etc. keys as standard function keys"**, or use the `fn` modifier in your binding (e.g. `fn - f1 : open -a Safari`).

---

## Observe Mode

Use observe mode to identify keycodes and modifier flags for any key combination:

```bash
swiftkHD -o
```

Output:
```
Observing key events. Press Ctrl-C to exit.
keycode: 0x00 (0) | flags: lcmd
keycode: 0x31 (49) | flags: (none)
```

---

## Hot Reload

SwiftKHD watches the config file (and any `.load`-ed files) for changes and automatically reloads without restarting.

To trigger a reload manually from another terminal:

```bash
swiftkHD --reload
```

To disable hot reload:

```bash
swiftkHD --no-hotload -c ~/.config/skhd/skhdrc
```

---

## Credits

SwiftKHD is a Swift port built on the shoulders of two excellent projects:

- **[skhd](https://github.com/koekeishiya/skhd)** by [Åsmund Vikane (koekeishiya)](https://github.com/koekeishiya) — the original Simple Hotkey Daemon for macOS. The config DSL, hotkey semantics, and overall architecture originate here.
- **[skhd.zig](https://github.com/jackielii/skhd.zig)** by [Jackie Li (jackielii)](https://github.com/jackielii) — a Zig port of skhd that introduced process groups, command template definitions, mode activation commands, and other enhancements. SwiftKHD's feature set and implementation approach closely follow skhd.zig.

---

## License

MIT — see [LICENSE](LICENSE).
