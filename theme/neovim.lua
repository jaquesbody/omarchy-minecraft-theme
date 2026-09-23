return {
  {
    "bjarneo/aether.nvim",
    branch = "v3",
    name = "aether",
    priority = 1000,
    opts = {
      colors = {
        bg = "#191622",
        dark_bg = "#12101A",
        darker_bg = "#0C0A12",
        lighter_bg = "#2A2438",

        fg = "#C6C6C6",
        dark_fg = "#555555",
        light_fg = "#DCDCDC",
        bright_fg = "#FFFFFF",
        muted = "#555555",

        red = "#FF5555",
        yellow = "#FFFF55",
        orange = "#FFAA00",
        green = "#55FF55",
        cyan = "#55FFFF",
        blue = "#5555FF",
        magenta = "#FF55FF",
        brown = "#866043",

        bright_red = "#FF7777",
        bright_yellow = "#FFFF77",
        bright_green = "#77FF77",
        bright_cyan = "#77FFFF",
        bright_blue = "#7777FF",
        bright_magenta = "#FF77FF",

        accent = "#55FF55",
        cursor = "#FFFFFF",
        foreground = "#C6C6C6",
        background = "#191622",
        selection = "#375231",
        selection_foreground = "#FFFFFF",
        selection_background = "#375231",
      },
    },
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "aether",
    },
  },
}
