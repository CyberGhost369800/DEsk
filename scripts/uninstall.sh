#!/bin/sh
# uninstall.sh -- DEsk taken off this machine again: what its installer put
# in, and nothing of yours.
#
# Run it as yourself from the folder you installed DEsk from; it asks for
# sudo when it needs to. It removes DEsk's programs and files (what the
# install put in, as build-install/meson-logs/install-log.txt has them),
# "DEsk" from the login screen, the machine's DEsk settings (/etc/xdg/desk),
# and the wlroots the installer built for DEsk (/opt/desk-wlroots), if there
# is one.
#
# It leaves the packages the installer brought from your distribution
# (other programs may use them; your package manager removes them), and
# what is yours in your home folder -- DEsk's settings, notes and memos --
# which it names at the end, for you to remove if you want.
#
#   --yes            do not ask
#   --keep-wlroots   leave /opt/desk-wlroots
#   --help           this
#
# Log out of DEsk first, and run it from another desktop or a text console.
# The build directory is build-install in the source folder (BUILD_DIR=...
# for another).
set -eu

yes=0 wlroots=1
while [ $# -gt 0 ]; do
	case "$1" in
	--yes|-y) yes=1 ;;
	--keep-wlroots) wlroots=0 ;;
	-h|--help) sed -n '2,/^set /s/^# \{0,1\}//p' "$0"; exit 0 ;;
	*) echo "uninstall.sh: what is $1? (--help says what it takes)" >&2; exit 2 ;;
	esac
	shift
done

root="$(cd "$(dirname "$0")/.." && pwd)"
build="${BUILD_DIR:-$root/build-install}"
record="$build/meson-logs/install-log.txt"

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
die() { printf 'uninstall.sh: %s\n' "$*" >&2; exit 1; }

if ! grep -q "^project('desk'" "$root/meson.build" 2>/dev/null; then
	die "$root does not look like DEsk's source folder (no meson.build for it)"
fi
[ -f "$record" ] || die "there is no record of an install from this folder ($record): run it from the folder you installed DEsk from"
# (sudo leaves XDG_CURRENT_DESKTOP behind, so the desk itself is looked for)
case "${XDG_CURRENT_DESKTOP:-}" in
*DEsk*) die "this is DEsk you are in: log out, and run it from another desktop or a text console" ;;
esac
if command -v pgrep >/dev/null 2>&1 && pgrep -x desk >/dev/null 2>&1; then
	die "DEsk is running (someone is in it, or it is open in a window): log out of it or close it first"
fi
if [ "$yes" -eq 0 ] && [ ! -t 0 ]; then
	die "there is nobody to answer its question here; run it with --yes"
fi

if [ "$(id -u)" -eq 0 ]; then
	as_root() { "$@"; }
else
	command -v sudo >/dev/null 2>&1 \
		|| die "removing needs root: run this as root, or install sudo and add yourself to it"
	as_root() { sudo "$@"; }
fi
ask() {
	# ask "question" -- no unless the answer is yes; --yes answers for us
	[ "$yes" -eq 1 ] && return 0
	printf '%s [y/N] ' "$1"
	read -r answer || answer=n
	case "$answer" in
	y|Y|yes|Yes) return 0 ;;
	*) return 1 ;;
	esac
}

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# What the install put in, still there: the files the record names, its
# comments off (a folder it names, as Meson does one it made, is left to
# go when it is empty)
grep -v '^#' "$record" | while IFS= read -r f; do
	if [ -L "$f" ] || [ -f "$f" ]; then
		printf '%s\n' "$f"
	fi
done > "$tmp/files"
# where it went: the folder above the bin/desk it put in
prefix=$(grep -v '^#' "$record" | sed -n 's|/bin/desk$||p' | head -n 1)
[ -n "$prefix" ] || prefix=/usr/local
data="$prefix/share"

# What the installer put beside it, outside that record
extra=""
sessions=/usr/share/wayland-sessions/desk.desktop
if [ -f "$sessions" ] && grep -qx "Exec=$prefix/bin/desk-session" "$sessions"; then
	extra="$extra $sessions"
fi
case "$prefix" in
/usr|/usr/local) ;;
*) if [ -f /usr/share/xdg-desktop-portal/desk-portals.conf ]; then
		extra="$extra /usr/share/xdg-desktop-portal/desk-portals.conf"
	fi ;;
esac
if [ -d /etc/xdg/desk ]; then
	extra="$extra /etc/xdg/desk"
fi
wlr=""
if [ "$wlroots" -eq 1 ] && [ -f /opt/desk-wlroots/share/desk-wlroots/built ]; then
	wlr=/opt/desk-wlroots
fi

n=$(wc -l < "$tmp/files")
if [ "$n" -eq 0 ] && [ -z "$extra" ] && [ -z "$wlr" ]; then
	say "DEsk is not installed from here: there is nothing of it left to remove."
	exit 0
fi
step "What goes"
if [ "$n" -gt 0 ]; then
	say "  DEsk's programs and files under $prefix and /etc ($n, as the install recorded them)"
fi
for f in $extra; do
	case "$f" in
	"$sessions") say "  $f (\"DEsk\" on the login screen)" ;;
	/etc/xdg/desk) say "  $f (DEsk's settings for every user of the machine)" ;;
	*) say "  $f" ;;
	esac
done
if [ -n "$wlr" ]; then
	say "  $wlr (the wlroots the installer built for DEsk; --keep-wlroots leaves it)"
fi
say ""
say "Left as they are: the packages the installer brought (your package manager"
say "removes them), and everything of yours in your home folder."
ask "Remove DEsk?" || { say "Nothing removed."; exit 0; }

step "Removing"
while IFS= read -r f; do
	as_root rm -f -- "$f"
done < "$tmp/files"
# made by the install itself, not in the record: the icon theme's cache
as_root rm -f -- "$data/icons/DEsk/icon-theme.cache"
# and DEsk's own folders, now empty -- only those, and only if empty
for d in "$data/icons/DEsk" "$data/themes/DEsk" "$data/desk"; do
	if [ -d "$d" ]; then
		as_root find "$d" -depth -type d -empty -delete 2>/dev/null || true
	fi
done
for d in "$data/xdg-desktop-portal" "$data/wayland-sessions" /etc/xdg/xdg-desktop-portal-wlr; do
	if [ -d "$d" ]; then
		as_root rmdir -- "$d" 2>/dev/null || true
	fi
done
for f in $extra; do
	as_root rm -rf -- "$f"
done
if [ -n "$wlr" ]; then
	as_root rm -rf -- "$wlr"
fi
# caches that had heard of DEsk's icons and programs hear they are gone
on_path() { command -v "$1" >/dev/null 2>&1; }
if [ -f "$data/icons/hicolor/icon-theme.cache" ] && on_path gtk-update-icon-cache; then
	as_root gtk-update-icon-cache -q -f "$data/icons/hicolor" || true
fi
if [ -f "$data/applications/mimeinfo.cache" ] && on_path update-desktop-database; then
	as_root update-desktop-database -q "$data/applications" || true
fi

left=$(while IFS= read -r f; do
	if [ -L "$f" ] || [ -e "$f" ]; then
		printf '%s\n' "$f"
	fi
done < "$tmp/files")
[ -z "$left" ] || { printf '%s\n' "$left" | sed 's/^/  /' >&2; die "these could not be removed"; }
say "DEsk is removed, and gone from the login screen."
say ""
say "What is yours is still there. To remove it too:"
say "  rm -rf ~/.config/desk ~/.local/share/desk ~/.local/state/desk ~/.cache/desk"
say "and this folder, $root, when you no longer want it."
