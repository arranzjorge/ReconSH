#!/usr/bin/env bash
#
# recon-chain.sh
# ---------------------------------------------------------------------------
# Automatiza una cadena de reconocimiento web:
#   subfinder -> httpx -> nmap -> nuclei -> informe final (Markdown)
#
# Pensado para Kali Linux. Requiere: subfinder, httpx, nmap, nuclei, jq
#
# USO PERMITIDO ÚNICAMENTE SOBRE DOMINIOS PARA LOS QUE TIENES AUTORIZACIÓN
# EXPLÍCITA (programa de bug bounty, pentest contratado, tu propio lab, etc).
# El autor no se hace responsable de un uso indebido de esta herramienta.
# ---------------------------------------------------------------------------

set -uo pipefail

# ---------------------------- Configuración ---------------------------------

DOMAIN=""
OUTDIR=""
THREADS=50
NMAP_PORTS="top-1000"          # "top-1000" o rango tipo "1-65535"
NUCLEI_SEVERITY="low,medium,high,critical"
SKIP_NMAP=false
SKIP_NUCLEI=false

VERSION="1.0.0"

# ------------------------------ Colores -------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[*]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[+]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()   { echo -e "${RED}[-]${NC} $1" >&2; }

# ------------------------------- Ayuda ---------------------------------------

usage() {
    cat <<EOF
${BOLD}recon-chain.sh v${VERSION}${NC}
Automatiza: subfinder -> httpx -> nmap -> nuclei -> informe Markdown

Uso:
  $0 -d <dominio> [opciones]

Opciones:
  -d <dominio>        Dominio objetivo (obligatorio). Ej: -d ejemplo.com
  -o <directorio>      Directorio de salida (por defecto: results/<dominio>_<fecha>)
  -t <hilos>           Hilos para httpx/nuclei (por defecto: 50)
  -p <puertos>         Rango de puertos para nmap: "top-1000" o "1-65535" (por defecto: top-1000)
  -s <severidades>     Severidades de nuclei separadas por coma (por defecto: low,medium,high,critical)
  --skip-nmap          Omite la fase de nmap
  --skip-nuclei         Omite la fase de nuclei
  -h                    Muestra esta ayuda

Ejemplo:
  $0 -d ejemplo.com -o resultados/ejemplo -t 100 -s medium,high,critical
EOF
    exit 0
}

# --------------------------- Parseo de argumentos -----------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        -d) DOMAIN="$2"; shift 2 ;;
        -o) OUTDIR="$2"; shift 2 ;;
        -t) THREADS="$2"; shift 2 ;;
        -p) NMAP_PORTS="$2"; shift 2 ;;
        -s) NUCLEI_SEVERITY="$2"; shift 2 ;;
        --skip-nmap) SKIP_NMAP=true; shift ;;
        --skip-nuclei) SKIP_NUCLEI=true; shift ;;
        -h|--help) usage ;;
        *) log_err "Opción desconocida: $1"; usage ;;
    esac
done

if [[ -z "$DOMAIN" ]]; then
    log_err "Debes indicar un dominio con -d"
    usage
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTDIR="${OUTDIR:-results/${DOMAIN}_${TIMESTAMP}}"
mkdir -p "$OUTDIR"

SUBS_FILE="$OUTDIR/subdomains.txt"
LIVE_FILE="$OUTDIR/live_hosts.txt"
LIVE_JSON="$OUTDIR/live_hosts.json"
NMAP_DIR="$OUTDIR/nmap"
NUCLEI_FILE="$OUTDIR/vulnerabilities.txt"
NUCLEI_JSON="$OUTDIR/vulnerabilities.json"
REPORT_FILE="$OUTDIR/informe.md"
LOG_FILE="$OUTDIR/recon.log"

mkdir -p "$NMAP_DIR"

exec > >(tee -a "$LOG_FILE") 2>&1

# --------------------------- Comprobación de deps -----------------------------

check_deps() {
    local missing=()
    local deps=(subfinder httpx nmap jq)
    $SKIP_NUCLEI || deps+=(nuclei)

    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_err "Faltan herramientas: ${missing[*]}"
        log_info "Instálalas (ej: 'sudo apt install nmap jq' y 'go install ...' para las de ProjectDiscovery) y vuelve a ejecutar."
        exit 1
    fi
}

# ------------------------------- Fase 1: subfinder -----------------------------

run_subfinder() {
    log_info "Fase 1/4: Enumerando subdominios de $DOMAIN con subfinder..."
    subfinder -d "$DOMAIN" -silent -o "$SUBS_FILE" 2>>"$LOG_FILE"

    # Asegura que el propio dominio raíz también se analiza
    echo "$DOMAIN" >> "$SUBS_FILE"
    sort -u "$SUBS_FILE" -o "$SUBS_FILE"

    local count
    count=$(wc -l < "$SUBS_FILE")
    log_ok "Subdominios encontrados: $count"
}

# ------------------------------- Fase 2: httpx ---------------------------------

run_httpx() {
    log_info "Fase 2/4: Comprobando hosts vivos con httpx..."
    httpx -l "$SUBS_FILE" \
        -silent \
        -threads "$THREADS" \
        -status-code -title -tech-detect -follow-redirects \
        -json -o "$LIVE_JSON" 2>>"$LOG_FILE"

    jq -r '.url' "$LIVE_JSON" 2>/dev/null | sort -u > "$LIVE_FILE"

    local count
    count=$(wc -l < "$LIVE_FILE" 2>/dev/null || echo 0)
    log_ok "Hosts vivos: $count"
}

# ------------------------------- Fase 3: nmap ----------------------------------

run_nmap() {
    if $SKIP_NMAP; then
        log_warn "Fase 3/4: nmap omitido (--skip-nmap)"
        return
    fi

    log_info "Fase 3/4: Escaneando puertos con nmap..."

    # Extrae solo hosts/IPs únicos (sin esquema ni path) para nmap
    local hosts_file="$OUTDIR/hosts_for_nmap.txt"
    sed -E 's#^https?://##; s#/.*$##; s#:.*$##' "$LIVE_FILE" | sort -u > "$hosts_file"

    local port_flag="--top-ports 1000"
    [[ "$NMAP_PORTS" != "top-1000" ]] && port_flag="-p $NMAP_PORTS"

    while read -r host; do
        [[ -z "$host" ]] && continue
        local safe_name
        safe_name=$(echo "$host" | tr -c 'a-zA-Z0-9.-' '_')
        nmap -sV -T4 $port_flag -oN "$NMAP_DIR/${safe_name}.txt" "$host" &>>"$LOG_FILE" &

        # Limita ejecuciones paralelas para no saturar
        while [[ $(jobs -r | wc -l) -ge 10 ]]; do wait -n; done
    done < "$hosts_file"
    wait

    log_ok "Escaneo nmap completado. Resultados en $NMAP_DIR/"
}

# ------------------------------- Fase 4: nuclei --------------------------------

run_nuclei() {
    if $SKIP_NUCLEI; then
        log_warn "Fase 4/4: nuclei omitido (--skip-nuclei)"
        return
    fi

    log_info "Fase 4/4: Buscando vulnerabilidades con nuclei (severidad: $NUCLEI_SEVERITY)..."
    nuclei -l "$LIVE_FILE" \
        -severity "$NUCLEI_SEVERITY" \
        -c "$THREADS" \
        -silent \
        -jsonl -o "$NUCLEI_JSON" 2>>"$LOG_FILE"

    if [[ -f "$NUCLEI_JSON" ]]; then
        jq -r '"[\(.info.severity | ascii_upcase)] \(.info.name) -> \(.["matched-at"])"' \
            "$NUCLEI_JSON" 2>/dev/null | sort > "$NUCLEI_FILE"
    fi

    local count
    count=$(wc -l < "$NUCLEI_FILE" 2>/dev/null || echo 0)
    log_ok "Hallazgos de nuclei: $count"
}

# ------------------------------ Informe final ----------------------------------

generate_report() {
    log_info "Generando informe final..."

    local subs_count live_count nmap_count nuclei_count
    subs_count=$(wc -l < "$SUBS_FILE" 2>/dev/null || echo 0)
    live_count=$(wc -l < "$LIVE_FILE" 2>/dev/null || echo 0)
    nmap_count=$(find "$NMAP_DIR" -type f -name '*.txt' 2>/dev/null | wc -l)
    nuclei_count=$(wc -l < "$NUCLEI_FILE" 2>/dev/null || echo 0)

    {
        echo "# Informe de reconocimiento - $DOMAIN"
        echo
        echo "**Fecha:** $(date '+%Y-%m-%d %H:%M:%S')"
        echo "**Objetivo:** $DOMAIN"
        echo
        echo "## Resumen"
        echo
        echo "| Fase | Resultado |"
        echo "|------|-----------|"
        echo "| Subdominios encontrados | $subs_count |"
        echo "| Hosts vivos | $live_count |"
        echo "| Hosts escaneados con nmap | $nmap_count |"
        echo "| Hallazgos de nuclei | $nuclei_count |"
        echo
        echo "## Subdominios"
        echo
        echo '```'
        cat "$SUBS_FILE" 2>/dev/null
        echo '```'
        echo
        echo "## Hosts vivos (httpx)"
        echo
        if [[ -f "$LIVE_JSON" ]]; then
            echo "| URL | Código | Título | Tecnologías |"
            echo "|-----|--------|--------|-------------|"
            jq -r '[.url, (.["status-code"] // .status_code // "-" | tostring), (.title // "-"), ((.tech // []) | join(", "))] | @tsv' \
                "$LIVE_JSON" 2>/dev/null | awk -F'\t' '{printf "| %s | %s | %s | %s |\n", $1, $2, $3, $4}'
        fi
        echo
        echo "## Hallazgos de nuclei"
        echo
        if [[ -s "$NUCLEI_FILE" ]]; then
            echo '```'
            cat "$NUCLEI_FILE"
            echo '```'
        else
            echo "_Sin hallazgos o fase omitida._"
        fi
        echo
        echo "## Notas de nmap"
        echo
        echo "Resultados detallados por host en \`nmap/\`."
        echo
        echo "---"
        echo "_Generado automáticamente con recon-chain.sh v${VERSION}_"
    } > "$REPORT_FILE"

    log_ok "Informe generado en: $REPORT_FILE"
}

# ---------------------------------- Main ----------------------------------------

main() {
    echo -e "${BOLD}=== recon-chain.sh v${VERSION} ===${NC}"
    log_info "Objetivo: $DOMAIN"
    log_info "Salida:   $OUTDIR"
    echo

    check_deps
    run_subfinder
    run_httpx
    run_nmap
    run_nuclei
    generate_report

    echo
    log_ok "Recon completo. Revisa el informe: $REPORT_FILE"
}

main
