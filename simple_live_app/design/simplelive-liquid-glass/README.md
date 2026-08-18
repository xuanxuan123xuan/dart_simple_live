# SimpleLive Liquid Glass icon source pack

This directory contains a clean, same-canvas vector source pack for Apple Icon Composer.
Every SVG uses a `1024 x 1024` artboard and preserves the final position of its artwork.

## Layer order

Import the files from bottom to top in this order:

1. `layers/01-background.svg`
2. `layers/02-window.svg`
3. `layers/03-window-chrome.svg`
4. `layers/04-play.svg`
5. `layers/05-floating-danmaku.svg`
6. `layers/06-live-bubble.svg`
7. `layers/07-live-signal.svg`
8. `layers/08-simplelive-wordmark.svg`

`SimpleLive` is intentionally retained as its own vector-path layer. It contains no live font
dependency, so the lettering remains present and stable when the file is moved to a Mac.

## Suggested Icon Composer grouping

- Canvas: `01-background.svg`
- Window: `02-window.svg` + `03-window-chrome.svg`
- Playback: `04-play.svg`
- Floating comments: `05-floating-danmaku.svg`
- Live status: `06-live-bubble.svg` + `07-live-signal.svg`
- Brand: `08-simplelive-wordmark.svg`

Use Icon Composer for specular highlights, refraction, translucency, and dynamic shadows.
The layer SVGs deliberately avoid baked blur, bevels, and drop shadows.

Suggested treatment:

- Window: low refraction, subtle outer highlight, restrained shadow.
- Playback: low translucency, medium specular highlight.
- Floating comments: medium translucency and refraction, stronger floating shadow.
- Live bubble: low translucency, medium outer highlight.
- Live signal: glass off or nearly off, so yellow stays saturated.
- Brand: glass off, high contrast in every appearance mode; keep visible in Default, Dark,
  Tinted, Clear Light, and Clear Dark.

## Delivery

On macOS, import the eight SVG files into Icon Composer, tune each appearance, save the resulting
`.icon` document, drag it into Xcode, and select it as the app icon in the project editor.

`preview.svg` is only a visual assembly preview. Do not import it as a Liquid Glass layer.

