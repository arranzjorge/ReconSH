# ---------------------------------------------------------------------------
# Etapa 1: compilar las herramientas de ProjectDiscovery con Go
# ---------------------------------------------------------------------------
FROM golang:1.22-bookworm AS builder

ENV GOPATH=/go
ENV PATH=$GOPATH/bin:$PATH

RUN go install github.com/projectdiscovery/subfinder/v2/cmd/subfinder@v2.15.0 && \
    go install github.com/projectdiscovery/httpx/cmd/httpx@latest && \
    go install github.com/projectdiscovery/nuclei/v3/cmd/nuclei@latest

# ---------------------------------------------------------------------------
# Etapa 2: imagen final, ligera, solo con lo necesario para ejecutar
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim

LABEL maintainer="Jorge Arranz"
LABEL description="recon-chain: subfinder -> httpx -> nmap -> nuclei -> informe"

RUN apt-get update && apt-get install -y --no-install-recommends \
        nmap \
        jq \
        bash \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Copia los binarios compilados en la etapa anterior
COPY --from=builder /go/bin/subfinder /usr/local/bin/subfinder
COPY --from=builder /go/bin/httpx /usr/local/bin/httpx
COPY --from=builder /go/bin/nuclei /usr/local/bin/nuclei

# Descarga las plantillas de nuclei durante el build para no hacerlo en cada ejecución
RUN nuclei -update-templates -silent || true

WORKDIR /app

COPY recon-chain.sh /app/recon-chain.sh
RUN chmod +x /app/recon-chain.sh

# Los resultados se escriben aquí; monta un volumen sobre esta ruta
RUN mkdir -p /app/results
VOLUME ["/app/results"]

ENTRYPOINT ["/app/recon-chain.sh"]
CMD ["-h"]
