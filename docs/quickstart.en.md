# LogiTrack quick start

This guide starts the complete local LogiTrack stack, verifies an order-to-delivery flow, and shuts the stack down without losing local data. The local environment uses synthetic data and is not a production deployment.

## Prerequisites

The container-based quick start requires:

- Docker Desktop with Docker Compose v2 (`docker compose version`)
- PowerShell 7 (`pwsh --version`)
- Git

The repository's host-side development and CI baselines are Java 21, Python 3.12, and Node.js 22. You do not need to install those runtimes for the container-only quick start because the images build them in isolated Docker stages.

Clone the repository and enter its root directory:

```powershell
git clone https://github.com/automaster5013/LogiTrack.git
Set-Location LogiTrack
```

## Initialize local secrets

Create the Git-ignored `.env` file before starting the stack:

```powershell
pwsh ./scripts/init-env.ps1
```

The script reads `.env.example` and generates independent cryptographically random values for the PostgreSQL and Grafana passwords. It never prints those passwords and refuses to overwrite an existing `.env` file. If the file already exists, keep using it; follow the credential-rotation procedure in the [operations guide](operations.md#로컬-자격-증명) instead of replacing it while volumes contain data.

Do not commit `.env`, reuse these local credentials in another environment, or treat the local authentication settings as production defaults.

## Start the stack

Build the application images, start every service, and wait for their readiness checks:

```powershell
docker compose up --build --wait
docker compose ps
```

The initial image build and dependency download can take several minutes. A successful `--wait` returns only after the long-running services report healthy.

## Open the local services

| Service | URL | Notes |
| --- | --- | --- |
| Project showcase | <http://localhost:3000/> | Product overview and architecture narrative |
| Operator console | <http://localhost:3000/console> | Orders, fleet map, warehouse, recovery, and alert policies |
| API health | <http://localhost:8080/actuator/health> | Expected response includes `"status":"UP"` |
| Grafana | <http://localhost:3001/> | User `admin`; read `GRAFANA_ADMIN_PASSWORD` from your local `.env` |
| Tempo API | <http://localhost:3200/> | Query traces through Grafana **Explore → Tempo** |

All development ports bind to loopback. The local Compose profile explicitly disables API authentication and is intended only for development on the host machine.

## Verify order creation and dispatch

The following PowerShell commands create a clearly synthetic order, dispatch it to a demo vehicle, and read the linked delivery. Random idempotency keys make the flow safe to repeat without colliding with an earlier run.

```powershell
$orderBody = @{
  orderNumber = "QS-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
  origin = @{ name = "Seoul Quickstart Hub"; lat = 37.5665; lon = 126.9780 }
  destination = @{ name = "Incheon Quickstart DC"; lat = 37.4563; lon = 126.7052 }
} | ConvertTo-Json -Depth 3

$order = Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:8080/api/orders" `
  -ContentType "application/json" `
  -Headers @{ "Idempotency-Key" = [guid]::NewGuid().ToString() } `
  -Body $orderBody

$dispatched = Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:8080/api/orders/$($order.id)/dispatch" `
  -ContentType "application/json" `
  -Headers @{ "Idempotency-Key" = [guid]::NewGuid().ToString() } `
  -Body (@{ vehicleId = "QUICKSTART-TRUCK-01" } | ConvertTo-Json)

Invoke-RestMethod `
  -Uri "http://localhost:8080/api/deliveries/$($dispatched.deliveryId)"
```

The first read normally shows `CREATED` or `IN_TRANSIT`. The simulator advances the synthetic vehicle asynchronously; refresh the operator console or repeat the final `Invoke-RestMethod` command to observe progress toward `DELIVERED`.

For the repository's complete cross-service verification, run:

```powershell
pwsh ./scripts/smoke.ps1
```

## Stop safely

Stop and remove the containers and networks while preserving PostgreSQL, Kafka, Redis, Tempo, Prometheus, and Grafana named volumes:

```powershell
docker compose down
```

The next `docker compose up --build --wait` reuses the preserved local data. Keep the existing `.env` with those volumes so the stored PostgreSQL and Grafana credentials remain consistent.

### Optional destructive reset

> **Data-removing operation:** the following command permanently deletes the local Compose volumes, including orders, delivery history, event state, traces, metrics, and Grafana state. Run it only when you intentionally want a blank local environment.

```powershell
docker compose down --volumes --remove-orphans
```

This command does not delete `.env`. You can reuse the file for the new empty volumes or rotate it later using the documented operations procedure.

## Continue reading

- [Project README](../README.md)
- [Architecture and data model](architecture.md)
- [Local operations and recovery](operations.md)
- [Security policy](../SECURITY.md)
- [Contribution guide](../CONTRIBUTING.md)
- [CI/CD and release strategy](delivery.md)
- [10-minute demo scenario](demo.md)
