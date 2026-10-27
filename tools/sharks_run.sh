#!/bin/sh
# Build and run examples/sharks.nim on ONE backend and keep the digest it
# prints, so tools/sharks_crosscheck.nim can compare every backend on this
# machine -- and every machine in the CI matrix -- against one golden scene.
#
#   sh tools/sharks_run.sh <backend> <outdir> [frames]
#
# backends:
#   native   whatever this OS picks by itself: X11, Cocoa or WinAPI
#   gtk4     -d:gtk4    (needs the GTK 4 development headers)
#   sdl2     -d:sdl2    (needs the sdl2 Nim wrapper and SDL2 + SDL2_ttf)
#   sdl3     -d:sdl3
#   html     -d:html    web backend, server mode. The scene is computed by the
#   canvas   -d:canvas  native process, which is also what prints the digest,
#                       so no browser is needed to obtain it; the browser is
#                       checked separately, by really rendering these frames.
#   jsdom    the standalone `nim js` page running inside jsdom, digest read
#            from the page's own console.log. The same Nim source, compiled to
#            JavaScript, in a real DOM.
#   chrome   the same standalone page in real headless Chrome/Edge. A hook
#            installed before the app's own script copies the SHARKS_DIGEST
#            line into an attribute on <html>, and --dump-dom reads it back,
#            so the digest comes out of an actual browser engine rather than
#            out of a simulation of one.
#
# Environment:
#   NIM, NODE, NPM       tool paths
#   UIRELAYS_SHARKS_FRAMES  default frame count (120)
#   UIRELAYS_SHARKS_TIMEOUT default per-run timeout in seconds (900)
#
# Exit codes: 0 digest captured, 1 build or run failed or printed no digest,
# 2 bad usage.
set -u

if [ "$#" -lt 2 ]; then
  echo "usage: sh tools/sharks_run.sh <backend> <outdir> [frames]" >&2
  exit 2
fi

backend="$1"
outdir="$2"
frames="${3:-${UIRELAYS_SHARKS_FRAMES:-120}}"
timeout_s="${UIRELAYS_SHARKS_TIMEOUT:-900}"

root=$(cd "$(dirname "$0")/.." && pwd)
nim="${NIM:-nim}"
node_bin="${NODE:-node}"

mkdir -p "$outdir" || exit 1
binDir="$outdir/bin-$backend"
mkdir -p "$binDir" || exit 1
log="$outdir/$backend.log"
digestOut="$outdir/$backend.digest"
rm -f "$digestOut"

# A windowed backend needs a display. GitHub's Linux runners have none, so the
# native X11 run happens under Xvfb; that is a real X server, not a stub, and
# x11_driver really dlopens libX11 and libXft and really draws into it.
displayWrap=""
case "$(uname -s 2>/dev/null)" in
  Linux)
    if [ -z "${DISPLAY:-}" ] && command -v xvfb-run >/dev/null 2>&1; then
      displayWrap="xvfb-run -a"
    fi
    ;;
esac

buildDefines=""
case "$backend" in
  native)  ;;
  gtk4)    buildDefines="-d:gtk4" ;;
  sdl2)    buildDefines="-d:sdl2" ;;
  sdl3)    buildDefines="-d:sdl3" ;;
  html)    buildDefines="-d:html" ;;
  canvas)  buildDefines="-d:canvas" ;;
  jsdom)   ;;
  chrome)  ;;
  *)
    echo "sharks_run: unknown backend '$backend'" >&2
    echo "  one of: native gtk4 sdl2 sdl3 html canvas jsdom chrome" >&2
    exit 2
    ;;
esac

run_native() {
  echo "=== sharks / $backend: build"
  # shellcheck disable=SC2086
  "$nim" c --mm:arc -d:sharksSelftest -d:sharksFrames="$frames" \
      $buildDefines --hints:off --path:"$root/src" \
      --outdir:"$binDir" -o:"$binDir/sharks_$backend" \
      "$root/examples/sharks.nim" > "$log" 2>&1
  code=$?
  if [ "$code" -ne 0 ]; then
    cat "$log"
    echo "sharks_run: $backend build failed (exit $code)" >&2
    return "$code"
  fi
  echo "=== sharks / $backend: run $frames frames"
  if [ -n "$displayWrap" ]; then
    $displayWrap "$binDir/sharks_$backend" >> "$log" 2>&1
  else
    "$binDir/sharks_$backend" >> "$log" 2>&1
  fi
  code=$?
  if [ "$code" -ne 0 ]; then
    cat "$log"
    echo "sharks_run: $backend run failed (exit $code)" >&2
    return "$code"
  fi
  return 0
}

build_selftest_page() {
  # $1 = page path. Compiles examples/sharks.nim with `nim js` and wraps it in
  # the same shell the exported gallery pages get, so what runs in the browser
  # is what a user would open.
  page="$1"
  echo "=== sharks: build the standalone page exporter"
  "$nim" c --mm:arc --hints:off --path:"$root/src" \
      --outdir:"$binDir" -o:"$binDir/exporter" \
      "$root/tools/export_interactive_html.nim" > "$log" 2>&1
  code=$?
  if [ "$code" -ne 0 ]; then
    cat "$log"
    echo "sharks_run: could not build the exporter (exit $code)" >&2
    return "$code"
  fi
  echo "=== sharks: compile examples/sharks.nim with nim js"
  UIRELAYS_ONLY_SELFTEST=1 \
  UIRELAYS_SELFTEST_OUT="$page" \
  UIRELAYS_SELFTEST_FRAMES="$frames" \
  NIM="$nim" \
    "$binDir/exporter" >> "$log" 2>&1
  code=$?
  if [ "$code" -ne 0 ] || [ ! -f "$page" ]; then
    cat "$log"
    echo "sharks_run: could not build the selftest page (exit $code)" >&2
    return 1
  fi
  return 0
}

# Git Bash hands a native chrome.exe a POSIX path it cannot open, so both the
# file:// URL and the profile directory go through cygpath where one exists.
toFileUrl() {
  if command -v cygpath >/dev/null 2>&1; then
    echo "file:///$(cygpath -m "$1")"
  else
    echo "file://$1"
  fi
}

toNativePath() {
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -w "$1"
  else
    echo "$1"
  fi
}

find_browser() {
  if [ -n "${UIRELAYS_BROWSER:-}" ]; then
    echo "$UIRELAYS_BROWSER"
    return 0
  fi
  for c in chromium chromium-browser google-chrome google-chrome-stable chrome msedge; do
    p=$(command -v "$c" 2>/dev/null || true)
    if [ -n "$p" ]; then echo "$p"; return 0; fi
  done
  # Not on PATH: the locations the CI images actually install them in.
  for p in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" \
    "/c/Program Files/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Google/Chrome/Application/chrome.exe" \
    "/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe" \
    "/c/Program Files/Microsoft/Edge/Application/msedge.exe" ; do
    if [ -x "$p" ] || [ -f "$p" ]; then echo "$p"; return 0; fi
  done
  return 1
}

run_chrome() {
  page="$outdir/selftest/chrome_page_src.html"
  build_selftest_page "$page" || return 1
  browser=$(find_browser) || {
    echo "sharks_run: no Chrome/Chromium/Edge found on this machine" >&2
    return 1
  }
  echo "=== sharks / chrome: browser is $browser"
  # Installed before the app's own script, so it sees every console.log the
  # compiled Nim produces and lifts the digest line onto <html>.
  cap='var __origLog=console.log;console.log=function(){try{var s=Array.prototype.join.call(arguments," ");if(s.indexOf("SHARKS_DIGEST")===0){document.documentElement.setAttribute("data-sharks-digest",s);}}catch(e){}return __origLog.apply(console,arguments);};'
  live="$outdir/selftest/chrome_page.html"
  awk -v cap="$cap" 'BEGIN{done=0} { if (!done && index($0,"<script>")>0) { print "<script>" cap "</script>"; done=1 } print }' \
    "$page" > "$live"
  if [ ! -s "$live" ]; then
    echo "sharks_run: could not prepare the Chrome page" >&2
    return 1
  fi
  profile="$outdir/chrome-profile"
  mkdir -p "$profile"
  echo "=== sharks / chrome: headless run, $frames frames"
  "$browser" --headless --disable-gpu --no-sandbox --hide-scrollbars \
    --user-data-dir="$(toNativePath "$profile")" --window-size=1024,640 \
    --virtual-time-budget="${UIRELAYS_SHARKS_VTB:-120000}" \
    --dump-dom "$(toFileUrl "$live")" > "$outdir/chrome_dom.html" 2>>"$log"
  code=$?
  if [ "$code" -ne 0 ]; then
    echo "sharks_run: the browser exited $code" >&2
    tail -n 20 "$log" >&2
    return "$code"
  fi
  sed -n 's/.*data-sharks-digest="\([^"]*\)".*/\1/p' "$outdir/chrome_dom.html" \
    | head -n 1 > "$digestOut"
  if [ ! -s "$digestOut" ]; then
    echo "sharks_run: the browser rendered the page but never logged a digest" >&2
    echo "  dumped DOM: $(wc -c < "$outdir/chrome_dom.html") bytes" >&2
    grep -o 'uir-viewport' "$outdir/chrome_dom.html" | head -n 1 >&2 || true
    return 1
  fi
  cat "$digestOut"
  return 0
}

run_jsdom() {
  page="$outdir/selftest/sharks_selftest.html"
  build_selftest_page "$page" || return 1
  if [ ! -d "$root/tests/jsdom/node_modules" ]; then
    echo "=== sharks / jsdom: npm ci (jsdom is not installed yet)"
    ( cd "$root/tests/jsdom" && "${NPM:-npm}" ci ) >> "$log" 2>&1
  fi
  echo "=== sharks / jsdom: run the page in jsdom"
  "$node_bin" "$root/tests/jsdom/digest_runner.js" "$page" \
      --width=1024 --height=640 --timeout=$((timeout_s * 1000)) >> "$log" 2>&1
  code=$?
  if [ "$code" -ne 0 ]; then
    cat "$log"
    echo "sharks_run: jsdom page failed (exit $code)" >&2
    return "$code"
  fi
  return 0
}

case "$backend" in
  jsdom)  run_jsdom ;;
  chrome) run_chrome ;;
  *)      run_native ;;
esac
code=$?

# The digest is the last SHARKS_DIGEST line the run printed. Taking the last
# one, not the first, means a run that printed a partial line before crashing
# cannot be mistaken for a result.
if [ ! -s "$digestOut" ]; then
  grep '^SHARKS_DIGEST ' "$log" 2>/dev/null | tail -n 1 > "$digestOut"
fi
if [ ! -s "$digestOut" ]; then
  echo "--- last 40 lines of $log" >&2
  tail -n 40 "$log" >&2
  echo "sharks_run: $backend printed no SHARKS_DIGEST line" >&2
  exit 1
fi

cat "$digestOut"
if [ "$code" -ne 0 ]; then
  exit "$code"
fi
exit 0
