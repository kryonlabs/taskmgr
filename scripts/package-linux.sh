#!/bin/sh
# Linux packages for a Kryon desktop app: a Debian package and an AppImage.
#
#   scripts/package-linux.sh deb|appimage|all VERSION [OUTPUT]
#
# Run from the project root after the native build. The app is staged with
# `ziran install --prefix`, so the layout is Kryon's own: /usr/bin/BIN,
# /usr/share/kryon/BIN and a desktop entry. Libraries the build produced
# rather than the system (libkryonavif.so) move to /usr/lib/BIN, and the
# program's RUNPATH becomes $ORIGIN/../lib/BIN, so several Kryon apps install
# side by side without sharing a file.
#
# Output names carry no version, so a release's
#   /releases/latest/download/BIN-linux-amd64.deb
#   /releases/latest/download/BIN-linux-x86_64.AppImage
# always point at the newest build.
#
# Needs python3 and patchelf; deb also needs dpkg-deb and dpkg-shlibdeps;
# appimage needs LINUXDEPLOY, the path of a linuxdeploy AppImage, and an icon
# file in [tool.kryon.install] icon.
set -eu

usage() {
    echo "usage: package-linux.sh deb|appimage|all VERSION [OUTPUT]" >&2
    exit 64
}
[ $# -ge 2 ] || usage
format=$1
version=$2
output=${3:-dist}
case "$format" in deb|appimage|all) ;; *) usage ;; esac
case "$version" in ''|*[!0-9A-Za-z.+~-]*) echo "package-linux: invalid version '$version'" >&2; exit 64 ;; esac

ZIRAN=${ZIRAN:-./scripts/ziran.sh}
PATCHELF=${PATCHELF:-patchelf}
root=$(pwd)

# One shell assignment per line, values quoted for eval.
metadata=$(python3 -I - <<'PY'
import shlex, tomllib
with open("ziran.toml", "rb") as handle:
    project = tomllib.load(handle)
package = project.get("package", {})
install = project.get("install", {})
kryon = project.get("tool", {}).get("kryon", {}).get("install", {})
name = package.get("name", "")
values = {
    "bin": install.get("bin") or name,
    "display": kryon.get("name") or install.get("bin") or name,
    "comment": kryon.get("comment", ""),
    "icon_file": kryon.get("icon", ""),
}
for key, value in values.items():
    print(f"{key}={shlex.quote(str(value))}")
PY
)
eval "$metadata"
case "$bin" in ''|*[!0-9A-Za-z._-]*) echo "package-linux: invalid program name '$bin'" >&2; exit 65 ;; esac

mkdir -p "$output" build
output=$(CDPATH= cd -- "$output" && pwd)
stage=$(mktemp -d "$root/build/package.XXXXXX")
trap 'rm -rf "$stage"' EXIT INT TERM
prefix=$stage/root/usr

# Kryon's install also writes an autostart entry when asked; keep it inside
# the stage instead of the packager's own configuration. Ziran refuses
# --locked next to a ziran.local.toml override (as release CI uses).
lock_flag=--locked
[ ! -f ziran.local.toml ] || lock_flag=
# shellcheck disable=SC2086
XDG_CONFIG_HOME=$stage/config "$ZIRAN" install --prefix "$prefix" $lock_flag >/dev/null

program=$prefix/bin/$bin
[ -x "$program" ] || { echo "package-linux: $program was not installed" >&2; exit 66; }

# Libraries outside the system library directories came from the build.
private=$prefix/lib/$bin
mkdir -p "$private"
ldd "$program" | awk '$2 == "=>" && $3 ~ /^\// { print $3 }' | while read -r library; do
    case "$library" in
        /lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*) ;;
        *) cp -L "$library" "$private/" ;;
    esac
done
missing=$(ldd "$program" | awk '/not found/ { print $1 }')
[ -z "$missing" ] || { echo "package-linux: unresolved libraries: $missing" >&2; exit 67; }
"$PATCHELF" --set-rpath "\$ORIGIN/../lib/$bin" "$program"
for library in "$private"/*; do
    [ -f "$library" ] || continue
    chmod 644 "$library"
    "$PATCHELF" --set-rpath '$ORIGIN' "$library"
done
rmdir "$private" 2>/dev/null || true

# The desktop entry names the program and icon instead of the stage paths.
desktop=$prefix/share/applications/$bin.desktop
icon=""
if [ -n "$icon_file" ]; then
    icon=$(ls "$prefix/share/pixmaps/$bin".* 2>/dev/null | head -n 1)
fi
python3 -I - "$desktop" "$prefix" "$bin" <<'PY'
import sys
path, prefix, name = sys.argv[1:4]
lines = []
with open(path, encoding="utf-8") as handle:
    for line in handle.read().splitlines():
        if line.startswith("Exec="):
            line = "Exec=" + name
        elif line.startswith("Icon=") and line[5:].startswith(prefix):
            line = "Icon=" + name
        elif line.startswith("Path=") or line.startswith("X-Kryon-Installed="):
            continue
        lines.append(line)
with open(path, "w", encoding="utf-8") as handle:
    handle.write("\n".join(lines) + "\n")
PY

build_deb() {
    debroot=$stage/deb
    mkdir -p "$debroot/DEBIAN"
    cp -a "$stage/root/usr" "$debroot/usr"
    shlib=$stage/shlibdeps
    mkdir -p "$shlib/debian"
    printf 'Source: %s\n\nPackage: %s\nArchitecture: any\n' "$bin" "$bin" > "$shlib/debian/control"
    objects="$debroot/usr/bin/$bin"
    search=""
    if [ -d "$debroot/usr/lib/$bin" ]; then
        search="-l$debroot/usr/lib/$bin"
        for library in "$debroot/usr/lib/$bin"/*; do objects="$objects $library"; done
    fi
    # shellcheck disable=SC2086
    depends=$(cd "$shlib" && dpkg-shlibdeps -O $search $objects 2>/dev/null |
        sed -n 's/^shlibs:Depends=//p')
    size=$(du -sk "$debroot/usr" | cut -f1)
    {
        echo "Package: $bin"
        echo "Version: $version"
        echo "Architecture: amd64"
        echo "Maintainer: Kryon Labs <https://github.com/kryonlabs>"
        echo "Installed-Size: $size"
        [ -z "$depends" ] || echo "Depends: $depends"
        echo "Section: utils"
        echo "Priority: optional"
        echo "Homepage: https://github.com/kryonlabs/$bin"
        echo "Description: $display${comment:+ - $comment}"
        echo " $display, a Kryon desktop application."
    } > "$debroot/DEBIAN/control"
    find "$debroot" -type d -exec chmod 755 {} +
    dpkg-deb --root-owner-group --build "$debroot" "$output/$bin-linux-amd64.deb" >/dev/null
    echo "$output/$bin-linux-amd64.deb"
}

build_appimage() {
    : "${LINUXDEPLOY:?set LINUXDEPLOY to a linuxdeploy AppImage}"
    [ -n "$icon" ] || { echo "package-linux: an AppImage needs [tool.kryon.install] icon" >&2; exit 68; }
    appdir=$stage/AppDir
    mkdir -p "$appdir"
    cp -a "$stage/root/usr" "$appdir/usr"
    work=$stage/appimage
    mkdir -p "$work"
    target=$bin-linux-x86_64.AppImage
    (
        cd "$work"
        APPIMAGE_EXTRACT_AND_RUN=1 NO_STRIP=1 ARCH=x86_64 \
            LINUXDEPLOY_OUTPUT_VERSION="$version" LDAI_OUTPUT="$target" OUTPUT="$target" \
            "$LINUXDEPLOY" --appdir "$appdir" --executable "$appdir/usr/bin/$bin" \
            --desktop-file "$appdir/usr/share/applications/$bin.desktop" \
            --icon-file "$icon" --output appimage >"$stage/linuxdeploy.log" 2>&1 ||
            { tail -n 40 "$stage/linuxdeploy.log" >&2; exit 69; }
    )
    mv -f "$work/$target" "$output/$target"
    chmod 755 "$output/$target"
    echo "$output/$target"
}

case "$format" in
    deb) build_deb ;;
    appimage) build_appimage ;;
    all) build_deb; build_appimage ;;
esac
