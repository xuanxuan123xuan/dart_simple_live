#!/usr/bin/env python3
"""Generate the bundled Douyin Android small-emoji token map."""

import argparse
import json
from pathlib import Path


def is_supported_image(path: Path) -> bool:
    header = path.read_bytes()[:12]
    return header.startswith(b"\x89PNG\r\n\x1a\n") or (
        header.startswith(b"RIFF") and header[8:12] == b"WEBP"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--assets-dir", required=True)
    parser.add_argument("--client-version", required=True)
    parser.add_argument("--source", required=True)
    parser.add_argument("--generated-at", required=True)
    args = parser.parse_args()

    data = json.loads(Path(args.input).read_text(encoding="utf-8"))
    assets_dir = Path(args.assets_dir)
    assets: dict[str, str] = {}
    asset_files: set[str] = set()
    for sticker in data.get("stickers", []):
        token = str(sticker.get("display_name", "")).strip()
        uri = str(sticker.get("uri", "")).strip()
        if not (token.startswith("[") and token.endswith("]") and uri):
            continue
        if Path(uri).name != uri:
            raise ValueError(f"invalid asset filename for {token}: {uri}")
        asset_path = assets_dir / uri
        if not asset_path.is_file():
            raise ValueError(f"missing asset for {token}: {asset_path}")
        if not is_supported_image(asset_path):
            raise ValueError(f"invalid PNG/WebP asset for {token}: {asset_path}")
        if token in assets and assets[token] != uri:
            raise ValueError(f"conflicting URI for {token}")
        assets[token] = f"asset://assets/images/douyin_emoji/{uri}"
        asset_files.add(uri)

    if not assets:
        raise ValueError("no Douyin mobile emoji entries found")

    lines = [
        "// Generated. Do not edit by hand.",
        f"// Douyin Android client: {args.client_version}",
        f"// Source: {args.source}",
        f"// Generated at: {args.generated_at}",
        "library;",
        "",
        f'const String douyinMobileEmojiClientVersion = {json.dumps(args.client_version)};',
        f'const String douyinMobileEmojiSource = {json.dumps(args.source)};',
        f'const String douyinMobileEmojiGeneratedAt = {json.dumps(args.generated_at)};',
        f"const int douyinMobileEmojiAssetCount = {len(assets)};",
        f"const int douyinMobileEmojiFileCount = {len(asset_files)};",
        "",
        "const Map<String, String> douyinMobileEmojiAssets = {",
    ]
    for token, uri in assets.items():
        lines.append(f"  {json.dumps(token)}: {json.dumps(uri)},")
    lines.extend(["};", ""])
    Path(args.output).write_text("\n".join(lines), encoding="utf-8")
    print(
        f"Generated {len(assets)} Douyin mobile emoji entries "
        f"backed by {len(asset_files)} PNG/WebP files."
    )


if __name__ == "__main__":
    main()
