## generate_themes.nim - Generate themes.css from theme.nim palettes

import ../src/fossil/ui/theme
import std/[os]

when isMainModule:
  let css = generateAllThemesCss()
  # Add extra themes monokai and github-light manually since they are not in Nim core yet
  let extra = """
/* Monokai - Vibrant dark */
[data-theme="monokai"] {
  --color-primary: #a6e22e;
  --color-primary-hover: #8ac627;
  --color-primary-light: #3e4a2d;
  --color-secondary: #75715e;
  --color-success: #a6e22e;
  --color-danger: #f92672;
  --color-warning: #fd971f;
  --color-info: #66d9ef;
  --color-bg: #272822;
  --color-bg-secondary: #3e3d32;
  --color-bg-card: #3e3d32;
  --color-bg-code: #49483e;
  --color-bg-hover: #49483e;
  --color-text: #f8f8f2;
  --color-text-secondary: #cfcfc2;
  --color-text-muted: #75715e;
  --color-text-inverse: #272822;
  --color-border: #49483e;
  --color-border-light: #75715e;
  --color-border-dark: #f8f8f2;
  --shadow: 0 1px 3px rgba(0,0,0,0.4);
  --shadow-lg: 0 4px 12px rgba(0,0,0,0.5);
  --radius: 6px;
  --radius-lg: 12px;
}

/* GitHub Light */
[data-theme="github-light"] {
  --color-primary: #0969da;
  --color-primary-hover: #0550ae;
  --color-primary-light: #ddf4ff;
  --color-secondary: #656d76;
  --color-success: #1a7f37;
  --color-danger: #cf222e;
  --color-warning: #9a6700;
  --color-info: #0969da;
  --color-bg: #ffffff;
  --color-bg-secondary: #f6f8fa;
  --color-bg-card: #ffffff;
  --color-bg-code: #f6f8fa;
  --color-bg-hover: #f6f8fa;
  --color-text: #24292f;
  --color-text-secondary: #57606a;
  --color-text-muted: #8c959f;
  --color-text-inverse: #ffffff;
  --color-border: #d0d7de;
  --color-border-light: #d8dee4;
  --color-border-dark: #24292f;
  --shadow: 0 1px 0 rgba(27,31,36,0.04);
  --shadow-lg: 0 3px 6px rgba(140,149,159,0.15);
  --radius: 6px;
  --radius-lg: 12px;
}
"""
  let fullCss = css & "\n" & extra
  writeFile("web_new/css/themes.css", fullCss)
  echo "Generated web_new/css/themes.css (" & $fullCss.len & " bytes)"
  echo "Themes: light, dark, solarized-light, nord, monokai, github-light"
