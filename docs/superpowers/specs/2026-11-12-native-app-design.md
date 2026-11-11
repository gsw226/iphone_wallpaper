# Text Wallpaper — native iOS app

Replaces the web MVP. Everything happens inside the app: several sentences on ONE
lock-screen wallpaper, background is a color or a photo from the library.

## Decisions

- SwiftUI, iOS 18+, iPhone only, portrait. XcodeGen (`ios/project.yml`), no packages.
- One design at a time (no saved list). Autosaved to Documents as JSON + photo JPEG.
- Free-form layout: each sentence is a text block the user drags anywhere on the preview;
  each block has its own text, font, size, color, wrap width. Default first block sits
  under the clock zone.
- Preview and export use the SAME SwiftUI view (`WallpaperView`); all geometry is a
  fraction of the wallpaper size, so preview == PNG.
- Fonts bundled (OFL, from github.com/google/fonts): Noto Sans KR Bold, Noto Serif KR Bold,
  Gowun Dodum, Nanum Pen Script. Pen gets an optical size bump.
- Applying: iOS has no wallpaper API for apps. The app renders a PNG, puts it on the
  pasteboard and opens
  `shortcuts://x-callback-url/run-shortcut?name=문장 배경화면&input=clipboard&x-success=textwallpaper://done`.
  The shortcut "문장 배경화면" (already in `shortcut/`) sets the lock screen.
  Fallbacks: ShareLink (share sheet → shortcut), Save to Photos.
- Lock-screen guide overlay in the editor only: clock zone top 0.35, button zone bottom 0.14.

## Modules (contract = the stubs in `ios/TextWallpaper/`)

| File | Owner | Contract |
|---|---|---|
| Model/Design.swift | lead | `Design`, `TextBlock`, `Background`, `FontChoice`, `RGBA`, `LockZones` |
| Model/DesignStore.swift | core | `@MainActor ObservableObject`: `design` (autosave), `photo`, `init(directory:)`, `setPhoto(_:)`, `clearPhoto(color:)` |
| Render/WallpaperView.swift | core | `WallpaperView(design:photo:)` fills its frame |
| Render/WallpaperRenderer.swift | core | `outputSize`, `render(_:photo:) -> UIImage?`, `pngData(_:photo:) -> Data?` |
| Render/Fonts.swift | core | `FontChoice.label`, `FontChoice.font(size:) -> Font` |
| Editor/* | editor | `EditorView` (root) + any subviews |
| Apply/ApplyService.swift | apply | `applyViaShortcut(png:)`, `saveToPhotos(png:completion:)`, `WallpaperPNG: Transferable` |

## Testing

- XCTest: Design codable round-trip, store save/load + photo file, renderer output size
  and non-empty PNG, block geometry is resolution-independent.
- Real device (iPhone 15 Pro, iOS 27.2) via `ios/scripts/run-device.sh` and iPhone Mirroring.
