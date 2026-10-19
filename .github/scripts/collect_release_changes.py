"""Collect product-scoped Git evidence for release notes, without external packages."""

import json
import re
import subprocess
from pathlib import PurePosixPath


# Keep these aligned with the clients' path dependencies and overrides.
SHARED_ROOTS = (
    'simple_live_core/',
    'third_party/media_kit_video/',
    'third_party/canvas_danmaku/',
    'simple_live_app/third_party/flutter_inappwebview_android/',
)
PRODUCT_ROOTS = {
    'App': ('simple_live_app/', 'third_party/dart_quickjs_compat/') + SHARED_ROOTS,
    'TV': ('simple_live_tv_app/',) + SHARED_ROOTS,
}
MAINTENANCE_DIRS = {
    'test', 'tests', 'test_live', 'integration_test', 'test_driver',
    'doc', 'docs', 'example', 'examples', 'benchmark', 'benchmarks',
    'tool', 'tools', 'build', '.dart_tool', '.github', '.vscode', '.idea',
}
VERSION_FILES = {
    'simple_live_app/lib/generated/app_version.g.dart',
    'simple_live_app/lib/generated/app_update_channel.g.dart',
}
VERSION_FIELDS = {
    'pubspec.yaml': re.compile(r'version\s*:.*'),
    'app.json5': re.compile(r'"version(?:Code|Name)"\s*:.*'),
}
MAX_PATCH_CHARS = 4000
MAX_CONTEXT_CHARS = 100_000


def git(repo, *args):
    return subprocess.check_output(
        ['git', '-C', str(repo), '-c', 'core.quotePath=false', *args],
        encoding='utf-8', errors='replace',
    )


def previous_release_tag(repo, audience, tag, branch, prerelease):
    prefix = 'tv_v' if audience == 'TV' else 'v'
    suffix = '-dev' if branch == 'dev' else '-pre' if prerelease else ''
    pattern = re.compile(rf'{prefix}\d+\.\d+\.\d+{suffix}')
    # Only reachable tags can establish a baseline for this checkout.
    tags = git(repo, 'tag', '--merged', 'HEAD', '--sort=-v:refname',
               '--list', prefix + '[0-9]*').splitlines()
    return next((item for item in tags if item != tag and pattern.fullmatch(item)), None)


def is_product_path(path, audience):
    parts = PurePosixPath(path).parts
    if audience == 'TV' and path.startswith('third_party/media_kit_video/'):
        if len(parts) > 2 and parts[2] in {'ios', 'macos', 'linux'}:
            return False
    return (
        path.startswith(PRODUCT_ROOTS[audience])
        and not MAINTENANCE_DIRS.intersection(parts)
        and path not in VERSION_FILES
        and not path.lower().endswith(('.md', '.rst', '.lock', '_test.dart'))
        and PurePosixPath(path).name not in {
            'LICENSE', 'CHANGELOG', 'analysis_options.yaml', '.gitignore',
            '.metadata', '.fvmrc', '.flutter-plugins-dependencies', 'l10n.yaml',
        }
    )


def product_patch(repo, commit, path):
    patch = git(repo, 'show', '--format=', '--root', '--no-ext-diff',
                '--no-renames', '--unified=2', commit, '--', path)
    version_field = VERSION_FIELDS.get(PurePosixPath(path).name)
    if version_field:
        changes = [line[1:].strip() for line in patch.splitlines()
                   if line.startswith(('+', '-')) and not line.startswith(('+++', '---'))]
        # Version-only bumps do not describe a new user-facing capability.
        if all(not line or version_field.fullmatch(line) for line in changes):
            return ''
    return patch


def collect_changes(repo, audience, tag, branch='', prerelease=False):
    roots = PRODUCT_ROOTS[audience]
    previous = previous_release_tag(repo, audience, tag, branch, prerelease)
    revision = f'{previous}..HEAD' if previous else 'HEAD'
    # Apply limits AFTER product/maintenance filtering; unrelated history must
    # neither crowd out this client's changes nor trigger an older-history fallback.
    limit = 80 if previous else 30
    commits = git(repo, 'log', '--no-merges', '--format=%H', revision, '--', *roots)
    records = []
    context_chars = 0
    for commit in commits.splitlines():
        paths = git(repo, 'diff-tree', '--root', '--no-commit-id', '--name-only',
                    '--no-renames', '-r', '-z', commit, '--', *roots).split('\0')
        patches = []
        relevant_paths = []
        for path in paths:
            if not path or not is_product_path(path, audience):
                continue
            patch = product_patch(repo, commit, path)
            if patch:
                relevant_paths.append(path)
                patches.append(patch)
        if not relevant_paths:
            continue
        patch = '\n'.join(patches)
        record = {
            'commit': commit,
            'subject': git(repo, 'log', '-1', '--format=%s', commit).strip(),
            'files': relevant_paths,
            'patch': patch[:MAX_PATCH_CHARS],
            'patch_truncated': len(patch) > MAX_PATCH_CHARS,
        }
        encoded = json.dumps(record, ensure_ascii=False)
        if records and context_chars + len(encoded) > MAX_CONTEXT_CHARS:
            break
        records.append(record)
        context_chars += len(encoded)
        if len(records) >= limit:
            break
    # Empty input is intentionally distinct from a collection/API failure.
    return json.dumps(records, ensure_ascii=False, indent=2) if records else ''
