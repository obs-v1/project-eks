# project-eks/observability — the monitoring stack (obs cluster)

Everything you taught, on the observability EKS cluster, via Helm with EBS persistence:

| Component | Chart | Role |
|---|---|---|
| OTel Collector | `open-telemetry/opentelemetry-collector` | OTLP hub → Jaeger / Prometheus / Loki; **internal NLB** for cross-VPC ingest |
| kube-prometheus-stack | `prometheus-community/kube-prometheus-stack` | Prometheus (exemplars + remote-write) · Alertmanager · Grafana · node-exporter · kube-state |
| Loki | `grafana/loki` | logs (native OTLP, structured-metadata `trace_id`) |
| Jaeger | `jaegertracing/jaeger` | traces (all-in-one, Badger on EBS) |
| Pyroscope | `grafana/pyroscope` | profiles |
| Pyrra | manifests | SLOs / error-budget burn (from 3.1.10) |

Grafana ships **pre-wired** with all four pivots: exemplars → Jaeger, Loki `derivedFields` → Jaeger,
Jaeger `tracesToLogsV2` → Loki and `tracesToProfiles` → Pyroscope.

## Deploy

```bash
# point kubectl at the obs cluster first:  make -C ../cluster kubeconfig
make all DOMAIN=lab.example.com
```

`make all` runs in dependency order (kps CRDs → backends → collector → pyrra → edges). Individual
targets exist for every component (`make loki`, `make jaeger`, …).

## Cross-VPC ingest

`make collector-lb` creates an **internal** NLB and external-dns publishes it as
`otel-collector.obs.internal` into the shared private zone. BankObs (other VPC) sends OTLP there over
the peering — never the public internet. Override the name with `COLLECTOR_HOST=…` if you changed
`private_dns_domain` in `../cluster`.

## UIs

`make ingress DOMAIN=…` publishes `grafana.<DOMAIN>`, `jaeger.<DOMAIN>`, `prometheus.<DOMAIN>`,
`alertmanager.<DOMAIN>`, `pyroscope.<DOMAIN>` via Traefik (TLS at the NLB, records via external-dns).

> The sample Pyrra SLO (`pyrra/slo.yaml`) targets `demo-app` — point it at a real bankobs metric
> once the app is up.
