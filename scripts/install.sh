# Minecraft Theme for Omarchy — installer
# Idempotent: safe to run multiple times.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
THEME_NAME="minecraft"
THEME_DIR="$HOME/.config/omarchy/themes/$THEME_NAME"
BIN_DIR="$HOME/.local/bin"
ICON_DIR="$HOME/.local/share/icons/MinecraftPixel"
CONFIG_DIR="$HOME/.config/minecraft_theme"

echo "==> Installing Minecraft theme for Omarchy"

# 1. Theme files (no .git here, so hyprland.lua / neovim.lua are honored)
echo "  -> theme: $THEME_DIR"
mkdir -p "$THEME_DIR/backgrounds"
for f in colors.toml shell.toml hyprland.lua neovim.lua btop.theme chromium.theme keyboard.rgb; do
  [ -f "$REPO_DIR/theme/$f" ] && cp "$REPO_DIR/theme/$f" "$THEME_DIR/$f"
done
# Preview if present
[ -f "$REPO_DIR/theme/preview.png" ] && cp "$REPO_DIR/theme/preview.png" "$THEME_DIR/"
# Wallpapers (user-supplied, gitignored in the repo)
for wallpaper in "$REPO_DIR/theme/backgrounds/"*; do
  [ -f "$wallpaper" ] && cp "$wallpaper" "$THEME_DIR/backgrounds/"
done

# 2. Scripts
echo "  -> scripts: $BIN_DIR"
mkdir -p "$BIN_DIR"
for s in minecraft-theme-toggle minecraft-hotbar minecraft-inventory minecraft-steve \
         minecraft-death minecraft-toast minecraft-splash minecraft-sound; do
  [ -f "$SCRIPT_DIR/$s" ] && cp "$SCRIPT_DIR/$s" "$BIN_DIR/"
done
chmod +x "$BIN_DIR"/minecraft-* 2>/dev/null || true

# 2b. Original procedural UI sounds
echo "  -> sounds: $HOME/.local/share/minecraft-theme/sounds"
mkdir -p "$HOME/.local/share/minecraft-theme/sounds"
if [ -d "$REPO_DIR/assets/sounds" ]; then
  cp "$REPO_DIR/assets/sounds/"*.wav "$HOME/.local/share/minecraft-theme/sounds/" 2>/dev/null || true
fi

# 3. Pixel cursor
echo "  -> cursor: $ICON_DIR"
if [ -d "$REPO_DIR/cursor/hyprcursors" ]; then
  python3 "$REPO_DIR/cursor/install_cursor.py" 2>/dev/null || {
    # Fallback: pack inline if helper missing
    echo "    (cursor helper failed; run cursor/generate.py + pack manually)"
  }
fi

# 4. Config dir for hotbar state (M3+)
echo "  -> config: $CONFIG_DIR"
mkdir -p "$CONFIG_DIR"
[ -f "$CONFIG_DIR/hotbar.json" ] || echo '{}' > "$CONFIG_DIR/hotbar.json"

# 4b. Quickshell plugins (HUD + inventory)
enable_plugin() {
  local id="$1"
  local src="$2"
  local dst="$HOME/.config/omarchy/plugins/$id"
  echo "  -> plugin: $dst"
  mkdir -p "$dst"
  cp "$src"/manifest.json "$dst/"
  for qml in "$src"/*.qml; do
    [ -f "$qml" ] && cp "$qml" "$dst/"
  done
  local SHELL_JSON="$HOME/.config/omarchy/shell.json"
  if [ -f "$SHELL_JSON" ] && command -v jq >/dev/null 2>&1; then
    jq --arg id "$id" \
      '(.plugins // []) | map(if type == "string" then {id: .} else . end) as $p
       | if ([$p[].id] | index($id)) then .plugins = $p
         else .plugins = ($p + [{id: $id}]) end' \
      "$SHELL_JSON" > "$SHELL_JSON.tmp" && mv "$SHELL_JSON.tmp" "$SHELL_JSON"
    echo "  -> enabled plugin $id"
  else
    omarchy plugin enable "$id" 2>/dev/null || true
  fi
}
enable_plugin "io.github.jaquesbody.minecraft-hud" "$REPO_DIR/plugin"
enable_plugin "io.github.jaquesbody.minecraft-inventory" "$REPO_DIR/plugin/inventory"
enable_plugin "io.github.jaquesbody.minecraft-steve" "$REPO_DIR/plugin/steve"
enable_plugin "io.github.jaquesbody.minecraft-death" "$REPO_DIR/plugin/death"
enable_plugin "io.github.jaquesbody.minecraft-toast" "$REPO_DIR/plugin/toast"
enable_plugin "io.github.jaquesbody.minecraft-splash" "$REPO_DIR/plugin/splash"

# Reload plugin list so newly copied plugins are visible to IPC
omarchy-shell shell rescanPlugins 2>/dev/null || true

# 5. Hyprland keybindings (survive Omarchy updates: live in user bindings)
BINDINGS="$HOME/.config/hypr/bindings.lua"
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-theme-toggle" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+M toggles the Minecraft theme on/off
o.bind("SUPER + M", "Toggle Minecraft Theme", os.getenv("HOME") .. "/.local/bin/minecraft-theme-toggle")
LUA
  echo "  -> added SUPER+M binding to bindings.lua"
fi
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-hotbar" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+H toggles the hotbar/HUD overlay
o.bind("SUPER + H", "Toggle Minecraft HUD", os.getenv("HOME") .. "/.local/bin/minecraft-hotbar")
LUA
  echo "  -> added SUPER+H binding to bindings.lua"
fi
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-inventory" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+E toggles the inventory panel
o.bind("SUPER + E", "Toggle Minecraft Inventory", os.getenv("HOME") .. "/.local/bin/minecraft-inventory")
LUA
  echo "  -> added SUPER+E binding to bindings.lua"
fi
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-steve" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+SHIFT+S toggles the Steve companion (SUPER+S is scratchpad)
o.bind("SUPER + SHIFT + S", "Toggle Minecraft Steve", os.getenv("HOME") .. "/.local/bin/minecraft-steve")
LUA
  echo "  -> added SUPER+SHIFT+S binding to bindings.lua"
fi
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-death" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+SHIFT+D toggles the death-screen power menu
o.bind("SUPER + SHIFT + D", "Minecraft Death Power Menu", os.getenv("HOME") .. "/.local/bin/minecraft-death")
LUA
  echo "  -> added SUPER+SHIFT+D binding to bindings.lua"
fi
if [ -f "$BINDINGS" ] && ! grep -q "minecraft-splash" "$BINDINGS" 2>/dev/null; then
  cat >> "$BINDINGS" << 'LUA'

-- Minecraft Theme: SUPER+SHIFT+X shows a yellow splash line
o.bind("SUPER + SHIFT + X", "Minecraft Splash Text", os.getenv("HOME") .. "/.local/bin/minecraft-splash")
LUA
  echo "  -> added SUPER+SHIFT+X binding to bindings.lua"
fi

# 6. Font (Monocraft) — warn if missing
if ! fc-list | grep -qi monocraft; then
  echo "  !! Monocraft font not found. Install with:  yay -S ttf-monocraft-nerd"
  echo "     then:  omarchy font set Monocraft"
fi

echo ""
echo "==> Done. Apply with:  omarchy theme set $THEME_NAME"
echo "    Toggle with:       SUPER+M   (or minecraft-theme-toggle)"
echo "    HUD / inventory:   SUPER+H / SUPER+E"
echo "    Steve / death:     SUPER+SHIFT+S / SUPER+SHIFT+D"
echo "    Splash / toast:    SUPER+SHIFT+X / minecraft-toast"
echo "    Sounds:            minecraft-sound click|open|close|toast|death"
