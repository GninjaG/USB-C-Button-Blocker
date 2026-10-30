#!/system/bin/sh
ui_print "- USB-C Button Blocker"

if [ -z "${MODPATH:-}" ]; then
  abort "! MODPATH is not set"
fi

_have_common=0

# 1. Gera os arquivos estaticos ANTES do set_perm_recursive, para que as
#    pastas-pai (system, system/usr, system/usr/keylayout) sejam rotuladas.
if [ -r "$MODPATH/common.sh" ]; then
  MODDIR="$MODPATH"
  . "$MODPATH/common.sh"
  _have_common=1
  purge_legacy_vendor >/dev/null 2>&1
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

# 3. Verificacao fail-closed: nunca deixe um payload system/ mal rotulado ou
#    vazio ser montado. Se nao for possivel provar o contexto, remova-o.
if [ "$_have_common" -eq 1 ] && [ -d "$MODPATH/system" ]; then
  if ! chcon -R u:object_r:system_file:s0 "$MODPATH/system" 2>/dev/null; then
    find "$MODPATH/system" -exec chcon u:object_r:system_file:s0 {} \; 2>/dev/null
  fi

  _has_kl=0
  for _klf in "$MODPATH/system/usr/keylayout"/*.kl; do
    if [ -f "$_klf" ]; then
      _has_kl=1
      break
    fi
  done

  if [ "$_has_kl" -eq 0 ] ||
     ! context_is_system_file "$MODPATH/system" ||
     ! context_is_system_file "$MODPATH/system/usr" ||
     ! context_is_system_file "$MODPATH/system/usr/keylayout"; then
    ui_print "! Could not verify system_file SELinux context"
    ui_print "! Removing keylayout payload to protect boot"
    rm -rf "$MODPATH/system"
  fi
fi

ui_print "- Reboot to activate"
