#!/usr/bin/env bash
# Author: Dark Oliveira
# Date: 09-09-2025
# Configura desbloqueio automático de LUKS no Debian/Ubuntu durante o boot do sistema
#

set -euo pipefail

KEYFILE="/etc/keys/luks.key"
CONF_HOOK="/etc/cryptsetup-initramfs/conf-hook"
CONF_INIT="/etc/initramfs-tools/initramfs.conf"

say() { printf "%b\n" "$*"; }

# Verificar se é root
if [[ $EUID -ne 0 ]]; then
  say "❌ Este script precisa ser executado como root (use: sudo $0)"
  exit 1
fi

# === Verificação de dependências ===
check_deps() {
  local deps=(cryptsetup lsblk blkid findmnt update-initramfs)
  local missing=()
  for dep in "${deps[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
      missing+=("$dep")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    say "❌ Dependências ausentes: ${missing[*]}"
    say "   Instale com: sudo apt update && sudo apt install cryptsetup initramfs-tools util-linux"
    exit 1
  fi
}
check_deps

# Retorna (se existir) o mapper dm-crypt aberto para um dado device-base LUKS
luks_mapper_of() {
  local dev="$1"
  [[ "$dev" =~ ^/dev/ ]] || dev="/dev/$dev"
  lsblk -pnlo NAME,TYPE "$dev" | awk '$2=="crypt"{print $1; exit}'
}

# Lista mountpoints (em quaisquer descendentes) do mapper
mountpoints_under() {
  local mapper="$1"
  [[ -n "$mapper" ]] || return 0
  lsblk -pnlo NAME,MOUNTPOINT "$mapper" \
    | awk 'NF>1{print $2}' \
    | sort -u \
    | sed '/^\s*$/d'
}

# Gera (ou reutiliza) keyfile segura
ensure_keyfile() {
  mkdir -p /etc/keys
  chmod 700 /etc/keys
  if [[ ! -f "$KEYFILE" ]]; then
    dd if=/dev/urandom of="$KEYFILE" bs=4096 count=1 status=none
    chmod 600 "$KEYFILE"
    say "→ Keyfile criada em $KEYFILE"
  else
    say "→ Keyfile existente será reutilizada: $KEYFILE"
  fi
}

# Configura conf-hook e initramfs.conf
ensure_initramfs_settings() {
  mkdir -p "$(dirname "$CONF_HOOK")"
  grep -q '^KEYFILE_PATTERN=' "$CONF_HOOK" 2>/dev/null || echo 'KEYFILE_PATTERN="/etc/keys/*.key"' >> "$CONF_HOOK"
  grep -q '^ASKPASS=n' "$CONF_HOOK" 2>/dev/null || echo 'ASKPASS=n' >> "$CONF_HOOK"


  if grep -q '^UMASK=' "$CONF_INIT" 2>/dev/null; then
    sed -i 's/^UMASK=.*/UMASK=0077/' "$CONF_INIT"
  else
    echo 'UMASK=0077' >> "$CONF_INIT"
  fi
}

# Adiciona entrada em /etc/crypttab para um device LUKS base (/dev/sdXn, /dev/mdX, etc.)
# Adiciona ou atualiza entrada em /etc/crypttab para um device LUKS
ensure_crypttab_entry() {
  local dev="$1"
  local uuid name
  uuid=$(blkid -s UUID -o value "$dev")
  name="$(basename "$dev")_crypt"

  if grep -q "UUID=$uuid" /etc/crypttab 2>/dev/null; then
    # Atualiza só a coluna da chave (3ª)
    awk -v uuid="$uuid" -v key="$KEYFILE" '
      BEGIN {OFS="\t"}
      $0 ~ "UUID="uuid {
        # garante 4 colunas: name, source, key, options
        if (NF < 4) { for (i=NF+1; i<=4; i++) $i="" }
        $3 = key
      }
      {print}
    ' /etc/crypttab > /etc/crypttab.tmp
    mv /etc/crypttab.tmp /etc/crypttab
  else
    # Adiciona nova linha com key padrão
    echo -e "$name\tUUID=$uuid\t$KEYFILE\tluks" >> /etc/crypttab
  fi
}

say "=== Configuração automática de LUKS ==="
say "[1/7] Procurando dispositivos LUKS..."

mapfile -t luks_devices < <(lsblk -pnlo NAME | while read -r dev; do
  if cryptsetup isLuks "$dev" &>/dev/null; then
    echo "$dev"
  fi
done)

if (( ${#luks_devices[@]} == 0 )); then
  say "❌ Nenhum dispositivo LUKS encontrado."
  exit 1
fi

say "→ Dispositivos LUKS encontrados:"
for i in "${!luks_devices[@]}"; do
  dev="${luks_devices[$i]}"
  mapper=$(luks_mapper_of "$dev")
  if [[ -n "$mapper" ]]; then
    mpts=$(mountpoints_under "$mapper" | paste -sd',' - || true)
  else
    mpts=""
  fi
  printf "  [%d] %-22s | mapper: %-25s | mounts: %s\n" \
    "$i" "$dev" "${mapper:--}" "${mpts:--}"
done

read -rp "Digite os índices a configurar (ex.: 0 2): " -a idxs
declare -a targets=()
for idx in "${idxs[@]}"; do
  sel="${luks_devices[$idx]}"
  say "→ Selecionado: $sel"
  targets+=("$sel")
done

say "[2/7] Preparando keyfile…"
ensure_keyfile

for dev in "${targets[@]}"; do
  say "=== Configurando $dev ==="

  say "[3/7] Inserindo keyfile no LUKS… (pode pedir sua senha atual)"
  cryptsetup luksAddKey "$dev" "$KEYFILE"

  say "[4/7] Atualizando /etc/crypttab…"
  ensure_crypttab_entry "$dev"
done

say "[5/7] Ajustando initramfs (KEYFILE_PATTERN e UMASK)…"
ensure_initramfs_settings

say "[6/7] Atualizando initramfs…"
update-initramfs -u

say "[7/7] Resumo do /etc/crypttab:"
grep -E '^crypt' /etc/crypttab || true

say "✅ Concluído! Reinicie para testar: sudo reboot"
