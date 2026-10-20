"""Prepare Linux native libraries and package AppImage without parallel copies."""

import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.request


# FFmpegKit 8.1.2 is built on Jammy and needs ABI 7, not Noble's ABI 9.
# Keep this compatibility library private to the app; never replace the OS copy.
VPX_URL = (
    "https://security.ubuntu.com/ubuntu/pool/main/libv/libvpx/"
    "libvpx7_1.11.0-2ubuntu2.5_amd64.deb"
)
VPX_SHA256 = "5561f3376bb9232d098a44dabc33eed3b3abfeec751c27893b58b6e6912684e0"


def run(*args, env=None, merge_stderr=False):
    result = subprocess.run(
        args, env=env, text=True, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT if merge_stderr else subprocess.PIPE)
    if result.returncode:
        raise RuntimeError(f"{args!r}\n{result.stdout}\n{result.stderr}")
    return result.stdout


def parse_dependencies(output):
    dependencies = set()
    for line in output.splitlines():
        if "=> not found" in line or "undefined symbol:" in line:
            raise RuntimeError(f"Unresolved native dependency: {line.strip()}")
        if "=>" not in line:
            continue
        resolved = line.split("=>", 1)[1].strip()
        match = re.fullmatch(r"(/.+?)\s+\(0x[0-9a-fA-F]+\)", resolved)
        if not match:
            raise RuntimeError(f"Unexpected ldd result: {line.strip()}")
        dependencies.add(Path(match[1]))
    return dependencies


def native_libraries(bundle):
    return sorted(p for p in (bundle / "lib").glob("*.so*")
                  if p.is_file() and p.name != "libapp.so")


def dependencies(library, bundle):
    # Explicitly resolve siblings for both ldd and its transitive dependencies.
    env = dict(os.environ, LD_LIBRARY_PATH=str(bundle / "lib"), LC_ALL="C")
    return parse_dependencies(run("ldd", "-r", str(library), env=env, merge_stderr=True))


def prepare(bundle):
    if not (bundle / "lib/libffmpegkit.so").is_file():
        raise RuntimeError("FFmpegKit is missing from the Flutter Linux bundle")
    with tempfile.TemporaryDirectory(prefix="simple-live-vpx-") as work:
        work = Path(work)
        package = work / "libvpx7.deb"
        with urllib.request.urlopen(VPX_URL, timeout=60) as response:
            package.write_bytes(response.read())
        if hashlib.sha256(package.read_bytes()).hexdigest() != VPX_SHA256:
            raise RuntimeError("libvpx7 package checksum mismatch")
        run("dpkg-deb", "-x", str(package), str(work / "unpacked"))
        root = work / "unpacked"
        shutil.copy2(root / "usr/lib/x86_64-linux-gnu/libvpx.so.7",
                     bundle / "lib/libvpx.so.7")
        notices = bundle / "data/licenses/libvpx7"
        notices.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / "usr/share/doc/libvpx7/copyright", notices)

    # Patch each real ELF once: patchelf can replace a symlink with a full copy.
    for library in sorted({p.resolve() for p in native_libraries(bundle)}):
        # RUNPATH is not inherited by indirect dependencies. Each FFmpeg .so
        # needs its own $ORIGIN so the DEB also works without LD_LIBRARY_PATH.
        current = run("patchelf", "--print-rpath", str(library)).strip()
        paths = list(dict.fromkeys(["$ORIGIN", *filter(None, current.split(":"))]))
        run("patchelf", "--set-rpath", ":".join(paths), str(library))
    for library in native_libraries(bundle):
        dependencies(library, bundle)
    print("Linux bundle: all native libraries resolve, including FFmpegKit")


def stage_dependencies(sources, destination, bundle):
    by_name = {}
    bundle_lib = (bundle / "lib").resolve()
    for source in sorted(sources):
        if source.resolve().parent == bundle_lib:
            continue  # already carried in AppDir/lib
        previous = by_name.setdefault(source.name, source)
        if previous.resolve() != source.resolve():
            raise RuntimeError(f"Conflicting native libraries: {previous}, {source}")
    destination.mkdir(parents=True, exist_ok=True)
    for name, source in by_name.items():
        shutil.copy2(source, destination / name)


def appimage(bundle, version):
    import yaml  # installed explicitly as python3-yaml by the Linux workflows

    config = yaml.safe_load(Path("linux/packaging/appimage/make_config.yaml").read_text())
    if config.get("include"):
        raise RuntimeError("Explicit AppImage includes need dependency resolution")
    output = Path("build/dist") / version
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="simple-live-appimage-") as work:
        appdir = Path(work) / "simple_live_app.AppDir"
        shutil.copytree(bundle, appdir, symlinks=True)
        # Match the Flutter/GTK runtime baseline used by Fastforge. Collect all
        # other dependencies into a set and copy once, in a deterministic order.
        baseline = dependencies(bundle / "lib/libflutter_linux_gtk.so", bundle)
        required = set()
        for library in native_libraries(bundle):
            required.update(dependencies(library, bundle) - baseline)
        stage_dependencies(required, appdir / "usr/lib", bundle)
        icon = Path(config["icon"])
        shutil.copy2(icon, appdir / f"simple_live_app{icon.suffix}")
        desktop = {
            "Type": "Application", "Name": config["display_name"],
            "GenericName": config["generic_name"],
            "Exec": "simple_live_app %u", "Icon": "simple_live_app",
            "StartupNotify": str(config.get("startup_notify", False)).lower(),
            "Categories": ";".join(config.get("categories", [])) + ";",
            "Keywords": ";".join(config.get("keywords", [])) + ";",
        }
        (appdir / "simple_live_app.desktop").write_text(
            "[Desktop Entry]\n" + "".join(f"{k}={v}\n" for k, v in desktop.items()))
        launcher = appdir / "AppRun"
        launcher.write_text(
            '#!/bin/sh\n'
            'APPDIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)\n'
            'export LD_LIBRARY_PATH="$APPDIR/lib:$APPDIR/usr/lib"\n'
            'exec "$APPDIR/simple_live_app" "$@"\n')
        launcher.chmod(0o755)
        artifact = (output / f"simple_live_app-{version}-linux.AppImage").resolve()
        run("appimagetool", "--no-appstream", str(appdir), str(artifact),
            env=dict(os.environ, ARCH="x86_64", APPIMAGE_EXTRACT_AND_RUN="1"))
        if not artifact.is_file() or artifact.stat().st_size == 0:
            raise RuntimeError("appimagetool did not produce an AppImage")
        print(artifact)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["prepare", "appimage"])
    parser.add_argument("--bundle", type=Path,
                        default=Path(os.environ.get("BUILD_OUTPUT_DIRECTORY",
                                                    "build/linux/x64/release/bundle")))
    parser.add_argument("--version")
    args = parser.parse_args()
    bundle = args.bundle.resolve()
    if args.mode == "prepare":
        prepare(bundle)
    elif args.version and re.fullmatch(r"\d+\.\d+\.\d+\+\d+", args.version):
        appimage(bundle, args.version)
    else:
        parser.error("appimage requires --version major.minor.patch+build")


if __name__ == "__main__":
    main()
