#!/usr/bin/env python3
"""
Bundle script for Fossil-Nim Standalone In-Browser VCS.
Combines web_new/browser.html, CSS stylesheets, and JS engines into a single,
self-contained, 100% offline-ready fossil-browser.html.
"""

import os
import re

REPO_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WEB_DIR = os.path.join(REPO_DIR, "web_new")
HTML_IN = os.path.join(WEB_DIR, "browser.html")
HTML_OUT = os.path.join(REPO_DIR, "fossil-browser.html")

def bundle():
    with open(HTML_IN, "r", encoding="utf-8") as f:
        html = f.read()

    # Read CSS files
    with open(os.path.join(WEB_DIR, "css", "app.css"), "r", encoding="utf-8") as f:
        app_css = f.read()
    with open(os.path.join(WEB_DIR, "css", "themes.css"), "r", encoding="utf-8") as f:
        themes_css = f.read()

    # Replace <link rel="stylesheet" href="css/app.css"> and themes.css
    css_bundle = f"<style>\n{app_css}\n</style>\n  <style>\n{themes_css}\n</style>"
    html = re.sub(
        r'<link\s+rel="stylesheet"\s+href="css/app\.css">\s*<link\s+rel="stylesheet"\s+href="css/themes\.css">',
        lambda m: css_bundle,
        html
    )

    # Read JS files
    with open(os.path.join(WEB_DIR, "js", "fossil_core.js"), "r", encoding="utf-8") as f:
        fossil_core_js = f.read()
    with open(os.path.join(WEB_DIR, "js", "fossil_browser_storage.js"), "r", encoding="utf-8") as f:
        fossil_storage_js = f.read()
    with open(os.path.join(WEB_DIR, "js", "fossil_mcp_agent.js"), "r", encoding="utf-8") as f:
        fossil_mcp_js = f.read()
    with open(os.path.join(WEB_DIR, "js", "fossil_browser_ui.js"), "r", encoding="utf-8") as f:
        fossil_ui_js = f.read()

    # Replace script tags with inlined scripts
    js_bundle = (
        f"<script>\n{fossil_core_js}\n</script>\n"
        f"<script>\n{fossil_storage_js}\n</script>\n"
        f"<script>\n{fossil_mcp_js}\n</script>\n"
        f"<script>\n{fossil_ui_js}\n</script>"
    )

    script_pattern = re.compile(
        r'<script\s+src="js/fossil_core\.js"></script>\s*'
        r'<script\s+src="js/fossil_browser_storage\.js"></script>\s*'
        r'<script\s+src="js/fossil_mcp_agent\.js"></script>\s*'
        r'<script\s+src="js/fossil_browser_ui\.js"></script>',
        re.MULTILINE
    )

    html, count = script_pattern.subn(lambda m: js_bundle, html)
    if count == 0:
        raise ValueError("Could not find script tags in browser.html to replace!")

    with open(HTML_OUT, "w", encoding="utf-8") as f:
        f.write(html)

    size = os.path.getsize(HTML_OUT)
    print(f"Bundled successfully into {HTML_OUT}: {size:,} bytes")

if __name__ == "__main__":
    bundle()
