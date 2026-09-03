# libmpv-ohos-build

Build scripts of [libmpv](https://github.com/mpv-player/mpv) for ohos-arm64 (API 15+).

Scripts are compatible with macOS, Linux and WSL, Windows is not supported.

## Build Dependencies

- git
- make
- python3
- pkg-conf
- gperf
- meson

ohos sdk is automatically downloaded on Linux / WSL, but you need to manually download DevEco Studio on your mac.

## Build

```shell
chmod +x *.sh */*.sh
./bundle.sh
```

## Patches

`patches/` contains diffs applied on top of upstream dependencies before building.
`patch.sh` applies them automatically as part of `bundle.sh`.

### Sync patches after modifying source code

Changes to upstream source code (ffmpeg, libplacebo, etc.) are made **in the WSL
build copy** (`~/libmpv-ohos-build-<date>/libmpv/<dep>/`), not directly in this repo.
After editing and verifying a build, export the diff back to this repo's `patches/`:

```bash
# Example: export ffmpeg changes
git -C ~/libmpv-ohos-build-<date>/libmpv/ffmpeg diff HEAD \
    -- libavcodec/ohdec.c libavutil/hwcontext_oh.c libavutil/hwcontext_oh.h \
    > /mnt/d/<path-to-this-repo>/patches/ffmpeg/support-zero-copy-hardware-decode.patch

# Then commit from Windows side (PowerShell)
$r = "D:\<path-to-this-repo>"
git -C $r add patches/
git -C $r commit -m "fix: ..."
```

See `BUILD-NOTES.md` section 10 for the full workflow and constraints.
