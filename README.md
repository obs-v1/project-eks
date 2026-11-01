# project-eks — BankObs + full observability on EKS, the real way

Two EKS clusters in two VPCs: one runs the **observability stack**, the other runs **BankObs**
(60 microservices). Telemetry flows **privately** between them over VPC peering; the UIs and the
app frontend are exposed publicly through Traefik with your own DNS + ACM cert.

```
   Internet ──TLS(ACM)──► Traefik NLB (public)                 Traefik NLB (public) ──TLS(ACM)──► Internet
                 │                                                      │
        ┌────────┴─────────────┐                          ┌────────────┴───────────┐
        │  OBSERVABILITY VPC    │   VPC peering (private)  │     BANKOBS VPC         │
        │  10.10.0.0/16         │◄────────────────────────►│     10.20.0.0/16        │
        │                       │                          │                         │
        │  EKS: observability   │   otel-collector         │   EKS: bankobs          │
        │   • OTel Collector ◄──┼──.obs.internal:4317──────┼── 60 services (OTLP)    │
        │   • Prometheus/Grafana│   (Route53 private zone, │   • StatefulSet DBs      │
        │   • Loki · Jaeger     │    resolves in both VPCs)│   • web-portal (frontend)│
        │   • Pyroscope · Pyrra │                          │                         │
        └───────────────────────┘                          └─────────────────────────┘
          grafana/jaeger/… .<DOMAIN>                          bankobs.<DOMAIN>
```

## Three layers

| Folder | What it does | Entry |
|---|---|---|
| [`cluster/`](cluster) | Terraform: 2 VPCs + peering + private zone + 2 EKS + Spot nodes + addons | `make apply` |
| [`observability/`](observability) | Helm: Collector, kube-prometheus-stack, Loki, Jaeger, Pyroscope, Pyrra | `make all` |
| [`app/`](app) | BankObs: 60 per-service charts (passthrough Dockerfiles) + platform StatefulSets | `make all` |

## End-to-end

```bash
# 1. Clusters (supply YOUR public zone, domain, wildcard ACM cert)
cd cluster
make apply ZONE_ID=Z0123... DOMAIN=lab.example.com ACM_ARN=arn:aws:acm:us-east-1:111122223333:certificate/abcd
make kubeconfig                      # both clusters into your kubeconfig

# 2. Observability stack (obs cluster)
cd ../observability && make all DOMAIN=lab.example.com

# 3. BankObs (bankobs cluster)
cd ../app && make all DOMAIN=lab.example.com
```

Then: `https://grafana.lab.example.com` (single pane), `https://bankobs.lab.example.com` (app),
and fault injection via `kubectl -n bankobs scale deploy/fault-injector --replicas=1`.

## Cost & teardown

Spot nodes keep it cheap, but two EKS control planes + NAT + NLBs + EBS still cost real money.
Tear down in reverse: `app → observability → cluster` (`make destroy` in each), and finally
`cd cluster && make destroy`.

## Design notes

- **Spot everywhere**, diversified instance sets + **Cluster Autoscaler** so a Spot interruption
  can't drain a cluster.
- **Private telemetry**: a Route53 private zone shared by both VPCs resolves `otel-collector.obs.internal`;
  the peering is what actually routes it. Telemetry never touches the internet.
- **Public endpoints**: EKS API is public (kubectl from anywhere); UIs/frontend via Traefik + external-dns + ACM.
- **BankObs images stay private to you**: each service is a passthrough `FROM`, so students can wire
  their own ECR + CI/CD without the source.
