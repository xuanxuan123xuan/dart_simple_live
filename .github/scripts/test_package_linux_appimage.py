import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    "package_linux_appimage", Path(__file__).with_name("package_linux_appimage.py"))
packager = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packager)


class NativeDependenciesTest(unittest.TestCase):
    def test_missing_dependency_is_an_error_instead_of_a_path_named_not(self):
        with self.assertRaisesRegex(RuntimeError, "libavutil.so.60 => not found"):
            packager.parse_dependencies("\tlibavutil.so.60 => not found\n")

    def test_unresolved_symbols_are_rejected_even_when_ldd_exits_zero(self):
        with self.assertRaisesRegex(RuntimeError, "av_free"):
            packager.parse_dependencies("undefined symbol: av_free (libswscale.so.9)")

    def test_resolves_unique_paths_and_ignores_the_dynamic_loader(self):
        self.assertEqual(packager.parse_dependencies(
            "linux-vdso.so.1 (0xabc)\n"
            "libc.so.6 => /lib/libc.so.6 (0xabc)\n"
            "libc.so.6 => /lib/libc.so.6 (0xdef)\n"
            "/lib64/ld-linux-x86-64.so.2 (0x123)\n"),
            {Path("/lib/libc.so.6")})

    def test_unexpected_ldd_output_is_not_silently_ignored(self):
        with self.assertRaisesRegex(RuntimeError, "Unexpected ldd"):
            packager.parse_dependencies("libvpx.so.7 => relative/path (0xabc)")

    def test_dependency_resolution_uses_bundle_directory_and_checks_relocations(self):
        bundle = Path("bundle").resolve()
        with patch.object(packager, "run", return_value="") as run:
            packager.dependencies(bundle / "lib/libffmpegkit.so", bundle)
        self.assertEqual(run.call_args.args[:2], ("ldd", "-r"))
        self.assertEqual(run.call_args.kwargs["env"]["LD_LIBRARY_PATH"],
                         str(bundle / "lib"))
        self.assertEqual(run.call_args.kwargs["env"]["LC_ALL"], "C")
        self.assertTrue(run.call_args.kwargs["merge_stderr"])

    def test_relocation_diagnostics_on_stderr_are_not_discarded(self):
        result = subprocess.CompletedProcess([], 0,
            "libc.so.6 => /lib/libc.so.6 (0xabc)\nundefined symbol: av_free\n")
        with patch.object(packager.subprocess, "run", return_value=result) as run:
            with self.assertRaisesRegex(RuntimeError, "av_free"):
                packager.dependencies(Path("libffmpegkit.so"), Path("bundle"))
        self.assertEqual(run.call_args.kwargs["stderr"], subprocess.STDOUT)

    def test_shared_dependencies_are_copied_once_and_bundled_ones_are_skipped(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            bundle = root / "bundle"
            (bundle / "lib").mkdir(parents=True)
            bundled = bundle / "lib/libavutil.so.60"
            bundled.write_bytes(b"bundled")
            external = root / "libvpx.so.7"
            external.write_bytes(b"external")
            dest = root / "AppDir/usr/lib"
            with patch.object(packager.shutil, "copy2", wraps=packager.shutil.copy2) as copy:
                packager.stage_dependencies([external, bundled, external], dest, bundle)
            self.assertEqual(copy.call_count, 1)
            self.assertEqual((dest / external.name).read_bytes(), b"external")
            self.assertFalse((dest / bundled.name).exists())

    def test_two_different_libraries_with_the_same_filename_fail_before_copy(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            files = [root / "a/libsame.so", root / "b/libsame.so"]
            for file in files:
                file.parent.mkdir()
                file.write_bytes(b"library")
            with patch.object(packager.shutil, "copy2") as copy:
                with self.assertRaisesRegex(RuntimeError, "Conflicting native libraries"):
                    packager.stage_dependencies(files, root / "dest", root / "bundle")
            copy.assert_not_called()

    def test_incorrect_download_checksum_is_rejected_before_extraction(self):
        with tempfile.TemporaryDirectory() as work:
            bundle = Path(work)
            (bundle / "lib").mkdir()
            (bundle / "lib/libffmpegkit.so").write_bytes(b"library")
            with patch.object(packager.urllib.request, "urlopen") as urlopen:
                urlopen.return_value.__enter__.return_value.read.return_value = b"bad package"
                with patch.object(packager, "run") as run:
                    with self.assertRaisesRegex(RuntimeError, "checksum mismatch"):
                        packager.prepare(bundle)
            run.assert_not_called()

    def test_appimage_preserves_assets_and_launcher_arguments(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            bundle = root / "bundle"
            (bundle / "lib").mkdir(parents=True)
            (bundle / "lib/libflutter_linux_gtk.so").write_bytes(b"flutter")
            (bundle / "lib/libffmpegkit.so").write_bytes(b"ffmpeg")
            (bundle / "simple_live_app").write_bytes(b"executable")
            (bundle / "data").mkdir()
            (bundle / "data/asset").write_bytes(b"asset")
            icon = root / "icon.png"
            icon.write_bytes(b"icon")
            config = {"display_name": "Simple Live", "generic_name": "Live Stream Viewer",
                      "icon": str(icon), "include": [], "categories": ["AudioVideo"]}
            config_path = Path("linux/packaging/appimage/make_config.yaml")
            read_text = Path.read_text

            def read(path, *args, **kwargs):
                return "config" if path == config_path else read_text(path, *args, **kwargs)

            def make(*args, **kwargs):
                self.assertEqual(args[:2], ("appimagetool", "--no-appstream"))
                appdir = Path(args[2])
                self.assertEqual((appdir / "data/asset").read_bytes(), b"asset")
                self.assertEqual((appdir / "lib/libffmpegkit.so").read_bytes(), b"ffmpeg")
                self.assertIn('"$APPDIR/simple_live_app" "$@"', (appdir / "AppRun").read_text())
                self.assertIn("Name=Simple Live", (appdir / "simple_live_app.desktop").read_text())
                Path(args[3]).write_bytes(b"AppImage")
                return ""

            # Exercise the actual staging path without requiring Linux ELF tools.
            with patch.dict("sys.modules", {"yaml": SimpleNamespace(safe_load=lambda _: config)}), \
                    patch.object(Path, "read_text", read), \
                    patch.object(packager, "dependencies", return_value=set()), \
                    patch.object(packager, "run", side_effect=make):
                # appimage output is relative to cwd; isolate it as in a CI job.
                previous = Path.cwd()
                try:
                    os.chdir(root)
                    packager.appimage(bundle, "26.4.6+26406")
                finally:
                    os.chdir(previous)
            self.assertTrue((root / "build/dist/26.4.6+26406/"
                             "simple_live_app-26.4.6+26406-linux.AppImage").is_file())


if __name__ == "__main__":
    unittest.main()
