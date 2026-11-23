#!/bin/bash
# Build an opt-in distribution archive. Never submits, uploads, or notarizes.
set -euo pipefail
route="${1:-}"
archive_path="${2:-}"
if [[ "$route" != "developer-id" && "$route" != "mac-app-store" ]] || [[ -z "$archive_path" ]]; then
    echo 'Usage: ORALO_TEAM_ID=... ORALO_BUNDLE_ID=... archive_distribution.sh developer-id|mac-app-store /absolute/path/Oralo.xcarchive' >&2
    exit 2
fi
if [[ ! "${ORALO_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || [[ ! "${ORALO_BUNDLE_ID:-}" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]] || [[ "$ORALO_BUNDLE_ID" == "com.ch563.oralo.mac.dev" ]]; then
    echo 'Supply your signing team and an explicitly chosen distribution bundle ID. The local dev ID cannot be used.' >&2
    exit 2
fi
if [[ "$archive_path" != /* ]] || [[ -e "$archive_path" ]]; then
    echo 'Choose a new, absolute archive path; existing archives will not be overwritten.' >&2
    exit 2
fi
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
identity='Apple Development'
if [[ "$route" == "developer-id" ]]; then identity='Developer ID Application'; fi
xcodebuild -project "$project_root/OraloMac.xcodeproj" -scheme OraloMac \
    -configuration Release -destination 'generic/platform=macOS' \
    -xcconfig "$project_root/Configurations/Distribution.xcconfig" \
    -archivePath "$archive_path" \
    "ORALO_TEAM_ID=$ORALO_TEAM_ID" "ORALO_BUNDLE_ID=$ORALO_BUNDLE_ID" \
    "CODE_SIGN_IDENTITY=$identity" ONLY_ACTIVE_ARCH=NO archive
printf 'Archive created: %s\nNo export, upload, notarization, or submission was performed.\n' "$archive_path"
