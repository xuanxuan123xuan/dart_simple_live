#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
native="$repo/simple_live_tvos_native"
vendor="$native/build/vendor"

prepare_package() {
  local name="$1" tag="$2" revision="$3" remote="$4"
  local destination="$vendor/$name"
  if [[ ! -e "$destination" ]]; then
    local staging
    staging="$(mktemp -d "$vendor/.$name.XXXXXX")"
    if ! git -c http.version=HTTP/1.1 clone --depth 1 --single-branch --branch "$tag" "$remote" "$staging" ||
       [[ "$(git -C "$staging" rev-parse HEAD)" != "$revision" ]]; then
      rm -rf -- "$staging"
      printf 'Could not prepare %s at %s\n' "$name" "$revision" >&2
      return 1
    fi
    mv -- "$staging" "$destination"
  fi
  if [[ "$(git -C "$destination" rev-parse HEAD)" != "$revision" ]]; then
    printf '%s has an unexpected revision. Move it out of %s and retry.\n' "$name" "$vendor" >&2
    return 1
  fi
}

mkdir -p "$vendor"
prepare_package KSPlayer 2.3.4 bdfa2da39bb18865b317c4ffd08cdef5f8efc043 https://github.com/kingslay/KSPlayer.git
prepare_package FFmpegKit 6.1.3 85b77c589de0360c111de16752db86b60496d70b https://github.com/kingslay/FFmpegKit.git

# Xcode rejects the underscore in the upstream embedded tvOS bundle identifier.
for slice in tvos-arm64_arm64e tvos-arm64_x86_64-simulator; do
  plist="$vendor/FFmpegKit/Sources/libshaderc_combined.xcframework/$slice/libshaderc_combined.framework/Info.plist"
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
  if [[ "$identifier" == com.kintan.ksplayer.libshaderc_combined ]]; then
    /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier com.kintan.ksplayer.libshaderc-combined' "$plist"
  elif [[ "$identifier" != com.kintan.ksplayer.libshaderc-combined ]]; then
    printf 'Unexpected libshaderc bundle identifier in %s\n' "$plist" >&2
    exit 1
  fi
done

"${XCODEGEN:-xcodegen}" generate --spec "$native/project.yml"
if [[ "$#" -eq 0 ]]; then
  set -- -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
fi
xcodebuild -project "$native/SimpleLiveTVOS.xcodeproj" -scheme SimpleLiveTVOS \
  -derivedDataPath "${TVOS_DERIVED_DATA:-$native/build/DerivedData}" "$@"
