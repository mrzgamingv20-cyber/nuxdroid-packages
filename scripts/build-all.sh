#!/data/data/com.termux/files/usr/bin/bash
# Rebuild every package under src/ into pool/ and regenerate the apt index.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

for src in src/*/; do
	name="$(basename "$src")"
	version="$(awk -F': ' '/^Version:/ {print $2}' "$src/control")"
	arch="$(awk -F': ' '/^Architecture:/ {print $2}' "$src/control")"
	out="pool/main/${name}_${version}_${arch}.deb"
	./scripts/make-deb.sh "$src" "$out"
done

# Drop stale copies outside pool/ (old layout kept duplicated .deb files).
find . -path ./.git -prune -o -name '*.deb' -print |
	while IFS= read -r f; do
		case "$f" in
			./pool/main/*) ;;
			*) echo "removing stale $f"; rm -f "$f" ;;
		esac
	done

./scripts/update-index.sh
