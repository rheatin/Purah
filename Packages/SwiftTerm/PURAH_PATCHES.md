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

Nothing else in the tree is modified.
