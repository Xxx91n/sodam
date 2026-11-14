#!/bin/bash
# PROTOTYPE / THROWAWAY - issue #142. Tie the WSL binary back to the official
# release packages, and check the glibc requirement the user mentioned.
set +e
P=/mnt/c/Windows/Temp/sodam142-pkgs
EV=/mnt/c/sodam-142/prototype/142-middle-drag/evidence/linux
mkdir -p "$EV"
OUT="$EV/pkg_verify.log"
: > "$OUT"
log() { echo "$*" | tee -a "$OUT"; }

log "=== tools ==="
for t in tar zstd bsdtar ar readelf objdump ldd strings grep; do
  log "$t=$(command -v $t || echo MISSING)"
done
log "=== system glibc ==="
ldd --version | head -1 | tee -a "$OUT"
log "=== official sha256 (from Release SHA256SUMS) ==="
grep -E "x86_64.pkg.tar.zst" "$P/SHA256SUMS-038" | tee -a "$OUT"
grep -E "amd64.deb" "$P/SHA256SUMS-039" | tee -a "$OUT"
log "=== downloaded sha256 ==="
sha256sum "$P/sodam-0.3.8-1-x86_64.pkg.tar.zst" "$P/sodam_0.3.9_amd64.deb" | tee -a "$OUT"

log "=== unpack v0.3.8 Arch package ==="
rm -rf /tmp/p038; mkdir -p /tmp/p038
tar --zstd -xf "$P/sodam-0.3.8-1-x86_64.pkg.tar.zst" -C /tmp/p038 usr/bin/sodam 2>&1 | tee -a "$OUT"
log "tar_exit=$?"
log "--- compare: package binary vs what WSL is running ---"
sha256sum /tmp/p038/usr/bin/sodam /opt/s038/usr/bin/sodam /usr/bin/sodam 2>&1 | tee -a "$OUT"

log "=== unpack v0.3.9 deb ==="
rm -rf /tmp/p039; mkdir -p /tmp/p039
(cd /tmp/p039 && LANG=C ar x "$P/sodam_0.3.9_amd64.deb" && ls -la) 2>&1 | tee -a "$OUT"
log "ar_exit=$?"
for d in /tmp/p039/control.tar.* /tmp/p039/data.tar.*; do
  [ -f "$d" ] || continue
  case "$d" in
    *.zst) zstd -dc "$d" | tar -xf - -C /tmp/p039 2>>"$OUT" ;;
    *) tar -xf "$d" -C /tmp/p039 2>>"$OUT" ;;
  esac
  log "unpacked $d"
done
log "--- deb control Version ---"
grep -E "^(Package|Version|Architecture):" /tmp/p039/control 2>/dev/null | tee -a "$OUT"
log "--- binaries in deb ---"
find /tmp/p039 -type f -name 'sodam*' -size +1M 2>/dev/null | while read -r f; do
  log "$f  sha=$(sha256sum "$f" | cut -d' ' -f1)"
done

log "=== highest GLIBC symbol required (explains Ubuntu 24.04 failure) ==="
for f in /tmp/p038/usr/bin/sodam $(find /tmp/p039 -type f -name sodam -size +1M 2>/dev/null | head -1); do
  [ -f "$f" ] || continue
  log "-- $f --"
  grep -aoE 'GLIBC_2\.[0-9]+' "$f" | sort -Vu | tail -5 | tee -a "$OUT"
  ldd "$f" 2>&1 | grep -iE "not found|GLIBC" | head -10 | tee -a "$OUT"
done
log "=== done ==="
