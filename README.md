# ReconSH

Automatización de reconocimiento web encadenando **subfinder → httpx → nmap → nuclei**, con generación automática de un **informe final en Markdown**. Pensado para ejecutarse en Kali Linux (o cualquier distro con las dependencias instaladas), y con soporte para Docker.

> ⚠️ **Uso responsable**: esta herramienta está pensada exclusivamente para auditorías autorizadas (programas de bug bounty, pentests contratados, tu propio laboratorio). El uso contra objetivos sin autorización explícita es ilegal. El autor no se responsabiliza de un uso indebido.

---

## ✨ Características

- **Enumeración de subdominios** con `subfinder`.
- **Detección de hosts vivos** con `httpx` (código de estado, título, tecnologías detectadas).
- **Escaneo de puertos y servicios** con `nmap`, paralelizado y limitado para no saturar la máquina.
- **Detección de vulnerabilidades** con `nuclei`, filtrable por severidad.
- **Informe final en Markdown** con tabla resumen, listado de subdominios, hosts vivos y hallazgos.
- Log completo de la ejecución (`recon.log`) para depuración.
- Opciones para omitir fases (`--skip-nmap`, `--skip-nuclei`) y ajustar hilos/puertos/severidad.

## 📋 Requisitos

- Bash
- [subfinder](https://github.com/projectdiscovery/subfinder)
- [httpx](https://github.com/projectdiscovery/httpx)
- [nuclei](https://github.com/projectdiscovery/nuclei)
- `nmap`
- `jq`

- 
En Kali Linux, `nmap` y `jq` ya suelen venir instalados o se instalan con:

```bash
sudo apt update && sudo apt install -y nmap jq
```

Las herramientas de ProjectDiscovery se instalan con Go:

```bash
go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest
go install github.com/projectdiscovery/httpx/cmd/httpx@latest
go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# Asegúrate de que $HOME/go/bin está en tu PATH
export PATH=$PATH:$HOME/go/bin
```

Y actualiza las plantillas de nuclei al menos una vez:

```bash
nuclei -update-templates
```

## 🚀 Instalación

```bash
git clone https://github.com/<tu-usuario>/recon-chain.git
cd recon-chain
chmod +x recon-chain.sh
```

## 🖥️ Uso

```bash
./ReconSH_v1.sh -d ejemplo.com
```

### Opciones

| Flag             | Descripción                                                              | Por defecto                       |
|------------------|---------------------------------------------------------------------------|------------------------------------|
| `-d <dominio>`   | Dominio objetivo (**obligatorio**)                                       | —                                   |
| `-o <directorio>`| Directorio de salida                                                     | `results/<dominio>_<fecha>`       |
| `-t <hilos>`     | Hilos para httpx/nuclei                                                  | `50`                                |
| `-p <puertos>`   | `top-1000` o rango, ej. `1-65535`                                        | `top-1000`                          |
| `-s <severidad>` | Severidades de nuclei separadas por coma                                | `low,medium,high,critical`         |
| `--skip-nmap`    | Omite la fase de nmap                                                    | —                                   |
| `--skip-nuclei`  | Omite la fase de nuclei                                                  | —                                   |
| `-h`             | Muestra la ayuda                                                          | —                                   |

### Ejemplos

```bash
# Escaneo completo
./recon-chain.sh -d ejemplo.com

# Solo hallazgos críticos/altos, más hilos, sin nmap
./recon-chain.sh -d ejemplo.com -s high,critical -t 100 --skip-nmap

# Full port scan
./recon-chain.sh -d ejemplo.com -p 1-65535
```

## 📁 Estructura de salida

```
results/ejemplo.com_20260827_101500/
├── subdomains.txt
├── live_hosts.txt
├── live_hosts.json
├── nmap/
│   ├── host1_ejemplo_com.txt
│   └── host2_ejemplo_com.txt
├── vulnerabilities.txt
├── vulnerabilities.json
├── informe.md          <- Informe final
└── recon.log
```

## 🐳 Uso con Docker

```bash
docker build -t recon-chain .
docker run --rm -v "$(pwd)/results:/app/results" recon-chain -d ejemplo.com
```

## 🗺️ Roadmap

- [ ] Exportar informe también en HTML
- [ ] Notificaciones por webhook (Slack/Discord/Telegram) al terminar
- [ ] Modo diff para comparar escaneos entre ejecuciones
- [ ] Soporte para listas de dominios (`-l dominios.txt`)
