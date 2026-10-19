# Бэкенд 1: Чистый Vanilla HTML5 + CSS3 + JS (DOM) — `html_driver.nim`

## Обзор

Бэкенд `html_driver.nim` (флаг компиляции `-d:html`) реализует графический интерфейс `uirelays` исключительно средствами **DOM-дерева HTML5, таблиц стилей CSS3 и чистого JavaScript**, **без единого элемента `<canvas>` и без WebAssembly (WASM)**.

## Отображение примитивов `uirelays` в DOM

| Вызов `uirelays` | Генерируемый DOM / CSS3 элемент |
|------------------|---------------------------------|
| `fillRect(r, color)` | `<div class="uir-rect" style="left:Xpx;top:Ypx;width:Wpx;height:Hpx;background:rgba(...);"></div>` |
| `drawPoint(x, y, color)` | `<div class="uir-point" style="left:Xpx;top:Ypx;width:1px;height:1px;background:rgba(...);"></div>` |
| `drawLine` (горизонтальная) | `<div class="uir-line-h" style="left:Xpx;top:Ypx;width:Wpx;height:1px;background:rgba(...);"></div>` |
| `drawLine` (вертикальная) | `<div class="uir-line-v" style="left:Xpx;top:Ypx;width:1px;height:Hpx;background:rgba(...);"></div>` |
| `drawLine` (диагональная) | `<svg class="uir-svg-line" ...><line x1="..." y1="..." x2="..." y2="..." stroke="rgba(...)"/></svg>` |
| `drawText` / `drawMeasuredText` | `<span class="uir-text" style="left:Xpx;top:Ypx;font-family:...;font-size:...;">...</span>` |
| `setClipRect(r)` + `saveState`/`restoreState` | `<div class="uir-clip" style="position:absolute;left:0;top:0;width:100%;height:100%;clip-path:polygon(...);">...</div>` |
| `drawImage(img, src, dst)` | `<div class="uir-img-crop" style="overflow:hidden;..."><img class="uir-img" src="data:..." /></div>` |
| `blitRGBA(pixels, w, h, dst)` | Чисто-Nim кодирование буфера `uint32` в PNG (`encodeRgbaToPngDataUri`) → `<div class="uir-blit-clip"><img class="uir-blit" src="data:image/png;base64,..." /></div>` |
