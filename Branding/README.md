# Tempo logo and app icon

An original rounded T with a curved stem, drawn from vector paths. The mark suggests rhythm and continuity. Deep ink `#10272B` and teal `#50DCC8` are the primary colours. In-app template images use the native teal tint for light/dark appearance.

Download `Tempo-Logo-Kit.zip` for the standalone assets, or use the folders directly.

## Files

- `tempo-app-icon-1024.png`: opaque 1024 × 1024 Home Screen icon; no pre-rounded corners. iOS applies the icon mask.
- `AppIcon.appiconset/`: Xcode-ready icon folder, including Contents.json.
- `tempo-mark-transparent.png`: 1024 × 1024 teal mark with transparent background.
- `TempoMark.imageset/`: template mark at 1×, 2× and 3× for native in-app tinting.
- `tempo-mark.svg`: editable transparent vector mark.
- `tempo-wordmark.svg`: mark and typographic name for documentation; text uses system-font fallbacks.
- `tempo-app-icon.svg`: editable vector icon with deep-ink background.

## Use in Xcode

The repository already includes the icon and logo in `Tempo/Resources/Assets.xcassets`, and the Tempo target selects `AppIcon`. Build and install the app on your phone and the new icon is included automatically. The mark is shown in Today and Settings.

For another project, drag `AppIcon.appiconset` and `TempoMark.imageset` into its asset catalog. In the app target's General settings select `AppIcon` as the App Icons Source. Display `Image("TempoMark")` with a foreground tint. Keep its proportions and leave sufficient space around the mark.

To regenerate all files on a Mac with Xcode installed:

```sh
python3 Scripts/create_icon.py
```

The generator writes both this export folder and the app catalog, keeping them identical. The artwork is original and covered by this repository's MIT licence.
