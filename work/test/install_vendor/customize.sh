#!/system/bin/sh
ui_print "- USB-C Button Blocker"

if [ -z "${MODPATH:-}" ]; then
  abort "! MODPATH is not set"
fi

# 1. Gera os arquivos estaticos ANTES do set_perm_recursive, para que as
#    pastas-pai (system, system/usr, system/usr/keylayout) sejam rotuladas.
if [ -r "$MODPATH/common.sh" ]; then
  MODDIR="$MODPATH"
  . "$MODPATH/common.sh"
  # Remove any /vendor payload from the broken revision even if Generic.kl is
  # temporarily unavailable; set_perm_recursive must never relabel that tree.
  fix_system_tree_contexts >/dev/null 2>&1
  generate_static_analog_keylayouts >/dev/null 2>&1
fi

# 2. Aplica permissoes e SELinux u:object_r:system_file:s0 recursivamente em TUDO.
set_perm_recursive "$MODPATH" 0 0 0755 0644 u:object_r:system_file:s0

for _f in customize.sh common.sh post-fs-data.sh service.sh hotplug.sh; do
  if [ -f "$MODPATH/$_f" ]; then
    set_perm "$MODPATH/$_f" 0 0 0755 u:object_r:system_file:s0
  fi
done

ui_print "- Reboot to activate"
