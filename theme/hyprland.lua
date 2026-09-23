-- Minecraft Theme — Hyprland overrides
-- Hard square borders, blocky gaps, snappy animations, pixel cursor

local active_border_color = "rgb(55FF55)"
local inactive_border_color = "rgb(555555)"

hl.config({
  general = {
    col = {
      active_border = active_border_color,
      inactive_border = inactive_border_color,
    },
    border_size = 4,
    gaps_in = 4,
    gaps_out = 8,
  },

  group = {
    col = {
      border_active = active_border_color,
      border_inactive = inactive_border_color,
    },
  },

  decoration = {
    rounding = 0,
    blur = {
      enabled = true,
      size = 4,
      passes = 2,
    },
    shadow = {
      enabled = true,
      range = 8,
      render_power = 2,
      color = "rgba(000000aa)",
    },
  },

})

-- Pixel cursor (original hyprcursor theme shipped with this repo)
hl.env("XCURSOR_THEME", "MinecraftPixel")
hl.env("HYPRCURSOR_THEME", "MinecraftPixel")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Minecraft-feel curves: snappy snap-in with a tiny bounce
hl.curve("minecraft", { type = "bezier", points = { { 0.25, 0.1 }, { 0.25, 1.0 } } })
hl.curve("minecraft_bounce", { type = "bezier", points = { { 0.34, 1.56 }, { 0.64, 1.0 } } })

hl.animation({ leaf = "windows", enabled = true, speed = 4.0, bezier = "minecraft" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.0, bezier = "minecraft_bounce", style = "popin 90%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3.0, bezier = "minecraft" })
hl.animation({ leaf = "fade", enabled = true, speed = 4.0, bezier = "minecraft" })
hl.animation({ leaf = "layers", enabled = true, speed = 4.0, bezier = "minecraft" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 4.0, bezier = "minecraft", style = "fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 3.0, bezier = "minecraft", style = "fade" })
