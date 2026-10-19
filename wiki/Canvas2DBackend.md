# Бэкенд 2: Отдельный HTML5 `<canvas>` 2D — `canvas_driver.nim`

## Обзор

Бэкенд `canvas_driver.nim` (флаг компиляции `-d:canvas`) реализует рендеринг `uirelays` через стандартный 2D-контекст элемента `<canvas id="uir-canvas">` (`canvas.getContext("2d")`), **без использования WebAssembly (WASM)**.

## Командный конвейер 2D-рендеринга

На каждом кадре вызовы `uirelays` записываются в список JSON-команд, который при вызове `refresh()` сравнивается по 64-битному хэшу `fnv1a64` с предыдущим кадром (для исключения лишних перерисовок в режиме простоя) и отправляется в браузер по SSE (`/events`) или `/state`:

- `{"op":"rect","x":...,"y":...,"w":...,"h":...,"c":"rgb(...)"}` → `ctx.fillRect(x, y, w, h)`
- `{"op":"point","x":...,"y":...,"c":"rgb(...)"}` → `ctx.fillRect(x, y, 1, 1)`
- `{"op":"line","x1":...,"y1":...,"x2":...,"y2":...,"c":"rgb(...)"}` → `ctx.fillRect` (для осевых линий) или `ctx.beginPath(); ctx.moveTo(...); ctx.lineTo(...); ctx.stroke()` (для диагональных)
- `{"op":"text","x":...,"y":...,"w":...,"h":...,"t":...,"font":...,"ascent":...,"fg":...,"bg":...}` → заливка фона `bg` (если `bg.a > 0`) + `ctx.fillText(t, x, y + ascent)`
- `{"op":"save"}`, `{"op":"clip",...}`, `{"op":"restore"}` → управление стеком отсечения `ctx.save()`, `ctx.beginPath()`, `ctx.rect(...)`, `ctx.clip()`, `ctx.restore()`
- `{"op":"img",...}` и `{"op":"blit",...}` → `ctx.drawImage(...)` с клиентским кэшем `Map` декодированных `Image`-объектов.
