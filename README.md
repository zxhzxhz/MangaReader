# MangaReader

MangaReader is an iPadOS comic and manga reader for locally managed archives and
folders. It runs ONNX super-resolution and sharpening models on device through
ONNX Runtime, and builds an unsigned `.ipa` in GitHub Actions without requiring
an Apple ID.

## Features

- iPadOS 18+, SwiftUI, simplified Chinese and English UI.
- Library root is the app's `Documents` folder. Put folders and archives there
  through the Files app; the library scanner reconciles them on launch and when
  the app returns to the foreground.
- ZIP and 7Z reading through libarchive (`SwiftArchive`), RAR reading through
  UnrarKit. Encrypted archives are supported with per-book passwords stored in
  the Keychain.
- Lazy, capped recursive indexing for wrapped and nested archives, with natural
  page ordering and protection against path traversal and oversized entries.
- File management inside the app library: create folders, copy, move, rename,
  delete, and extract archives into editable folders.
- Custom covers from any page, using a lazy thumbnail grid and a mature crop
  control. Covers are stored as app metadata; source files are never rewritten.
- ONNX enhancement with a global default profile and a per-session toggle.
  Built-in templates cover common waifu2x and Real-ESRGAN variants. Arbitrary
  ONNX models can be configured through profiles.
- LRU derived cache (thumbnails, extracted pages, enhanced pages) with a
  default 5 GB limit.

## Important distribution note

The GitHub Actions artifact is an **unsigned** `.ipa`. It cannot be installed
directly on an unmodified, unjailbroken iPad. To install it you need one of:

- re-sign the app with your own Apple ID and provisioning profile;
- a personal signing service or third-party sideload workflow;
- a jailbroken device.

The project intentionally does not include any Apple ID or signing secrets.

## Build

The project uses XcodeGen and CocoaPods:

```bash
brew install xcodegen
xcodegen generate
pod install
open MangaReader.xcworkspace
```

GitHub Actions performs this build on a macOS runner and packages an unsigned
IPA. Push builds run unit tests; `v*` tags attach the IPA to a GitHub Release.

## Library layout

```text
Documents/
  Models/          # user-provided .onnx files
  <your manga>/
  <your manga>.zip
```

## ONNX models

Model files are not bundled with the repository. Drop `.onnx` files into
`Documents/Models`, then create or edit a model profile in Settings. A profile
describes tensor names, scale, tiling, colorspace, normalization, alpha
handling, denoise level, and execution provider. A tiny validation run checks
that the output shape matches the configured scale.

`AnimeSharpV4` is intentionally a custom-profile placeholder until exact model
and tensor specifications are supplied.

## License and third-party notices

The app is MIT licensed. Third-party components and their licenses are listed
in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
