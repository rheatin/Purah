# Local patches to the vendored SwiftTerm

This is a checked-in copy, not a remote dependency: `Package.swift` points at
`.package(path: "Packages/SwiftTerm")`, so upstream never arrives on its own.
The only way a change lands here is a person copying a newer release in, and
that copy drops everything below unless it is re-applied by hand.

Check this list after any re-vendor, then run `swift build --disable-sandbox`
and open the Terminal drawer.

1. **`Package.swift`** — tools version bumped to 6.0, macOS deployment raised,
   `Apple/Metal/Shaders.metal` and `Mac/README.md` excluded from the target.
2. **`Apple/Metal/MetalTerminalRenderer.swift`** — shaders embedded as source
   strings; the external Metal toolchain cryptex is not available at build time.
3. **`Mac/MacTerminalView.swift`, `FontSet.italicized`** — SGR 3 slants a font
   family that ships no italic face (PT Mono, SF Mono). `NSFontManager` returns
   the upright font for those, so the terminal drew italics as plain text. The
   shear matrix has to go through `CTFontCreateWithFontDescriptorAndOptions`;
   the `.matrix` attribute on `NSFontDescriptor` renders stray dots.

4. **`Mac/MacTerminalView.swift`, scroller** — `scrollerStyle` is `.overlay`
   instead of `.legacy`. The legacy style draws a permanent track down the
   right edge, which read as a scrollbar bolted onto the drawer card. The knob
   starts at `alphaValue = 0`, fades in from `scrollWheel`, and fades out 0.9s
   after the hand stops; it stays hidden entirely while `canScroll` is false.
   The scroller is `PurahScroller`, which draws a 4pt bar and nothing else:
   overlay style still paints a translucent slot, and that slot is the frame
   people saw around the bar.

Nothing else in the tree is modified.
