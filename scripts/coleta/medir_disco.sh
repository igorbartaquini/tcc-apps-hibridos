#!/usr/bin/env bash
# =====================================================================
# Medicao de disco (QP4) no Ubuntu, tudo num comando
# Gera ~/tcc/dados/disco_linux.csv com uma linha por alvo.
#
# Rode depois de ter usado cada aplicativo pelo menos uma vez, para o
# cache ja existir.
#
#   bash ~/tcc/scripts/medir_disco.sh
# =====================================================================
export LC_ALL=C LC_NUMERIC=C

SAIDA="${SAIDA:-$HOME/tcc/dados}"
mkdir -p "$SAIDA"
ARQ="$SAIDA/disco_linux.csv"
echo "alvo,camada,tipo,mb,arquivos,existe,caminho" > "$ARQ"

medir() {   # $1 alvo  $2 camada  $3 tipo  $4 caminho
  local alvo="$1" camada="$2" tipo="$3" cam="$4"
  if [ -z "$cam" ] || [ ! -e "$cam" ]; then
    echo "$alvo,$camada,$tipo,0,0,nao,$cam" >> "$ARQ"
    return
  fi
  local kb n
  kb=$(du -sk "$cam" 2>/dev/null | cut -f1)
  [ -z "$kb" ] && kb=0
  if [ -d "$cam" ]; then
    n=$(find "$cam" -type f 2>/dev/null | wc -l)
  else
    n=1
  fi
  awk -v a="$alvo" -v c="$camada" -v t="$tipo" -v k="$kb" -v n="$n" -v p="$cam" \
    'BEGIN{printf "%s,%s,%s,%.2f,%d,sim,%s\n", a, c, t, k/1024, n, p}' >> "$ARQ"
}

echo "Medindo disco. Pode levar alguns minutos."

# ---------- 1. instaladores baixados ----------
for f in "$HOME/tcc/instaladores"/*; do
  [ -f "$f" ] || continue
  medir "$(basename "$f")" instalador instalador "$f"
done

# ---------- 2. motor compartilhado ----------
# No Linux nao existe runtime WebView2. O Chrome e o unico motor
# compartilhado, e so entre as abas dele.
echo "  chrome..."
medir chrome compartilhado instalado /opt/google/chrome

# ---------- 3. instalado por aplicativo ----------
echo "  instalado..."
# Slack: pacote snap. O .snap e comprimido, a pasta montada e o tamanho
# real em uso. As duas medidas entram, porque sao coisas diferentes.
medir slack_snap_arquivo electron instalado "$(ls -1 /var/lib/snapd/snaps/slack_*.snap 2>/dev/null | tail -1)"
medir slack_snap_montado electron instalado /snap/slack/current
# Discord: pacote .deb, instalacao comum
medir discord electron instalado /usr/share/discord
medir discord_opt electron instalado /opt/discord

# ---------- 4. perfil e cache por aplicativo ----------
echo "  perfil e cache..."
medir slack   electron  perfil_cache "$HOME/snap/slack/current/.config/Slack"
medir slack_alt electron perfil_cache "$HOME/.config/Slack"
medir discord electron  perfil_cache "$HOME/.config/discord"
medir chrome_perfil navegador perfil_cache "$HOME/.config/google-chrome/Default"

echo ""
if command -v column >/dev/null 2>&1; then
  column -s, -t "$ARQ"
else
  cat "$ARQ"
fi
echo ""
echo "Gravado em $ARQ"
echo "Linha com existe=sim e arquivos=0 significa pasta vazia ou sem permissao."
