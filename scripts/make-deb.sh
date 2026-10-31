#!/data/data/com.termux/files/usr/bin/bash
# Build a NuxDroid .deb whose payload lives under the com.nuxdroid prefix.
#
# Official Termux packages ship paths under /data/data/com.termux, which dpkg
# inside NuxDroid cannot write to (Permission denied). Every NuxDroid package
# must therefore stage its payload under:
#   data/data/com.nuxdroid/files/usr/...
#
# usage: make-deb.sh <src-package-dir> <output.deb>
#
# <src-package-dir> layout:
#   control        required, dpkg control file
#   files/         payload, paths relative to $PREFIX (e.g. files/bin/foo)
#   dirs           optional, dirs to create under $PREFIX (one per line)
#   preinst|postinst|prerm|postrm   optional maintainer scripts
set -euo pipefail

if [ "$#" -ne 2 ]; then
	echo "usage: $0 <src-package-dir> <output.deb>" >&2
	exit 1
fi

SRC="$1"
OUT="$2"
PREFIX_REL="data/data/com.nuxdroid/files/usr"

[ -f "$SRC/control" ] || { echo "error: missing $SRC/control" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
chmod 0755 "$work"

mkdir -p "$work/DEBIAN" "$work/$PREFIX_REL"
chmod 0755 "$work/DEBIAN"
cp "$SRC/control" "$work/DEBIAN/control"
chmod 0644 "$work/DEBIAN/control"

if [ -d "$SRC/files" ]; then
	cp -a "$SRC/files"/. "$work/$PREFIX_REL/"
fi

if [ -f "$SRC/dirs" ]; then
	while IFS= read -r d; do
		[ -n "$d" ] || continue
		mkdir -p "$work/$PREFIX_REL/$d"
	done < "$SRC/dirs"
fi

for script in preinst postinst prerm postrm; do
	if [ -f "$SRC/$script" ]; then
		cp "$SRC/$script" "$work/DEBIAN/$script"
		chmod 0755 "$work/DEBIAN/$script"
		# Maintainer scripts are exec'd by dpkg, so their shebang must be a
		# path that exists inside the NuxDroid prefix.
		if head -1 "$work/DEBIAN/$script" | grep -q '^#!'; then
			if head -1 "$work/DEBIAN/$script" | grep -q '/data/data/com\.termux'; then
				echo "error: $script shebang references the com.termux prefix" >&2
				exit 1
			fi
		fi
	fi
done

installed_size="$(du -sk "$work/$PREFIX_REL" | awk '{print $1}')"
grep -v '^Installed-Size:' "$work/DEBIAN/control" > "$work/DEBIAN/control.new"
printf 'Installed-Size: %s\n' "$installed_size" >> "$work/DEBIAN/control.new"
mv "$work/DEBIAN/control.new" "$work/DEBIAN/control"
chmod 0644 "$work/DEBIAN/control"

mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# --root-owner-group keeps the payload owned by root/root exactly like official
# Termux packages; dpkg skips ownership restoration when running as a normal
# app user, but an unexpected owner (e.g. the builder uid) would be rejected.
dpkg-deb -b --root-owner-group -Zxz "$work" "$OUT"

# Hard guard: the payload must never reference another app's private prefix.
if dpkg-deb -c "$OUT" | grep -q 'data/data/com\.termux'; then
	echo "error: $OUT contains data/data/com.termux paths" >&2
	rm -f "$OUT"
	exit 1
fi

# Hard guard: payload ownership must be root/root.
if dpkg-deb -c "$OUT" | awk '$1 ~ /^[-dl]/ {print $2}' | grep -qv '^root/root$'; then
	echo "error: $OUT contains entries not owned by root/root" >&2
	rm -f "$OUT"
	exit 1
fi

echo "built $OUT"
dpkg-deb -c "$OUT"
