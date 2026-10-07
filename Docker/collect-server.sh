#!/bin/bash
# What simplenotes-server needs at run time, copied into a root of its own at
# the paths it was built with, for an image FROM scratch
# (Docker/server.Dockerfile):
#
#   * the executable and its model, in /app;
#   * every library ldd finds for it, and for the SQL stores it loads by
#     name (FreeCoreData's PostgreSQL and MySQL ones, -StoreType);
#   * FreeCoreData's framework bundle, which gnustep-base looks for;
#   * glibc's UTF-16 and UTF-32 converters (gnustep-base's strings use them
#     through iconv: a character past 16 bits, an emoji, needs them);
#   * gnustep-base's resources, the UTC time zone, and a user to run as.
#
# Debug information is stripped, symbol tables kept: Objective-C methods are
# named only there, and a crash's backtrace is worth them.
#
#   Docker/collect-server.sh /rootfs   (in the build stage, from the source)
set -euo pipefail

root=${1:?the root to fill}
set +u
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
set -u
export LD_LIBRARY_PATH="/opt/gnustep/lib:${LD_LIBRARY_PATH:-}"

mkdir -p "$root/app" "$root/data" "$root/tmp" "$root/etc"
chmod 1777 "$root/tmp"
cp Examples/SimpleNotes/obj/simplenotes-server "$root/app/"
cp -R Examples/SimpleNotes/obj/SimpleNotes.momd "$root/app/"

# A library and what it links: the stack's as they are (links into the
# framework bundles stay links), the system's resolved.
libraries_of() {
  ldd "$1" | awk '/=> \//{print $3} /^\t\/.*ld-linux/{print $1}'
}
copy_library() {
  case "$1" in
    /opt/gnustep/*) cp --parents -a "$1" "$root/"; cp --parents -a "$(readlink -f "$1")" "$root/" ;;
    *) cp --parents -L "$1" "$root/" ;;
  esac
}

stores=$(find /opt/gnustep -name 'libCD*Store.so' | sort)
[ -n "$stores" ] || { echo "no SQL stores (libCD*Store.so) in /opt/gnustep" >&2; exit 1; }
for f in "$root/app/simplenotes-server" $stores; do
  if [ "$f" != "$root/app/simplenotes-server" ]; then
    for link in "${f}"*; do copy_library "$link"; done
  fi
  for lib in $(libraries_of "$f"); do copy_library "$lib"; done
done
if ldd "$root/app/simplenotes-server" | grep -q 'not found'; then
  ldd "$root/app/simplenotes-server" >&2
  exit 1
fi

for fw in $(find /opt/gnustep -maxdepth 4 -name '*.framework' -type d); do
  cp --parents -a "$fw" "$root/"
  rm -rf "$root$fw/Headers" "$root$fw"/Versions/*/Headers
done

gconv=$(dirname "$(find /usr/lib -path '*gconv*' -name UTF-16.so | head -n 1)")
mkdir -p "$root$gconv"
cp -a "$gconv/gconv-modules" "$gconv/UTF-16.so" "$gconv/UTF-32.so" "$gconv/UNICODE.so" "$root$gconv/"
[ ! -d "$gconv/gconv-modules.d" ] || cp -a "$gconv/gconv-modules.d" "$root$gconv/"

base=$(find /opt/gnustep -path '*Libraries/gnustep-base' -type d | head -n 1)
[ -z "$base" ] || cp --parents -a "$base" "$root/"
[ ! -d /opt/gnustep/etc ] || cp --parents -a /opt/gnustep/etc "$root/"

mkdir -p "$root/usr/share/zoneinfo/Etc"
cp -a /usr/share/zoneinfo/UTC "$root/usr/share/zoneinfo/"
cp -a /usr/share/zoneinfo/Etc/UTC "$root/usr/share/zoneinfo/Etc/"
ln -sf /usr/share/zoneinfo/UTC "$root/etc/localtime"
echo 'notes:x:10001:10001:simplenotes:/data:/nonexistent' > "$root/etc/passwd"
echo 'notes:x:10001:' > "$root/etc/group"
chown 10001:10001 "$root/data"

find "$root" -type f \( -name '*.so*' -o -path '*/app/simplenotes-server' \) -exec strip --strip-debug {} \;
du -sh "$root"
