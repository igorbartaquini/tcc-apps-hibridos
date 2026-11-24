#!/usr/bin/env bash
# =====================================================================
# Coleta de memoria e CPU no Ubuntu
# TCC - Tendencias e desafios de infraestrutura na era dos apps hibridos
#
# Metrica principal: PSS (Proportional Set Size), somado na arvore de
# processos, lido de /proc/<pid>/smaps_rollup.
# Metricas auxiliares: USS e RSS.
# Taxa: 1 amostra por segundo.
#
# Exemplo de uso:
#   ./coletar_linux.sh slack_electron_C1_linux_01 slack electron C1 "slack" 600
# =====================================================================
set -uo pipefail

RUN_ID="${1:?informe o run_id}"
APP="${2:?informe o app}"
CAMADA="${3:?informe a camada}"
CENARIO="${4:?informe o cenario}"
PROCESSOS="${5:?informe os nomes de processo separados por espaco}"
SEGUNDOS="${6:-600}"
SAIDA="${SAIDA:-$HOME/tcc/dados}"

mkdir -p "$SAIDA"
ARQ="$SAIDA/$RUN_ID.csv"
META="$SAIDA/$RUN_ID.meta.txt"

{
  echo "run_id=$RUN_ID"
  echo "app=$APP"
  echo "camada=$CAMADA"
  echo "cenario=$CENARIO"
  echo "so=$(lsb_release -ds 2>/dev/null || echo Linux)"
  echo "kernel=$(uname -r)"
  echo "processos_alvo=$PROCESSOS"
  echo "duracao_s=$SEGUNDOS"
  echo "inicio=$(date -Is)"
  echo "maquina=$(hostname)"
  echo "cpu=$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
  echo "ram_total_mb=$(( $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 ))"
} > "$META"

echo "timestamp,run_id,app,camada,cenario,so,n_processos,pss_mb,uss_mb,rss_mb,cpu_pct" > "$ARQ"

NUCLEOS=$(nproc)
TICK=$(getconf CLK_TCK)
declare -A CPU_ANT
PRIMEIRA=1

# monta a arvore de processos a partir dos nomes alvo
montar_arvore() {
  local raizes=() alvo
  for alvo in $PROCESSOS; do
    while read -r p; do raizes+=("$p"); done < <(pgrep -x "$alvo" 2>/dev/null)
  done
  [ ${#raizes[@]} -eq 0 ] && return
  local fila=("${raizes[@]}") vistos=() atual filhos f
  while [ ${#fila[@]} -gt 0 ]; do
    atual="${fila[0]}"; fila=("${fila[@]:1}")
    case " ${vistos[*]:-} " in *" $atual "*) continue;; esac
    vistos+=("$atual")
    filhos=$(pgrep -P "$atual" 2>/dev/null || true)
    for f in $filhos; do fila+=("$f"); done
  done
  printf '%s\n' "${vistos[@]}"
}

echo "Coletando $RUN_ID por $SEGUNDOS segundos..."

for ((i=0; i<SEGUNDOS; i++)); do
  T0=$(date +%s%N)
  PSS=0; USS=0; RSS=0; N=0; CPU_TOTAL=0
  declare -A CPU_ATU=()

  while read -r pid; do
    [ -z "$pid" ] && continue
    [ -r "/proc/$pid/smaps_rollup" ] || continue
    read -r p u1 u2 r < <(awk '
      /^Pss:/            {pss+=$2}
      /^Private_Clean:/  {pc+=$2}
      /^Private_Dirty:/  {pd+=$2}
      /^Rss:/            {rss+=$2}
      END {print pss+0, pc+0, pd+0, rss+0}' "/proc/$pid/smaps_rollup" 2>/dev/null)
    PSS=$((PSS + ${p:-0})); USS=$((USS + ${u1:-0} + ${u2:-0})); RSS=$((RSS + ${r:-0}))
    N=$((N+1))

    if [ -r "/proc/$pid/stat" ]; then
      ticks=$(awk '{print $14+$15}' "/proc/$pid/stat" 2>/dev/null || echo 0)
      CPU_ATU[$pid]=$ticks
      if [ -n "${CPU_ANT[$pid]:-}" ]; then
        CPU_TOTAL=$((CPU_TOTAL + ticks - ${CPU_ANT[$pid]}))
      fi
    fi
  done < <(montar_arvore)

  for k in "${!CPU_ATU[@]}"; do CPU_ANT[$k]=${CPU_ATU[$k]}; done

  if [ "$PRIMEIRA" -eq 1 ]; then CPU_PCT="0.00"; PRIMEIRA=0
  else CPU_PCT=$(awk -v t="$CPU_TOTAL" -v tk="$TICK" -v n="$NUCLEOS" 'BEGIN{printf "%.2f",(t/tk)/n*100}'); fi

  awk -v ts="$(date -Is)" -v r="$RUN_ID" -v a="$APP" -v c="$CAMADA" -v ce="$CENARIO" \
      -v n="$N" -v pss="$PSS" -v uss="$USS" -v rss="$RSS" -v cpu="$CPU_PCT" \
      'BEGIN{printf "%s,%s,%s,%s,%s,Linux,%d,%.2f,%.2f,%.2f,%s\n",ts,r,a,c,ce,n,pss/1024,uss/1024,rss/1024,cpu}' >> "$ARQ"

  GASTO=$(( ($(date +%s%N) - T0) / 1000000 ))
  ESPERA=$(( 1000 - GASTO ))
  [ "$ESPERA" -gt 0 ] && sleep "$(awk -v e=$ESPERA 'BEGIN{print e/1000}')"
done

echo "fim=$(date -Is)" >> "$META"
echo "Pronto: $ARQ"
