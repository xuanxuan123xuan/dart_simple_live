#!/usr/bin/env bash
set -euo pipefail

channel="${1:-}"
version="${2:-}"

case "$channel" in
  dev)
    source_branch="ipa-source"
    source_template="apps.json"
    source_file="apps.json"
    ios_tag="ios-dev"
    ;;
  stable)
    source_branch="ipa-stable"
    source_template="apps-stable.json"
    source_file="apps.json"
    ios_tag="ios-stable"
    ;;
  *)
    echo "usage: $0 <dev|stable> <version>" >&2
    exit 2
    ;;
esac

if [[ -z "$version" ]]; then
  echo "IPA source version must not be empty" >&2
  exit 2
fi

source_worktree="${RUNNER_TEMP:?}/${source_branch}-worktree"
template_dir="${GITHUB_WORKSPACE:?}/ipa-source"
repository="${GITHUB_REPOSITORY:?}"

rm -rf "$source_worktree"
git worktree prune

cleanup() {
  git worktree remove --force "$source_worktree" >/dev/null 2>&1 || true
}
trap cleanup EXIT

if git ls-remote --exit-code --heads origin "refs/heads/$source_branch" >/dev/null 2>&1; then
  git fetch origin "refs/heads/$source_branch:refs/remotes/origin/$source_branch"
  git worktree add --detach "$source_worktree" "refs/remotes/origin/$source_branch"
else
  git worktree add --detach "$source_worktree" HEAD
  git -C "$source_worktree" switch --orphan "$source_branch"
  git -C "$source_worktree" rm -rf . >/dev/null 2>&1 || true
fi

if [[ ! -f "$source_worktree/$source_file" ]]; then
  cp "$template_dir/$source_template" "$source_worktree/$source_file"
fi
if [[ ! -f "$source_worktree/icon.png" ]]; then
  cp "$template_dir/icon.png" "$source_worktree/icon.png"
fi

if [[ ! -f "$source_worktree/$source_file" ]]; then
  echo "Missing IPA source file: $source_branch/$source_file" >&2
  exit 1
fi

node - "$source_worktree/$source_file" "$version" "$repository" "$source_branch" "$source_file" "$ios_tag" <<'JS'
const fs = require('fs');

const [path, version, repository, sourceBranch, sourceFile, iosTag] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(path, 'utf8'));
data.sourceURL =
  `https://raw.githubusercontent.com/${repository}/${sourceBranch}/${sourceFile}`;

const app = data.apps[0];
app.version = version;
app.versionDate = new Date().toISOString().slice(0, 10);
app.downloadURL =
  `https://github.com/${repository}/releases/download/${iosTag}/simple-live.ipa`;
app.iconURL =
  `https://raw.githubusercontent.com/${repository}/${sourceBranch}/icon.png`;

fs.writeFileSync(path, `${JSON.stringify(data, null, 2)}\n`, 'utf8');
JS

git -C "$source_worktree" add --all
git -C "$source_worktree" \
  -c user.name="github-actions[bot]" \
  -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -m "chore: update $channel IPA source to $version" || {
    echo "IPA source already points to $channel $version"
    exit 0
  }

# 同一通道的两个发布可能同时结束；rebase 后重试，避免后完成者推送失败。
for attempt in 1 2 3; do
  if git -C "$source_worktree" push origin "HEAD:refs/heads/$source_branch"; then
    echo "IPA source updated: $source_branch/$source_file -> $version"
    exit 0
  fi
  if [[ "$attempt" -eq 3 ]]; then
    break
  fi
  git -C "$source_worktree" fetch origin \
    "refs/heads/$source_branch:refs/remotes/origin/$source_branch"
  git -C "$source_worktree" rebase "origin/$source_branch"
done

echo "Failed to push IPA source branch after 3 attempts" >&2
exit 1
