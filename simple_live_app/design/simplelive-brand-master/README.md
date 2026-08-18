# SimpleLive cross-platform brand masters

These files are deterministic exports of the approved layered SimpleLive artwork.
They retain the yellow live signal, centered play symbol, floating comments, and
outlined `SimpleLive` wordmark.

## Masters

- `simplelive-master-1024.*`: full-bleed warm-background master for stores, previews,
  and source exports.
- `simplelive-rounded-transparent-1024.*`: baked rounded-square master with transparent
  outer corners for Windows, Linux, HarmonyOS, and other unmasked surfaces.
- `simplelive-android-foreground-1024.*`: transparent, safe-area-inset foreground for
  Android adaptive icons. Pair it with background color `#F8F5EF`.

Both SVG and 1024 x 1024 PNG forms are retained. Generate them again with:

```powershell
$env:NODE_PATH='C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\node_modules'
& 'C:\Users\ROG\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin\node.exe' simple_live_app/tool/generate_brand_masters.mjs
```

The same command also updates the in-app preview, Android adaptive and legacy launcher
resources, and the iOS `AppIconSimpleLive` alternate icon set.

The generator inlines the vector wordmark before rendering, so the output has no font
or external-image dependency.
