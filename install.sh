#!/usr/bin/env bash
# Installs the systemd-boot look-alike GRUB theme (Arch Linux paths).
# Safe to run again later, e.g. to update to a newer version of the theme.
set -euo pipefail
[[ $EUID -eq 0 || -n ${ROOT:-} ]] || { echo "Please run with sudo."; exit 1; }

ROOT="${ROOT:-}"                       # only used for testing
DEST="$ROOT/boot/grub/themes/systemd-boot"
CFG="$ROOT/boot/grub/grub.cfg"
DEFAULTS="$ROOT/etc/default/grub"
BIN="$ROOT/usr/local/bin/grub-mkconfig-sdboot"
SRC="$(cd "$(dirname "$0")" && pwd)"

# Already installed? (theme is set in /etc/default/grub)
FIRST_INSTALL=yes
grep -qE "^GRUB_THEME=\"?${DEST#$ROOT}/theme.txt\"?" "$DEFAULTS" && FIRST_INSTALL=no

# --- Theme files -----------------------------------------------------------
mkdir -p "$DEST"
if [[ $SRC != "$DEST" ]]; then
  if [[ -f $DEST/theme.txt ]]; then
    cp "$DEST/theme.txt" "$DEST/theme.txt.bak"
    echo "Saved your current theme.txt as theme.txt.bak"
  fi
  cp "$SRC"/theme.txt "$SRC"/*.png "$SRC"/*.pf2 "$SRC"/LICENSE-efi-font.txt "$DEST"/
fi
# GRUB loads every .pf2 in the theme folder. Unifont is kept as a fallback for
# characters the firmware font doesn't have (and for GRUB's editor/console).
cp "$ROOT/usr/share/grub/unicode.pf2" "$DEST"/

# --- /etc/default/grub -----------------------------------------------------
# Back up only once, so the backup always holds your original config.
if [[ ! -e $DEFAULTS.bak ]]; then
  cp "$DEFAULTS" "$DEFAULTS.bak"
  echo "Backed up your original config to $DEFAULTS.bak"
fi

set_opt() {
  if grep -qE "^#?\s*$1=" "$DEFAULTS"; then
    sed -i -E "s|^#?\s*$1=.*|$1=\"$2\"|" "$DEFAULTS"
  else
    echo "$1=\"$2\"" >> "$DEFAULTS"
  fi
}
# The only two settings the theme needs; everything else is left as you have it
set_opt GRUB_THEME "${DEST#$ROOT}/theme.txt"
set_opt GRUB_TERMINAL_OUTPUT "gfxterm"   # themes only load in graphical mode

# --- Helper script + regenerate ------------------------------------------
mkdir -p "$(dirname "$BIN")"
cp "$SRC"/center-entries.sh "$BIN"
chmod +x "$BIN"
"$BIN" "$CFG" "$DEST/theme.txt"   # runs grub-mkconfig, then centres and resizes

if [[ $FIRST_INSTALL == yes ]]; then
  echo "Installed! From now on, use: sudo grub-mkconfig-sdboot"
else
  echo "Updated!"
fi
