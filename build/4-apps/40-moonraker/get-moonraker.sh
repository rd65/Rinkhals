#!/bin/sh

# Used by main Dockerfile

set -e

WORK=$(mktemp -d)
trap "rm -rf $WORK" EXIT
cd "$WORK"

FILES_DIR="${FILES_DIR:-/files}"

MOONRAKER_COMMIT=3c1f31874ac0beba35747059637583e5d2c383c0
MOONRAKER_DIRECTORY=$FILES_DIR/4-apps/home/rinkhals/apps/40-moonraker

echo "Downloading Moonraker..."
wget -O moonraker.zip https://github.com/Arksine/moonraker/archive/${MOONRAKER_COMMIT}.zip
unzip -d moonraker moonraker.zip

mkdir -p $MOONRAKER_DIRECTORY/moonraker
rm -rf $MOONRAKER_DIRECTORY/moonraker/*
cp -pr "$WORK"/moonraker/*/* $MOONRAKER_DIRECTORY/moonraker

# Apply Rinkhals spoolman compatibility fix directly in Moonraker source.
# See: https://github.com/utkabobr/DuckPro-Kobra3/issues/54#issuecomment-2540040852
SPOOLMAN_FILE="$MOONRAKER_DIRECTORY/moonraker/moonraker/components/spoolman.py"
if [ -f "$SPOOLMAN_FILE" ] && ! grep -q "SPOOL_ID: Union\[int, None\]" "$SPOOLMAN_FILE"; then
	perl -0pi -e 's/def set_active_spool\(self, spool_id: Union\[int, None\]\) -> None:\n        assert spool_id is None or isinstance\(spool_id, int\)/def set_active_spool(self, spool_id: Union[int, None] = None, SPOOL_ID: Union[int, None] = None) -> None:\n        if spool_id is None and SPOOL_ID is not None:\n            spool_id = int(str(SPOOL_ID).lstrip("="))\n        assert spool_id is None or isinstance(spool_id, int)/' "$SPOOLMAN_FILE"

	# Fail loudly rather than shipping an unpatched spoolman.py. The perl
	# substitution matches an exact two-line pattern, so a MOONRAKER_COMMIT bump
	# or any upstream reformatting would silently match nothing and exit 0 -
	# and the M555 SPOOL_ID handling this patch exists for would quietly
	# regress, to be discovered by a user rather than by the build.
	if ! grep -q "SPOOL_ID: Union\[int, None\]" "$SPOOLMAN_FILE"; then
		echo "ERROR: spoolman.py SPOOL_ID patch did not apply - did upstream Moonraker change set_active_spool?" >&2
		exit 1
	fi
fi

# GoKlipper sends some notifications with the remote method in
# template.method instead of the top-level method field expected by Moonraker.
# Normalize registered template methods so G-code responses reach clients.
KLIPPY_CONNECTION_FILE="$MOONRAKER_DIRECTORY/moonraker/moonraker/components/klippy_connection.py"
if [ -f "$KLIPPY_CONNECTION_FILE" ] && ! grep -q "GoKlipper compatibility" "$KLIPPY_CONNECTION_FILE"; then
	perl -0pi -e 's/        method = cmd\.get\('"'"'method'"'"', None\)\n        if method is not None:/        method = cmd.get('"'"'method'"'"', None)\n\n        # GoKlipper compatibility: some notifications put the remote method\n        # in template.method rather than the top-level method field.\n        if method is None:\n            template = cmd.get('"'"'template'"'"')\n            if isinstance(template, dict):\n                template_method = template.get('"'"'method'"'"')\n                params = cmd.get('"'"'params'"'"', {})\n                if (\n                    template_method in self.remote_methods and\n                    isinstance(params, dict)\n                ):\n                    self.event_loop.register_callback(\n                        self._execute_method, template_method, **params)\n                    return\n\n        if method is not None:/' "$KLIPPY_CONNECTION_FILE"

	if ! grep -q "GoKlipper compatibility" "$KLIPPY_CONNECTION_FILE"; then
		echo "ERROR: klippy_connection.py GoKlipper compatibility patch did not apply - did upstream Moonraker change _process_command?" >&2
		exit 1
	fi
fi

VERSION=$(echo $MOONRAKER_COMMIT | cut -c1-7)
sed -i "s/\"version\": *\"[^\"]*\"/\"version\": \"${VERSION}\"/" $MOONRAKER_DIRECTORY/app.json
