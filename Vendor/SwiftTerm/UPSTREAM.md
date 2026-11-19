# SwiftTerm source

Source: https://github.com/migueldeicaza/SwiftTerm

Pinned tag: `v1.20.0`

Upstream revision: `5d14406844143538cd8f8851d2d8a67c1fe443e5`

Downloaded from the upstream tag archive, without a Git checkout. See `LICENSE` for the MIT license and copyright notices.

Local packaging changes:

- The package manifest builds only the macOS library, without upstream CLI tools, documentation plugins, remote dependencies, or the Git-based build-info plugin.
- `Sources/SwiftTerm/SwiftTermBuildInfo.swift` supplies the pinned version directly.
- The app uses the CoreGraphics renderer. The optional Metal shader resource is excluded from the package.
- Upstream tooling and example apps are omitted from this vendored copy.

Local terminal changes:

- The macOS view forwards right/middle presses, drags, and releases when the application enables mouse reporting, respecting Shift bypass and the requested tracking mode.
- AppKit right/middle button numbers are translated to terminal button numbers.
- SGR and SGR-pixel releases retain the released button's identity; legacy mouse reports retain their generic release encoding.
