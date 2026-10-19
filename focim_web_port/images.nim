## Pictures in the editor: decoded and scaled with pixie, handed to the driver
## as finished pixels.
##
## The X11 driver focim runs on on Linux does not decode pictures, and it
## should not have to. An editor that shows a PNG named in a markdown file is
## asking for a decoder, not for a driver rewrite, and a decoder that lives in
## a driver is a decoder every application linking uirelays pays for whether
## or not it ever shows a picture. So the three image relays are filled in
## here instead, on top of the one thing the driver does offer for this:
## `blitRGBA`, which takes finished pixels and hands back its clip rectangle
## and its frame's dirty tracking in return for going through it.
##
## Nothing here is X11's. A driver that offers `blitRGBA` and has no decoder
## of its own gets pictures the moment it offers it, and a driver that brings
## its own -- the figdraw ones, Cocoa -- keeps them: `installPixieImages`
## looks before it overwrites.

from uirelays/screen import nil
from uirelays/coords import nil

const uirelaysWebDriver =
  defined(html) or defined(uirelaysHtml) or defined(features.uirelays.html) or
  defined(canvas) or defined(uirelaysCanvas) or defined(features.uirelays.canvas)

when uirelaysWebDriver:
  proc setImageBackdrop*(c: screen.Color) = discard
  proc installPixieImages*() = discard
else:
  import pixie

  type
    Slot = object
      ## One picture, as it was asked for by path.
      src: pixie.Image
        ## What the file decoded to, at its own size. `nil` marks a free slot:
        ## a file that would not decode never gets one, so a slot only becomes
        ## `nil` again by being freed, and the next load takes it back.
      pixels: seq[uint32]
        ## The last thing blitted -- cropped, scaled and composited, ready for
        ## the surface. A frame that asks for the same picture the same way as
        ## the frame before it does no work at all, which is the ordinary case:
        ## an editor redraws continuously and a picture in it rarely moves.
      outW, outH: int         ## what `pixels` was built for
      srcRect: coords.Rect    ## ... and out of which part of `src`
      backdrop: uint32        ## ... and against which background

  var
    slots: seq[Slot]
    backdrop: uint32 = 0x1E1E2E'u32
      ## What transparency shows. A surface is handed opaque pixels because
      ## `blitRGBA` does not blend, so anything see-through has to be resolved
      ## against something here -- and the something is whatever the editor
      ## painted the row with, which is why `setImageBackdrop` exists and is
      ## called every frame rather than once.

  proc setImageBackdrop*(c: screen.Color) =
    ## The color to resolve transparency against: the background the picture is
    ## being drawn on. Cheap to call every frame, and meant to be -- the theme
    ## can change with any keystroke in the config tab.
    let p = (c.r.uint32 shl 16) or (c.g.uint32 shl 8) or (c.b.uint32)
    if p != backdrop:
      backdrop = p
      # Every composited buffer was resolved against the old color and is now
      # the wrong picture. Dropping them is enough to have them built again.
      for s in slots.mitems: s.outW = 0

  proc pixieLoadImage(path: string): screen.Image {.nimcall.} =
    var decoded: pixie.Image = nil
    # A path out of a markdown file is a path a person typed: it may be
    # misspelled, may point at a directory, may be a PNG that is not one. None
    # of that is the editor's to fix, and none of it is worth a crash -- the
    # caller draws its placeholder for a picture that would not load, which
    # says more to whoever typed the path than a working picture ever could.
    try:
      decoded = readImage(path)
    except CatchableError:
      return screen.Image(0)
    if decoded == nil or decoded.width <= 0 or decoded.height <= 0:
      return screen.Image(0)
    for i in 0 ..< slots.len:
      if slots[i].src == nil:
        slots[i] = Slot(src: decoded)
        return screen.Image(i + 1)
    slots.add Slot(src: decoded)
    result = screen.Image(slots.len)

  proc pixieFreeImage(img: screen.Image) {.nimcall.} =
    let i = img.int - 1
    if i >= 0 and i < slots.len:
      slots[i] = Slot()

  proc pixieImageSize(img: screen.Image): tuple[w, h: int] {.nimcall.} =
    let i = img.int - 1
    if i >= 0 and i < slots.len and slots[i].src != nil:
      (slots[i].src.width, slots[i].src.height)
    else:
      (0, 0)

  proc rebuild(s: var Slot; src: coords.Rect; w, h: int) =
    ## Crop, scale and flatten, in that order, into `s.pixels`.
    let iw = s.src.width
    let ih = s.src.height
    # A source rectangle from a caller that measured with `imageSize` is the
    # whole picture; one from a caller that could not is anything at all. Clamp
    # rather than refuse: a crop that hangs off the edge means the visible part
    # of it, and an empty one means all of it.
    var x = clamp(src.x, 0, iw)
    var y = clamp(src.y, 0, ih)
    var cw = clamp(src.w, 0, iw - x)
    var ch = clamp(src.h, 0, ih - y)
    if cw <= 0 or ch <= 0:
      x = 0; y = 0; cw = iw; ch = ih
    var part = s.src
    if x != 0 or y != 0 or cw != iw or ch != ih:
      part = s.src.subImage(x, y, cw, ch)
    let scaled = if part.width == w and part.height == h: part
                 else: part.resize(w, h)

    let br = (backdrop shr 16) and 0xFF
    let bg = (backdrop shr 8) and 0xFF
    let bb = backdrop and 0xFF
    s.pixels.setLen w * h
    for idx in 0 ..< w * h:
      let c = scaled.data[idx]
      if c.a == 255:
        # The ordinary case, and worth its own line: a screenshot or a photo is
        # opaque everywhere and needs no arithmetic to prove it.
        s.pixels[idx] = (c.r.uint32 shl 16) or (c.g.uint32 shl 8) or c.b.uint32
      else:
        # Pixie keeps color premultiplied by alpha, which is exactly the form
        # `over` wants: the source contributes itself and the background what
        # is left of it. No dividing back out, and nothing to get wrong about
        # a fully transparent pixel.
        let inv = 255'u32 - c.a.uint32
        let r = min(255'u32, c.r.uint32 + (br * inv + 127) div 255)
        let g = min(255'u32, c.g.uint32 + (bg * inv + 127) div 255)
        let b = min(255'u32, c.b.uint32 + (bb * inv + 127) div 255)
        s.pixels[idx] = (r shl 16) or (g shl 8) or b

    s.outW = w
    s.outH = h
    # What was asked for, not what it clamped to: this is a cache key, and it
    # is compared against the next caller's question rather than against this
    # one's answer.
    s.srcRect = src
    s.backdrop = backdrop

  proc pixieDrawImage(img: screen.Image; src, dst: coords.Rect) {.nimcall.} =
    let i = img.int - 1
    if i < 0 or i >= slots.len or slots[i].src == nil: return
    if dst.w <= 0 or dst.h <= 0: return
    let s = addr slots[i]
    if s.outW != dst.w or s.outH != dst.h or s.backdrop != backdrop or
        s.srcRect != src:
      try:
        rebuild(s[], src, dst.w, dst.h)
      except CatchableError:
        # `resize` of a picture into an implausible shape is the only way here,
        # and a frame that cannot scale one has nothing better to do than skip
        # it. The slot keeps whatever it had, so the next frame tries again.
        s.outW = 0
        return
    if s.pixels.len > 0:
      discard screen.blitRGBA(
        cast[ptr UncheckedArray[uint32]](addr s.pixels[0]), s.outW, s.outH, dst)

  proc installPixieImages*() =
    ## Fill in the image relays, if the driver wants them filled in.
    ##
    ## Two conditions, and both are refusals to be clever. A driver that
    ## decodes pictures itself is left alone, because it knows things about its
    ## own surface that this cannot -- the figdraw drivers hold the picture in
    ## the same form they composite in, and going through pixels here would be
    ## a decode and a scale to throw away. And a driver with no `blitRGBA` gets
    ## nothing, because there would be nowhere to put the result: better the
    ## editor's placeholder, which says which file it wanted, than three relays
    ## that quietly draw nothing.
    if screen.drawRelays.blitRGBA == nil: return
    if screen.drawRelays.loadImage != nil: return
    screen.drawRelays.loadImage = pixieLoadImage
    screen.drawRelays.freeImage = pixieFreeImage
    screen.drawRelays.drawImage = pixieDrawImage
    screen.drawRelays.imageSize = pixieImageSize
