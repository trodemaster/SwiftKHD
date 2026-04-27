let defaultConfigContent = """
# swiftkhd configuration
# Format: [modifier(s) +] [modifier] - key : shell command
# Run `man swiftkhd` or `swiftkhd --help` for full reference.
# Use `swiftkhd --observe` to print key names for any key you press.

# --- Media playback ---
play     : true
next     : true
previous : true
mute     : true
sound_up   : true
sound_down : true

# --- Example bindings (uncomment to enable) ---
# cmd - return : open -na Terminal
# cmd + shift - 3 : screencapture -i ~/Desktop/screenshot.png
# cmd + ctrl - r : open -a "Activity Monitor"
"""
