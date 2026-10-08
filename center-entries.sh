#!/usr/bin/env bash
# Companion script for the systemd-boot GRUB theme. Run it with sudo
# instead of grub-mkconfig. It:
#   0. regenerates grub.cfg with grub-mkconfig (skip with --no-mkconfig),
#   1. optionally removes "Advanced options" submenus and the
#      "Loading Linux ..." / "Loading initial ramdisk ..." messages,
#   2. centres menu titles by padding them with leading spaces,
#   3. sizes the menu box in theme.txt the way systemd-boot does: as wide as
#      the longest title (plus 3 characters each side), as tall as the number
#      of entries, with the separator and countdown snug underneath.
# Safe to run repeatedly.
set -euo pipefail

MKCONFIG=yes
if [[ ${1:-} == --no-mkconfig ]]; then MKCONFIG=no; shift; fi
CFG="${1:-/boot/grub/grub.cfg}"
THEME="${2:-/boot/grub/themes/systemd-boot/theme.txt}"
HIDE_ADVANCED=yes  # set to "no" to keep the "Advanced options" submenu
HIDE_LOADING=yes   # set to "no" to keep the "Loading ..." messages
MAX_ROWS=12        # beyond this many entries the menu scrolls instead

ROW=19             # item_height in theme.txt
LINE_GAP=9         # px between the last entry and the separator line
COUNTDOWN_GAP=10   # px between the separator line and the "Boot in" text box
GLYPH=8            # menu font glyph width in px
BAR_PAD=6          # characters added to the longest title for the highlight bar
LINE_PAD=6         # characters the separator extends beyond the highlight bar
MAX_COLS=80        # widest the highlight bar may get, in characters
MENU_EXTRA=2       # px GRUB trims off the right of the highlight; added back to match

# --- Step 0: regenerate grub.cfg -----------------------------------------
for f in "$CFG" "$THEME"; do
  if [[ -e $f && ! -w $f ]] || [[ ! -e $f && ! -w $(dirname "$f") ]]; then
    echo "Can't write to $f, please run with sudo." >&2; exit 1
  fi
done
[[ -f $THEME ]] || { echo "Theme not found at $THEME" >&2; exit 1; }
if [[ $MKCONFIG == yes ]]; then
  grub-mkconfig -o "$CFG"
fi

# "UEFI Firmware Settings" only appears at boot if the firmware supports it
FW_OK=no
efivar=/sys/firmware/efi/efivars/OsIndicationsSupported-8be4df61-93ca-11d2-aa0d-00e098032b8c
if [[ -r $efivar ]] && (( $(od -An -t u1 -j4 -N1 "$efivar") & 1 )); then FW_OK=yes; fi

# --- Step 1 + 2: rewrite grub.cfg ----------------------------------------
# The same awk program runs twice: first to measure (entry count and longest
# visible title), then to write the cleaned-up, centred config.
# shellcheck disable=SC2016
AWKPROG='
  function braces(s,   o, c) { o = gsub(/{/, "{", s); c = gsub(/}/, "}", s); return o - c }
  skipping { sdepth += braces($0); if (sdepth <= 0) skipping = 0; next }
  depth == 0 && hide == "yes" && /^[ \t]*submenu / {
    sdepth = braces($0); if (sdepth > 0) skipping = 1; next
  }
  # The "Loading ..." messages are plain echo lines inside menu entries
  hideload == "yes" && depth > 0 && /^[ \t]*echo[ \t]+\x27/ { depth += braces($0); next }
  {
    line = $0
    if (match(line, /^[ \t]*(menuentry|submenu) \x27[^\x27]*\x27/)) {
      pre = line; sub(/\x27.*/, "", pre)
      rest = substr(line, length(pre) + 2)
      title = rest; sub(/\x27.*/, "", title)
      tail = substr(rest, length(title) + 2)
      sub(/^ +/, "", title)
      if (depth == 0 && !(line ~ /uefi-firmware/ && fw != "yes")) {
        n++; if (length(title) > maxlen) maxlen = length(title)
      }
      pad = int((w - length(title)) / 2); if (pad < 0) pad = 0
      line = sprintf("%s\x27%*s%s\x27%s", pre, pad, "", title, tail)
    }
    depth += braces($0)
    print line
  }
  END { print n + 0, maxlen + 0 > cf }
'
countfile="$(mktemp)"
awk -v w=0 -v hide="$HIDE_ADVANCED" -v fw="$FW_OK" -v hideload="$HIDE_LOADING" \
    -v cf="$countfile" "$AWKPROG" "$CFG" > /dev/null
read -r count maxlen < "$countfile"; rm -f "$countfile"

cols=$(( maxlen + BAR_PAD ))
(( cols > MAX_COLS )) && cols=$MAX_COLS

tmp="$CFG.tmp"
awk -v w="$cols" -v hide="$HIDE_ADVANCED" -v fw="$FW_OK" -v hideload="$HIDE_LOADING" \
    -v cf=/dev/null "$AWKPROG" "$CFG" > "$tmp"
mv "$tmp" "$CFG"

# --- Step 3: resize the menu box and move the separator + countdown -------
rows=$count
(( rows < 1 )) && rows=1
(( rows > MAX_ROWS )) && rows=$MAX_ROWS

tmp="$THEME.tmp"
awk -v rows="$rows" -v row="$ROW" -v lg="$LINE_GAP" -v cg="$COUNTDOWN_GAP" \
    -v cols="$cols" -v lcols=$(( cols + LINE_PAD )) -v glyph="$GLYPH" -v extra="$MENU_EXTRA" '
  function off(v) { return (v >= 0 ? "+" v : v) }
  /^[ \t]*\+[ \t]*[a-z_]+/ { comp = $0; sub(/^[ \t]*\+[ \t]*/, "", comp); sub(/[ \t{].*/, "", comp)
                             n = 0; inblk = 1 }
  inblk { buf[++n] = $0
          if ($0 ~ /^[ \t]*}[ \t]*$/) { flush(); inblk = 0 }
          next }
  { print }
  function flush(   i, istimeout) {
    istimeout = 0
    for (i = 1; i <= n; i++) if (buf[i] ~ /__timeout__/) istimeout = 1
    for (i = 1; i <= n; i++) {
      l = buf[i]
      if (comp == "boot_menu" && l ~ /^[ \t]*top *=/)    sub(/=.*/, "= 50%" off(menutop), l)
      if (comp == "boot_menu" && l ~ /^[ \t]*height *=/) sub(/=.*/, "= " rows * row, l)
      # Widths snap to the character grid like systemd-boot (odd widths lean left)
      if (comp == "boot_menu" && l ~ /^[ \t]*left *=/)   sub(/=.*/, "= 50%" off(-glyph * int((cols + 1) / 2)), l)
      if (comp == "boot_menu" && l ~ /^[ \t]*width *=/)  sub(/=.*/, "= " glyph * cols + extra, l)
      if (comp == "image" && l ~ /^[ \t]*left *=/)       sub(/=.*/, "= 50%" off(-glyph * int((lcols + 1) / 2)), l)
      if (comp == "image" && l ~ /^[ \t]*width *=/)      sub(/=.*/, "= " glyph * lcols, l)
      if (comp == "image" && l ~ /^[ \t]*top *=/)       sub(/=.*/, "= 50%" off(menutop + rows * row + lg), l)
      if (comp == "label" && istimeout && l ~ /^[ \t]*top *=/) sub(/=.*/, "= 50%" off(menutop + rows * row + lg + cg), l)
      print l
    }
  }
  # Like systemd-boot: entries are centred on screen in whole text rows
  BEGIN { menutop = -row * int((rows + 1) / 2) }
' "$THEME" > "$tmp"
mv "$tmp" "$THEME"

msg="$count menu entr$([[ $count == 1 ]] && echo y || echo ies), $cols characters wide"
(( count > MAX_ROWS )) && msg+=" (showing $MAX_ROWS, the rest scroll)"
echo "Centred titles in $CFG and sized the menu in $THEME for $msg."
