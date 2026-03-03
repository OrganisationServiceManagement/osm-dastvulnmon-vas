# osm-dastvulnmon-vas

Greenbone / OpenVAS vulnerability monitoring for OSM — containerised deployment
using [greenbone-container-images](https://github.com/greenbone/greenbone-container-images).

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Centralised Reporting Portal                │
│                                                             │
│  ┌──────────────┐   ┌──────────┐   ┌──────────────────────┐ │
│  │ ospd-openvas │◄──│  gvmd    │──►│ Security Assistant   │ │
│  │  (scan coord)│   │(mgmt dmn)│   │ gsad + gsa + nginx   │ │
│  └──────┬───────┘   └──────────┘   └──────────────────────┘ │
│         │                                                   │
│  ┌──────▼───────┐  ┌──────────┐  ┌──────────────────────┐  │
│  │   openvasd   │  │  pg-gvm  │  │  Feeds (scap, cert,   │  │
│  │ (local notus)│  │ (database│  │  data-objects, …)     │  │
│  └──────────────┘  └──────────┘  └──────────────────────┘  │
└─────────────────────────────┬───────────────────────────────┘
                              │ OSPD (port 9390, optional TLS)
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│  Scanner Node 1 │ │  Scanner Node 2 │ │  Scanner Node N │
│                 │ │                 │ │    (optional)   │
│ ┌─────────────┐ │ │ ┌─────────────┐ │ │ ┌─────────────┐ │
│ │ ospd-openvas│ │ │ │ ospd-openvas│ │ │ │ ospd-openvas│ │
│ └──────┬──────┘ │ │ └──────┬──────┘ │ │ └──────┬──────┘ │
│        │        │ │        │        │ │        │        │
│ ┌──────▼──────┐ │ │ ┌──────▼──────┐ │ │ ┌──────▼──────┐ │
│ │  openvasd   │ │ │ │  openvasd   │ │ │ │  openvasd   │ │
│ │  (full mode)│ │ │ │  (full mode)│ │ │ │  (full mode)│ │
│ │ Notus +     │ │ │ │ Notus +     │ │ │ │ Notus +     │ │
│ │ openVAS     │ │ │ │ openVAS     │ │ │ │ openVAS     │ │
│ └─────────────┘ │ │ └─────────────┘ │ │ └─────────────┘ │
└─────────────────┘ └─────────────────┘ └─────────────────┘
  Decentralised       Decentralised       Decentralised
  Scanner Node        Scanner Node        Scanner Node
```

### Components

| Location | Component | Description |
|---|---|---|
| Portal | **ospd-openvas** | Open Scanner Protocol Daemon — scan coordinator |
| Portal | **gvmd** | Greenbone Vulnerability Management Daemon |
| Portal | **Security Assistant** | `gsad` + `gsa` + `nginx` — web reporting UI |
| Portal | pg-gvm | PostgreSQL database |
| Portal | redis-server | Redis cache (used by ospd-openvas) |
| Portal | openvasd (notus) | Built-in local Notus scan backend |
| Portal | Feed containers | scap-data, cert-data, data-objects, report-formats, … |
| Scanner | **ospd-openvas** | Remote scan coordinator (exposed on OSPD port) |
| Scanner | **Notus Scanner** | Advisory-based local vulnerability checks (via openvasd) |
| Scanner | **openVAS Scanner** | NASL-based network vulnerability scanning (via openvasd) |
| Scanner | redis-server | Redis cache (used by the scanner's ospd-openvas) |
| Scanner | Feed containers | vulnerability-tests, notus-data, gpg-data |

---

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) ≥ 24 — required for the `healthcheck`
  `start_period` syntax and the `service_completed_successfully` condition used in
  `depends_on` blocks
- [Docker Compose](https://docs.docker.com/compose/) ≥ 2.20 (`docker compose` CLI plugin)
  — required for the `name:` top-level key and full `depends_on` condition support
- On scanner nodes: `NET_ADMIN` and `NET_RAW` capabilities (standard on most Linux hosts)

---

## Quick Start — Standalone (all-in-one)

Deploy the full stack on a single host. The portal includes a built-in local scanner.

```bash
# 1. Copy and optionally customise the portal environment file
cp portal/.env.example portal/.env

# 2. Start all services
docker compose -f portal/compose.yaml up -d

# 3. Wait for feeds to synchronise (~10–20 min on first run), then open:
#    https://localhost:9392
#    Default credentials: admin / admin
```

---

## Distributed Deployment

### Step 1 — Start the centralised portal

```bash
cp portal/.env.example portal/.env
# Edit portal/.env if required (e.g. change PORTAL_HOST)
docker compose -f portal/compose.yaml up -d
```

### Step 2 — Start one or more scanner nodes

Run the following on **each** remote scanner host:

```bash
cp scanner/.env.example scanner/.env
# Edit scanner/.env — ensure SCANNER_LISTEN and SCANNER_PORT are correct
docker compose -f scanner/compose.yaml up -d
```

> **Port access**: The scanner exposes `ospd-openvas` on `SCANNER_PORT` (default 9390).
> Make sure this port is reachable from the portal host (firewall / security groups).

### Step 3 — Register each scanner with gvmd

Use the provided helper script from the portal host. The script reads credentials from
`GMP_USERNAME` and `GMP_PASSWORD` environment variables (defaults to `admin` — change
after first login):

```bash
# Register a single remote scanner
GMP_PASSWORD=<your-admin-password> ./scripts/register-scanner.sh <scanner-host>

# Register with a custom port and display name
GMP_PASSWORD=<your-admin-password> ./scripts/register-scanner.sh 192.168.1.50 9390 "Scanner - DMZ"
```

Alternatively, register scanners manually via the Greenbone Security Assistant:
**Configuration → Scanners → New Scanner**.

### Step 4 — Create and run scan tasks

Open the Security Assistant at `https://<portal-host>:9392`, create a **Scan Target**
and a **Scan Task**, then select the desired scanner when creating the task.

---

## Configuration Reference

### Portal (`portal/.env`)

| Variable | Default | Description |
|---|---|---|
| `PORTAL_HOST` | `127.0.0.1` | Interface nginx binds HTTPS/9392 on |
| `FEED_RELEASE` | `24.10` | Greenbone feed release tag |
| `OPENVASD_SERVER` | `http://openvasd:80` | openvasd backend URL used by the portal's ospd-openvas. Set to a remote scanner to redirect local scanning. |

### Scanner (`scanner/.env`)

| Variable | Default | Description |
|---|---|---|
| `SCANNER_LISTEN` | `0.0.0.0` | Interface ospd-openvas binds on |
| `SCANNER_PORT` | `9390` | Host port published for gvmd OSPD connections |
| `FEED_RELEASE` | `24.10` | Greenbone feed release tag |

---

## Directory Structure

```
.
├── portal/
│   ├── compose.yaml        # Centralised portal stack
│   └── .env.example        # Portal environment variable template
├── scanner/
│   ├── compose.yaml        # Decentralised scanner node stack
│   └── .env.example        # Scanner environment variable template
└── scripts/
    └── register-scanner.sh # Helper: register a remote scanner with gvmd
```

---

## Useful Commands

```bash
# View portal service logs
docker compose -f portal/compose.yaml logs -f

# View scanner node logs
docker compose -f scanner/compose.yaml logs -f

# Stop all portal services
docker compose -f portal/compose.yaml down

# Stop scanner node (data volumes preserved)
docker compose -f scanner/compose.yaml down

# Remove all volumes (full reset — data will be lost)
docker compose -f portal/compose.yaml down -v
docker compose -f scanner/compose.yaml down -v
```

---

## Security Notes

- By default the portal is bound to `127.0.0.1`. Change `PORTAL_HOST` to expose it on
  your network, and ensure access is controlled by a firewall.
- The scanner's `ospd-openvas` OSPD port (9390) should only be accessible from the
  portal host. Restrict access with firewall rules.
- Change the default `admin` / `admin` credentials immediately after first login.
- For production deployments, consider placing the portal behind a reverse proxy with
  a trusted TLS certificate.

---

## References

- [Greenbone Container Images](https://github.com/greenbone/greenbone-container-images)
- [Greenbone Community Documentation](https://greenbone.github.io/docs/latest/)
- [Greenbone Community Forum — Remote Scanners](https://forum.greenbone.net/t/how-to-deploy-a-remote-greenbone-scanner-via-docker-compose/21826)

