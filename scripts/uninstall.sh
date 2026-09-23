#!/bin/bash
# Minecraft Theme for Omarchy — uninstaller
set -euo pipefail

THEME_NAME="minecraft"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"
BIN_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/MinecraftPixel"
STATE_DIR="$HOME/.local/state/minecraft-theme"
CONFIG_DIR="$HOME/.config/minecraft_theme"
BINDINGS="$HOME/.config/hypr/bindings.lua"

echo "==> Uninstalling Minecraft theme"

# Restore previous theme if Minecraft is currently active
current_name=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || echo "")
if [ "$current_name" = "$THEME_NAME" ]; then
  prev=""
  [ -f "$STATE_DIR/previous-theme" ] && prev=$(cat "$STATE_DIR/previous-theme")
  if [ -n "$prev" ] && [ "$prev" != "$THEME_NAME" ]; then
    echo "  -> restoring theme: $prev"
    omarchy-theme-set "$prev" || true
  else
    echo "  !! Minecraft theme is active; no previous theme recorded."
    echo "     Switch manually: omarchy theme list | omarchy theme set <name>"
  fi
fi

echo "  -> removing theme dir"
rm -rf "$THEME_DIR"

echo "  -> removing scripts"
rm -f "$BIN_DIR/minecraft-theme-toggle" "$BIN_DIR/minecraft-hotbar" \
      "$BIN_DIR/minecraft-inventory" "$BIN_DIR/minecraft-steve" \
      "$BIN_DIR/minecraft-death" "$BIN_DIR/minecraft-toast" \
      "$BIN_DIR/minecraft-splash" "$BIN_DIR/minecraft-sound"

echo "  -> removing sounds"
rm -rf "$HOME/.local/share/minecraft-theme"

echo "  -> removing Quickshell plugins"
for PLUGIN_ID in \
  io.github.jaquesbody.minecraft-hud \
  io.github.jaquesbody.minecraft-inventory \
  io.github.jaquesbody.minecraft-steve \
  io.github.jaquesbody.minecraft-death \
  io.github.jaquesbody.minecraft-toast \
  io.github.jaquesbody.minecraft-splash
do
  PLUGIN_DST="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
  omarchy-shell shell hide "$PLUGIN_ID" 2>/dev/null || true
  omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || true
  if [ -f "$HOME/.config/omarchy/shell.json" ] && command -v jq >/dev/null 2>&1; then
    SHELL_JSON="$HOME/.config/omarchy/shell.json"
    jq --arg id "$PLUGIN_ID" \
      '(.plugins // []) | map(if type == "string" then {id: .} else . end) as $p
       | .plugins = ($p | map(select(.id != $id)))' \
      "$SHELL_JSON" > "$SHELL_JSON.tmp" && mv "$SHELL_JSON.tmp" "$SHELL_JSON"
  fi
  rm -rf "$PLUGIN_DST"
done
omarchy-shell shell rescanPlugins 2>/dev/null || true

echo "  -> removing cursor theme"
rm -rf "$ICON_DIR"

echo "  -> removing state"
rm -rf "$STATE_DIR"

if [ -d "$CONFIG_DIR" ]; then
  echo "  -> keeping config (hotbar customizations): $CONFIG_DIR"
  echo "     Delete manually if unwanted."
fi

# Remove Minecraft keybind lines (user file — only ours).
if [ -f "$BINDINGS" ]; then
  echo "  -> removing Minecraft bindings from bindings.lua"
  python3 - "$BINDINGS" << 'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    lines = f.readlines()
out, i = [], 0
while i < len(lines):
    line = lines[i]
    if "minecraft-" in line and (line.strip().startswith("--") or "o.bind" in line):
        if line.strip().startswith("--"):
            i += 1
            if i < len(lines) and "minecraft-" in lines[i]:
                i += 1
            if i < len(lines) and lines[i].strip() == "":
                i += 1
            continue
        else:
            i += 1
            continue
    out.append(line)
    i += 1
with open(path, "w") as f:
    f.writelines(out)
PY
fi

# Also strip any leftover splash bind (older installs)
if [ -f "$BINDINGS" ]; then
  grep -v "minecraft-splash" "$BINDINGS" > "$BINDINGS.tmp" 2>/dev/null && mv "$BINDINGS.tmp" "$BINDINGS" || true
fi

echo ""
echo "==> Uninstalled."
