#!/bin/bash
#
# Installs (or removes) a launchd agent that runs reinstall-iphone.sh every day at
# 12:30. A run missed while the Mac sleeps happens at the next wake-up.
#
# Usage:
#   scripts/install-auto-reinstall.sh "iPhone de David"   # install / update
#   scripts/install-auto-reinstall.sh --uninstall         # remove

set -euo pipefail

LABEL="com.runmotion.reinstall"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/runmotion-reinstall.log"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/reinstall-iphone.sh"

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$PLIST"
    echo "Tâche supprimée."
    exit 0
fi

if [[ -z "${1:-}" ]]; then
    echo "Usage : $0 \"<nom de l'iPhone>\"   (voir : xcrun devicectl list devices)" >&2
    exit 1
fi
DEVICE="$1"
chmod +x "$SCRIPT"
mkdir -p "$(dirname "$PLIST")"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>/bin/bash</string>
		<string>$SCRIPT</string>
	</array>
	<key>EnvironmentVariables</key>
	<dict>
		<key>RUNMOTION_DEVICE</key>
		<string>$DEVICE</string>
	</dict>
	<key>StartCalendarInterval</key>
	<dict>
		<key>Hour</key>
		<integer>18</integer>
		<key>Minute</key>
		<integer>30</integer>
	</dict>
	<key>StandardOutPath</key>
	<string>$LOG</string>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "Tâche installée : vérification chaque jour à 18h30 pour « $DEVICE »."
echo "Journal : $LOG"
echo "Lancer une vérification maintenant : launchctl kickstart gui/$(id -u)/$LABEL"
