#!/usr/bin/env python3
"""Extract the text-emotion catalog cached by the official Android client."""

import argparse
import json
import sqlite3
from pathlib import Path


def _decode_emotions(raw: str | None) -> list[dict]:
    if not raw:
        return []
    return [json.loads(value) for value in raw.split(",,,") if value]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    source = Path(args.input).resolve()
    connection = sqlite3.connect(f"file:{source.as_posix()}?mode=ro", uri=True)
    try:
        integrity = connection.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise ValueError(f"SQLite integrity check failed: {integrity}")

        emotions: list[dict] = []
        rows = connection.execute(
            'SELECT "M_EMOTIONS" FROM "EMOTION_PACKAGE" ORDER BY rowid'
        )
        for (raw,) in rows:
            for emotion in _decode_emotions(raw):
                if emotion.get("bizType") != 1:
                    continue
                codes = [
                    group
                    for group in emotion.get("emotionCodes", [])
                    if group.get("language") == "zh_CN"
                ]
                if not any(group.get("codes") for group in codes):
                    continue
                item = dict(emotion)
                item["emotionCodes"] = codes
                emotions.append(item)
    finally:
        connection.close()

    if not emotions:
        raise ValueError("No zh_CN bizType=1 emotions found")

    output = {
        "result": 1,
        "emotionPackageList": [{"emotions": emotions}],
    }
    Path(args.output).write_text(
        json.dumps(output, ensure_ascii=False, separators=(",", ":")),
        encoding="utf-8",
    )
    print(f"Extracted {len(emotions)} Kuaishou mobile text emotions.")


if __name__ == "__main__":
    main()
