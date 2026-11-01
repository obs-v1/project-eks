# ─────────────────────────────────────────────────────────────────────────────
#  project-eks/observability — the monitoring stack on the observability cluster
#
#  make all                 # everything, in dependency order
#  make otel-collector | kube-prometheus-stack | loki | jaeger | pyroscope | pyrra
#  make ingress | collector-lb
#
#  Inputs:
#    DOMAIN          public base domain for the UI hosts (grafana.$DOMAIN, …)   [required for `ingress`]
#    COLLECTOR_HOST  private name BankObs pushes OTLP to    [default otel-collector.obs.internal]
#    CONTEXT         kube context of the OBS cluster        [default obs-v1-observability]
# ─────────────────────────────────────────────────────────────────────────────
NS             ?= monitoring
CONTEXT        ?= obs-v1-observability
COLLECTOR_HOST ?= otel-collector.obs.internal
DOMAIN         ?=

H  = helm --kube-context $(CONTEXT) upgrade --install
K  = kubectl --context $(CONTEXT)
HN = -n $(NS)

AGENT_CTX ?= obs-v1-bankobs   # the agent runs IN the bankobs cluster

.PHONY: repos namespace all otel-collector kube-prometheus-stack loki jaeger pyroscope pyrra ingress collector-lb agent destroy

# Collector agent in the BANKOBS cluster: scrapes /metrics + tails logs locally and forwards
# them by OTLP to the central collector across the peering. (Deploy after the obs stack.)
agent: repos
	helm --kube-context $(AGENT_CTX) upgrade --install bankobs-agent open-telemetry/opentelemetry-collector \
	  --version 0.178.1 -n monitoring --create-namespace -f agent/values-agent.yaml
	@echo "  ✓ bankobs-agent deployed to $(AGENT_CTX) (metrics scrape + logs tail → obs collector)."

repos:
	helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo add jaegertracing https://jaegertracing.github.io/helm-charts
	helm repo update

namespace:
	$(K) create namespace $(NS) --dry-run=client -o yaml | $(K) apply -f -

# Order: Prometheus Operator CRDs first (kps), then backends, then collector, then pyrra, then edges.
all: repos namespace kube-prometheus-stack loki jaeger pyroscope otel-collector pyrra collector-lb ingress
	@echo ""; echo "  ✓ observability stack deployed to context $(CONTEXT)."

kube-prometheus-stack: namespace
	$(H) kps prometheus-community/kube-prometheus-stack --version 92.17.0 $(HN) \
	  -f values/kube-prometheus-stack.yaml --wait --timeout 15m

loki: namespace
	$(H) loki grafana/loki --version 7.5.0 $(HN) -f values/loki.yaml

jaeger: namespace
	$(H) jaeger jaegertracing/jaeger --version 4.16.1 $(HN) -f values/jaeger.yaml

pyroscope: namespace
	$(H) pyroscope grafana/pyroscope --version 2.4.2 $(HN) -f values/pyroscope.yaml

otel-collector: namespace
	$(H) otel-collector open-telemetry/opentelemetry-collector --version 0.178.1 $(HN) \
	  -f values/otel-collector.yaml

pyrra: namespace
	# CRD first (pinned upstream release), then the operator + UI, then the sample SLO.
	$(K) apply -f https://raw.githubusercontent.com/pyrra-dev/pyrra/v0.10.2/examples/kubernetes/manifests/setup/pyrra-slo-CustomResourceDefinition.yaml
	$(K) apply -f pyrra/pyrra.yaml
	$(K) apply -f pyrra/slo.yaml

collector-lb: namespace
	@sed 's|$${COLLECTOR_HOST}|$(COLLECTOR_HOST)|g' k8s/collector-internal-lb.yaml | $(K) apply -f -

ingress: namespace
	@test -n "$(DOMAIN)" || { echo "ERROR: set DOMAIN=lab.example.com"; exit 1; }
	@sed 's|$${DOMAIN}|$(DOMAIN)|g' ingress/ui-ingress.yaml | $(K) apply -f -
	@echo "  UIs (once DNS propagates): https://grafana.$(DOMAIN)  https://jaeger.$(DOMAIN)  https://prometheus.$(DOMAIN)  https://alertmanager.$(DOMAIN)  https://pyroscope.$(DOMAIN)"

destroy:
	-$(K) delete -f pyrra/slo.yaml --ignore-not-found
	-$(K) delete -f pyrra/pyrra.yaml --ignore-not-found
	-helm --kube-context $(CONTEXT) uninstall otel-collector pyroscope jaeger loki kps $(HN)
	@echo "  ✓ stack removed (PVCs/CRDs kept — delete manually if you want a clean slate)."
