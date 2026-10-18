## Theme System - Modular, easy to edit palette
## Generates CSS variables, supports light/dark/custom themes

import std/[tables, json, strutils, os]

type
  ColorPalette* = object
    # Primary colors
    primary*: string
    primaryHover*: string
    primaryLight*: string
    secondary*: string
    success*: string
    danger*: string
    warning*: string
    info*: string

    # Backgrounds
    bg*: string
    bgSecondary*: string
    bgCard*: string
    bgCode*: string
    bgHover*: string

    # Text
    text*: string
    textSecondary*: string
    textMuted*: string
    textInverse*: string

    # Borders
    border*: string
    borderLight*: string
    borderDark*: string

    # Special
    shadow*: string
    shadowLg*: string
    radius*: string
    radiusLg*: string

  Theme* = object
    name*: string
    displayName*: string
    description*: string
    isDark*: bool
    palette*: ColorPalette
    customCss*: string

proc defaultLightPalette*(): ColorPalette =
  ColorPalette(
    primary: "#0d6efd",
    primaryHover: "#0b5ed7",
    primaryLight: "#cfe2ff",
    secondary: "#6c757d",
    success: "#198754",
    danger: "#dc3545",
    warning: "#ffc107",
    info: "#0dcaf0",
    bg: "#f8f9fa",
    bgSecondary: "#e9ecef",
    bgCard: "#ffffff",
    bgCode: "#f1f3f5",
    bgHover: "#e9ecef",
    text: "#212529",
    textSecondary: "#495057",
    textMuted: "#6c757d",
    textInverse: "#ffffff",
    border: "#dee2e6",
    borderLight: "#e9ecef",
    borderDark: "#343a40",
    shadow: "0 1px 3px rgba(0,0,0,0.1)",
    shadowLg: "0 4px 12px rgba(0,0,0,0.15)",
    radius: "6px",
    radiusLg: "12px"
  )

proc defaultDarkPalette*(): ColorPalette =
  ColorPalette(
    primary: "#3b82f6",
    primaryHover: "#2563eb",
    primaryLight: "#1e3a5f",
    secondary: "#6b7280",
    success: "#10b981",
    danger: "#ef4444",
    warning: "#f59e0b",
    info: "#06b6d4",
    bg: "#111827",
    bgSecondary: "#1f2937",
    bgCard: "#1f2937",
    bgCode: "#374151",
    bgHover: "#374151",
    text: "#f9fafb",
    textSecondary: "#d1d5db",
    textMuted: "#9ca3af",
    textInverse: "#111827",
    border: "#374151",
    borderLight: "#4b5563",
    borderDark: "#6b7280",
    shadow: "0 1px 3px rgba(0,0,0,0.3)",
    shadowLg: "0 4px 12px rgba(0,0,0,0.4)",
    radius: "6px",
    radiusLg: "12px"
  )

proc solarizedLightPalette*(): ColorPalette =
  ColorPalette(
    primary: "#268bd2",
    primaryHover: "#2075b5",
    primaryLight: "#d6e9f5",
    secondary: "#93a1a1",
    success: "#859900",
    danger: "#dc322f",
    warning: "#b58900",
    info: "#2aa198",
    bg: "#fdf6e3",
    bgSecondary: "#eee8d5",
    bgCard: "#ffffff",
    bgCode: "#eee8d5",
    bgHover: "#eee8d5",
    text: "#586e75",
    textSecondary: "#657b83",
    textMuted: "#93a1a1",
    textInverse: "#fdf6e3",
    border: "#93a1a1",
    borderLight: "#eee8d5",
    borderDark: "#586e75",
    shadow: "0 1px 3px rgba(88,110,117,0.1)",
    shadowLg: "0 4px 12px rgba(88,110,117,0.15)",
    radius: "6px",
    radiusLg: "12px"
  )

proc nordPalette*(): ColorPalette =
  ColorPalette(
    primary: "#88c0d0",
    primaryHover: "#81a1c1",
    primaryLight: "#4c566a",
    secondary: "#4c566a",
    success: "#a3be8c",
    danger: "#bf616a",
    warning: "#ebcb8b",
    info: "#88c0d0",
    bg: "#2e3440",
    bgSecondary: "#3b4252",
    bgCard: "#3b4252",
    bgCode: "#4c566a",
    bgHover: "#4c566a",
    text: "#eceff4",
    textSecondary: "#d8dee9",
    textMuted: "#4c566a",
    textInverse: "#2e3440",
    border: "#4c566a",
    borderLight: "#5e81ac",
    borderDark: "#2e3440",
    shadow: "0 1px 3px rgba(0,0,0,0.3)",
    shadowLg: "0 4px 12px rgba(0,0,0,0.4)",
    radius: "6px",
    radiusLg: "12px"
  )

proc defaultThemes*(): seq[Theme] =
  @[
    Theme(name: "light", displayName: "Light", description: "Default light theme, clean and minimal", isDark: false, palette: defaultLightPalette(), customCss: ""),
    Theme(name: "dark", displayName: "Dark", description: "Dark theme for low light", isDark: true, palette: defaultDarkPalette(), customCss: ""),
    Theme(name: "solarized-light", displayName: "Solarized Light", description: "Solarized light, easy on eyes", isDark: false, palette: solarizedLightPalette(), customCss: ""),
    Theme(name: "nord", displayName: "Nord", description: "Nord dark, arctic bluish", isDark: true, palette: nordPalette(), customCss: ""),
  ]

proc paletteToCssVariables*(p: ColorPalette): string =
  ## Generate CSS variables from palette
  result = ":root {\n"
  result.add "  --color-primary: " & p.primary & ";\n"
  result.add "  --color-primary-hover: " & p.primaryHover & ";\n"
  result.add "  --color-primary-light: " & p.primaryLight & ";\n"
  result.add "  --color-secondary: " & p.secondary & ";\n"
  result.add "  --color-success: " & p.success & ";\n"
  result.add "  --color-danger: " & p.danger & ";\n"
  result.add "  --color-warning: " & p.warning & ";\n"
  result.add "  --color-info: " & p.info & ";\n"
  result.add "  --color-bg: " & p.bg & ";\n"
  result.add "  --color-bg-secondary: " & p.bgSecondary & ";\n"
  result.add "  --color-bg-card: " & p.bgCard & ";\n"
  result.add "  --color-bg-code: " & p.bgCode & ";\n"
  result.add "  --color-bg-hover: " & p.bgHover & ";\n"
  result.add "  --color-text: " & p.text & ";\n"
  result.add "  --color-text-secondary: " & p.textSecondary & ";\n"
  result.add "  --color-text-muted: " & p.textMuted & ";\n"
  result.add "  --color-text-inverse: " & p.textInverse & ";\n"
  result.add "  --color-border: " & p.border & ";\n"
  result.add "  --color-border-light: " & p.borderLight & ";\n"
  result.add "  --color-border-dark: " & p.borderDark & ";\n"
  result.add "  --shadow: " & p.shadow & ";\n"
  result.add "  --shadow-lg: " & p.shadowLg & ";\n"
  result.add "  --radius: " & p.radius & ";\n"
  result.add "  --radius-lg: " & p.radiusLg & ";\n"
  result.add "  --font-sans: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;\n"
  result.add "  --font-mono: SFMono-Regular, Menlo, Monaco, Consolas, 'Liberation Mono', 'Courier New', monospace;\n"
  result.add "}\n"

proc themeToCss*(theme: Theme): string =
  ## Full CSS for theme
  result = "/* Theme: " & theme.name & " - " & theme.displayName & " */\n"
  result.add "/* " & theme.description & " */\n"
  result.add "[data-theme=\"" & theme.name & "\"] {\n"
  let p = theme.palette
  result.add "  --color-primary: " & p.primary & ";\n"
  result.add "  --color-primary-hover: " & p.primaryHover & ";\n"
  result.add "  --color-primary-light: " & p.primaryLight & ";\n"
  result.add "  --color-secondary: " & p.secondary & ";\n"
  result.add "  --color-success: " & p.success & ";\n"
  result.add "  --color-danger: " & p.danger & ";\n"
  result.add "  --color-warning: " & p.warning & ";\n"
  result.add "  --color-info: " & p.info & ";\n"
  result.add "  --color-bg: " & p.bg & ";\n"
  result.add "  --color-bg-secondary: " & p.bgSecondary & ";\n"
  result.add "  --color-bg-card: " & p.bgCard & ";\n"
  result.add "  --color-bg-code: " & p.bgCode & ";\n"
  result.add "  --color-bg-hover: " & p.bgHover & ";\n"
  result.add "  --color-text: " & p.text & ";\n"
  result.add "  --color-text-secondary: " & p.textSecondary & ";\n"
  result.add "  --color-text-muted: " & p.textMuted & ";\n"
  result.add "  --color-text-inverse: " & p.textInverse & ";\n"
  result.add "  --color-border: " & p.border & ";\n"
  result.add "  --color-border-light: " & p.borderLight & ";\n"
  result.add "  --color-border-dark: " & p.borderDark & ";\n"
  result.add "  --shadow: " & p.shadow & ";\n"
  result.add "  --shadow-lg: " & p.shadowLg & ";\n"
  result.add "  --radius: " & p.radius & ";\n"
  result.add "  --radius-lg: " & p.radiusLg & ";\n"
  result.add "}\n"
  if theme.customCss.len>0:
    result.add "\n" & theme.customCss & "\n"

proc generateAllThemesCss*(): string =
  ## Generate CSS for all themes
  result = "/* Fossil-Nim Themes - Auto-generated */\n"
  result.add "/* Edit palette in src/fossil/ui/theme.nim to change colors */\n\n"
  for theme in defaultThemes():
    result.add themeToCss(theme)
    result.add "\n"

proc themeToJson*(theme: Theme): JsonNode =
  %* {
    "name": theme.name,
    "displayName": theme.displayName,
    "description": theme.description,
    "isDark": theme.isDark,
    "palette": {
      "primary": theme.palette.primary,
      "primaryHover": theme.palette.primaryHover,
      "primaryLight": theme.palette.primaryLight,
      "secondary": theme.palette.secondary,
      "success": theme.palette.success,
      "danger": theme.palette.danger,
      "warning": theme.palette.warning,
      "info": theme.palette.info,
      "bg": theme.palette.bg,
      "bgSecondary": theme.palette.bgSecondary,
      "bgCard": theme.palette.bgCard,
      "bgCode": theme.palette.bgCode,
      "bgHover": theme.palette.bgHover,
      "text": theme.palette.text,
      "textSecondary": theme.palette.textSecondary,
      "textMuted": theme.palette.textMuted,
      "textInverse": theme.palette.textInverse,
      "border": theme.palette.border,
      "borderLight": theme.palette.borderLight,
      "borderDark": theme.palette.borderDark,
      "shadow": theme.palette.shadow,
      "shadowLg": theme.palette.shadowLg,
      "radius": theme.palette.radius,
      "radiusLg": theme.palette.radiusLg
    }
  }

proc saveThemesToFile*(path: string) =
  ## Save themes CSS to file for web UI
  let css = generateAllThemesCss()
  writeFile(path, css)

proc loadCustomTheme*(path: string): Theme =
  ## Load custom theme from JSON file
  if not fileExists(path):
    return defaultThemes()[0]
  try:
    let j = parseJson(readFile(path))
    var palette = defaultLightPalette()
    if j.hasKey("palette"):
      let p = j["palette"]
      if p.hasKey("primary"): palette.primary = p["primary"].getStr(palette.primary)
      if p.hasKey("bg"): palette.bg = p["bg"].getStr(palette.bg)
      if p.hasKey("text"): palette.text = p["text"].getStr(palette.text)
      # ... add more as needed, for brevity only few
    Theme(
      name: j.getOrDefault("name").getStr("custom"),
      displayName: j.getOrDefault("displayName").getStr("Custom"),
      description: j.getOrDefault("description").getStr("Custom theme"),
      isDark: j.getOrDefault("isDark").getBool(false),
      palette: palette,
      customCss: j.getOrDefault("customCss").getStr("")
    )
  except:
    defaultThemes()[0]
