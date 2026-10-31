#!/data/data/com.termux/files/usr/bin/bash
# Regenerate the apt index files (Packages, Contents, Release) from pool/main.
#
# Layout produced:
#   dists/<arch>/main/binary/<arch>/Packages{,.gz,.xz}
#   dists/<arch>/main/binary/Packages{,.gz,.xz}     (legacy apt path)
#   dists/<arch>/main/Contents-<arch>{,.xz}
#   dists/<arch>/Release
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="aarch64"
SUITE="$ARCH"
COMPONENT="main"
POOL="${POOL_DIR:-pool/$COMPONENT}"
BASE="dists/$SUITE/$COMPONENT"
BIN_DIR="$BASE/binary-$ARCH"
LEGACY_BIN_DIR="$BASE/binary"

mkdir -p "$BIN_DIR" "$LEGACY_BIN_DIR"

packages_tmp="$(mktemp)"
contents_tmp="$(mktemp)"
trap 'rm -f "$packages_tmp" "$contents_tmp"' EXIT

{
	for deb in "$POOL"/*.deb; do
		[ -e "$deb" ] || continue
		rel="$deb"
		size="$(stat -c %s "$deb")"
		md5="$(md5sum "$deb" | awk '{print $1}')"
		sha1="$(sha1sum "$deb" | awk '{print $1}')"
		sha256="$(sha256sum "$deb" | awk '{print $1}')"
		sha512="$(sha512sum "$deb" | awk '{print $1}')"

		dpkg-deb -f "$deb"
		printf 'Filename: %s\n' "$rel"
		printf 'Size: %s\n' "$size"
		printf 'MD5Sum: %s\n' "$md5"
		printf 'SHA1: %s\n' "$sha1"
		printf 'SHA256: %s\n' "$sha256"
		printf 'SHA512: %s\n' "$sha512"
		printf '\n'
	done
} > "$packages_tmp"

# Contents-<arch>: "<path>\t<pkg>" for every payload file.
{
	for deb in "$POOL"/*.deb; do
		[ -e "$deb" ] || continue
		pkg="$(dpkg-deb -f "$deb" Package)"
		dpkg-deb -c "$deb" | awk -v pkg="$pkg" '
			$1 !~ /^d/ {
				path = $NF
				sub(/^\.\//, "", path)
				if (path != "") printf "%s\t%s\n", path, pkg
			}'
	done
} > "$contents_tmp"

write_indexes() {
	local dir="$1"
	cp "$packages_tmp" "$dir/Packages"
	gzip -9nc "$dir/Packages" > "$dir/Packages.gz"
	xz -9c "$dir/Packages" > "$dir/Packages.xz"
}

write_indexes "$BIN_DIR"
write_indexes "$LEGACY_BIN_DIR"

cp "$contents_tmp" "$BASE/Contents-$ARCH"
xz -9c "$BASE/Contents-$ARCH" > "$BASE/Contents-$ARCH.xz"
gzip -9nc "$BASE/Contents-$ARCH" > "$BASE/Contents-$ARCH.gz"

# Release checksums cover only the index files, relative to dists/<suite>/.
index_files=""
for rel in \
	"$COMPONENT/binary-$ARCH/Packages" \
	"$COMPONENT/binary-$ARCH/Packages.gz" \
	"$COMPONENT/binary-$ARCH/Packages.xz" \
	"$COMPONENT/binary/Packages" \
	"$COMPONENT/binary/Packages.gz" \
	"$COMPONENT/binary/Packages.xz" \
	"$COMPONENT/Contents-$ARCH" \
	"$COMPONENT/Contents-$ARCH.xz" \
	"$COMPONENT/Contents-$ARCH.gz"; do
	index_files="$index_files $rel"
done

emit_sums() {
	local tool="$1"
	for rel in $index_files; do
		[ -f "dists/$SUITE/$rel" ] || continue
		printf ' %s %s %s\n' \
			"$($tool "dists/$SUITE/$rel" | awk '{print $1}')" \
			"$(stat -c %s "dists/$SUITE/$rel")" \
			"$rel"
	done
}

{
	echo "Suite: $SUITE"
	echo "Codename: $SUITE"
	echo "Version: 1"
	echo "Architectures: $ARCH"
	echo "Components: $COMPONENT"
	echo "Description: NuxDroid $ARCH repository"
	echo "Date: $(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S UTC')"
	echo "MD5Sum:"
	emit_sums md5sum
	echo "SHA1:"
	emit_sums sha1sum
	echo "SHA256:"
	emit_sums sha256sum
	echo "SHA512:"
	emit_sums sha512sum
} > "dists/$SUITE/Release"

echo "index regenerated:"
ls -l "dists/$SUITE/Release" "$BIN_DIR"/Packages* "$LEGACY_BIN_DIR"/Packages*
