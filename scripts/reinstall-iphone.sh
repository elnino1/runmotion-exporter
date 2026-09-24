#!/bin/bash
#
# Re-signs and reinstalls RunMotion Montre on the iPhone over Wi-Fi, so the free
# personal-team signature (valid 7 days) never lapses.
#
# Does nothing while the installed build still has more than REINSTALL_BEFORE_DAYS
# left, so it is safe to run daily (see install-auto-reinstall.sh). Pass --force
# to reinstall regardless.
#
# Configuration (environment variables):
#   RUNMOTION_DEVICE       iPhone name or identifier, as in `xcrun devicectl list devices` (required)
#   REINSTALL_BEFORE_DAYS  reinstall when fewer days than this remain (default 3)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$SCRIPT_DIR/../runmotion_exporter/runmotion_exporter.xcodeproj"
SCHEME="runmotion_exporter"
BUNDLE_ID="com.in.runmotion-exporter"
DEVICE="${RUNMOTION_DEVICE:?Set RUNMOTION_DEVICE to the iPhone name (see: xcrun devicectl list devices)}"
REINSTALL_BEFORE_DAYS="${REINSTALL_BEFORE_DAYS:-3}"

STATE_DIR="$HOME/Library/Application Support/runmotion-reinstall"
EXPIRATION_FILE="$STATE_DIR/expiration"
DERIVED_DATA="$HOME/Library/Caches/runmotion-reinstall/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug-iphoneos/runmotion_exporter.app"
PROFILE_DIRS=(
    "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
    "$HOME/Library/MobileDevice/Provisioning Profiles"
)

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*"; }

notify() {
    osascript -e "display notification \"$1\" with title \"RunMotion Montre\"" >/dev/null 2>&1 || true
}

fail() {
    log "ÉCHEC : $1"
    notify "Réinstallation impossible : $1"
    exit 1
}

profile_expiration_epoch() {
    local date
    date="$(security cms -D -i "$1" 2>/dev/null | plutil -extract ExpirationDate raw -o - -)" || return 1
    date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$date" +%s
}

# 1. Skip if the installed build is still valid long enough.
if [[ "${1:-}" != "--force" && -f "$EXPIRATION_FILE" ]]; then
    expiration="$(cat "$EXPIRATION_FILE")"
    remaining_days=$(( (expiration - $(date +%s)) / 86400 ))
    if (( remaining_days >= REINSTALL_BEFORE_DAYS )); then
        log "Signature encore valable $remaining_days jour(s), rien à faire."
        exit 0
    fi
    log "Signature valable encore $remaining_days jour(s) : réinstallation."
fi

# 2. Drop cached provisioning profiles for the app and its extension, so Xcode issues
#    fresh ones (7 full days) instead of reusing a profile that is about to expire.
for dir in "${PROFILE_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for profile in "$dir"/*.mobileprovision "$dir"/*.provisionprofile; do
        [[ -f "$profile" ]] || continue
        app_id="$(security cms -D -i "$profile" 2>/dev/null \
            | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null)" || continue
        if [[ "$app_id" == *".$BUNDLE_ID" || "$app_id" == *".$BUNDLE_ID".* ]]; then
            log "Suppression du profil en cache $app_id"
            rm -f "$profile"
        fi
    done
done

# 3. Build and sign.
log "Compilation…"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$DERIVED_DATA" \
    -allowProvisioningUpdates \
    -quiet \
    build || fail "la compilation a échoué (voir le journal)."

new_expiration="$(profile_expiration_epoch "$APP/embedded.mobileprovision")" \
    || fail "profil de signature introuvable dans l'app compilée."

# 4. Install over Wi-Fi.
log "Installation sur « $DEVICE »…"
xcrun devicectl device install app --device "$DEVICE" "$APP" \
    || fail "iPhone injoignable (même Wi-Fi que le Mac, déverrouillé ?). Nouvel essai demain."

mkdir -p "$STATE_DIR"
echo "$new_expiration" > "$EXPIRATION_FILE"
expires_on="$(date -r "$new_expiration" '+%d/%m à %H:%M')"
log "Réinstallée, valable jusqu'au $expires_on."
notify "App réinstallée, valable jusqu'au $expires_on."
