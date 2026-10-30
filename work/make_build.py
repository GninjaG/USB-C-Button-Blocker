#!/usr/bin/env python3
"""Assemble the self-contained build_usb_blocker.sh from work/module."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent
MOD = ROOT / "module"
OUT = ROOT.parent / "build_usb_blocker.sh"

FILES = [
    "module.prop",
    "customize.sh",
    "common.sh",
    "post-fs-data.sh",
    "service.sh",
    "hotplug.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]

HEADER = r'''#!/usr/bin/env sh
# build_usb_blocker.sh
# Gera o modulo KernelSU/Magisk "usb_c_button_blocker.zip" no diretorio atual.
#
# Uso:
#   sh build_usb_blocker.sh [caminho_de_saida.zip]
#
# Requisitos: sh POSIX e (zip OU python3). Em Termux:
#   pkg install zip        # opcional, se python nao estiver instalado
#
# O ZIP e montado com module.prop e META-INF na raiz, sem pasta externa.

set -eu
umask 022

OUT=${1:-"$PWD/usb_c_button_blocker.zip"}
case "$OUT" in
  /*) ;;
  *) OUT="$PWD/$OUT" ;;
esac

BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/usb_c_button_blocker.XXXXXX" 2>/dev/null || true)
if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR="${TMPDIR:-/tmp}/usb_c_button_blocker.$$"
  mkdir -p "$BUILD_DIR"
fi
case "$BUILD_DIR" in
  ''|'/'|'.') echo "ERRO: diretorio temporario invalido" >&2; exit 1 ;;
esac

cleanup() {
  [ -n "${BUILD_DIR:-}" ] && rm -rf "$BUILD_DIR"
}
trap cleanup 0 1 2 15

mkdir -p "$BUILD_DIR/META-INF/com/google/android"

printf '%s\n' "- Criando arquivos do modulo em $BUILD_DIR"
'''

FOOTER = r'''
# ---------------------------------------------------------------------------
# Permissoes: scripts executaveis, metadados legiveis.
# ---------------------------------------------------------------------------
chmod 0755 "$BUILD_DIR/customize.sh" \
           "$BUILD_DIR/common.sh" \
           "$BUILD_DIR/post-fs-data.sh" \
           "$BUILD_DIR/service.sh" \
           "$BUILD_DIR/hotplug.sh" \
           "$BUILD_DIR/META-INF/com/google/android/update-binary"
chmod 0644 "$BUILD_DIR/module.prop" \
           "$BUILD_DIR/META-INF/com/google/android/updater-script"

find_python() {
  if [ -n "${PYTHON_BIN:-}" ] && [ -x "${PYTHON_BIN:-}" ]; then
    printf '%s\n' "$PYTHON_BIN"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

PY=$(find_python || true)

# ---------------------------------------------------------------------------
# Empacotamento. O zip NAO pode conter a pasta externa.
# ---------------------------------------------------------------------------
rm -f "$OUT"

if [ -n "$PY" ]; then
  printf '%s\n' "- Empacotando com Python (modos Unix preservados)"
  "$PY" - "$BUILD_DIR" "$OUT" <<'PY_ZIP_EOF'
import os
import sys
import zipfile

stage, out = sys.argv[1], sys.argv[2]
files = [
    "module.prop",
    "customize.sh",
    "common.sh",
    "post-fs-data.sh",
    "service.sh",
    "hotplug.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for name in files:
        path = os.path.join(stage, *name.split("/"))
        if not os.path.isfile(path):
            raise SystemExit("arquivo ausente: " + path)
        zi = zipfile.ZipInfo.from_file(path, name)
        zi.create_system = 3
        mode = 0o755 if (name.endswith(".sh") or name.endswith("update-binary")) else 0o644
        zi.external_attr = (0o100000 | mode) << 16
        zi.compress_type = zipfile.ZIP_DEFLATED
        with open(path, "rb") as src, z.open(zi, "w") as dst:
            dst.write(src.read())
PY_ZIP_EOF
elif command -v zip >/dev/null 2>&1; then
  printf '%s\n' "- Empacotando com zip"
  ( cd "$BUILD_DIR" && zip -X -r "$OUT" META-INF module.prop customize.sh common.sh post-fs-data.sh service.sh hotplug.sh ) >/dev/null
else
  echo "ERRO: instale zip ou python3 (Termux: pkg install zip python)" >&2
  exit 1
fi

if [ ! -s "$OUT" ]; then
  echo "ERRO: o ZIP nao foi criado: $OUT" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Verificacao estrutural (sem depender de unzip).
# ---------------------------------------------------------------------------
if [ -n "$PY" ]; then
  "$PY" - "$OUT" <<'PY_CHECK_EOF'
import sys
import zipfile

required = [
    "module.prop",
    "customize.sh",
    "common.sh",
    "post-fs-data.sh",
    "service.sh",
    "hotplug.sh",
    "META-INF/com/google/android/update-binary",
    "META-INF/com/google/android/updater-script",
]
with zipfile.ZipFile(sys.argv[1]) as z:
    names = z.namelist()
    missing = [n for n in required if n not in names]
    wrapped = [n for n in names if n.startswith("./") or n.startswith("usb_c_button_blocker/")]
    if missing:
        raise SystemExit("ERRO: entradas ausentes: " + ", ".join(missing))
    if wrapped:
        raise SystemExit("ERRO: caminho com pasta externa no ZIP: " + ", ".join(wrapped))
    print("- ZIP verificado: %d entradas, raiz correta" % len(names))
PY_CHECK_EOF
fi

printf '%s\n' "- Pronto: $OUT"
if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "$OUT"
fi
'''

parts = [HEADER]
for name in FILES:
    content = (MOD / name).read_text()
    if "__USB_BLOCKER_FILE_EOF__" in content:
        raise SystemExit("delimiter collision in " + name)
    parts.append('\ncat > "$BUILD_DIR/%s" <<\'__USB_BLOCKER_FILE_EOF__\'\n' % name)
    parts.append(content)
    if not content.endswith("\n"):
        parts.append("\n")
    parts.append("__USB_BLOCKER_FILE_EOF__\n")
parts.append(FOOTER)
OUT.write_text("".join(parts), newline="\n")
print("wrote", OUT, OUT.stat().st_size, "bytes")
