# ─────────────────────────────────────────────────────────────────────────────
#  project-eks/app — BankObs on the bankobs EKS cluster
#
#  make all                 # platform (DBs/web-portal) + all 60 service charts + frontend ingress
#  make platform            # databases, license-checker, web-portal, init jobs (StatefulSets)
#  make services            # helm upgrade --install every service, one after another (no wait)
#  make frontend DOMAIN=…   # expose web-portal at bankobs.<DOMAIN> via Traefik
#  make -C <service> deploy # a single service on its own (build/push/deploy live in each folder)
#  make regen               # re-stamp the per-service charts from _generate.sh
#
#  Inputs:  CTX (kube context, default obs-v1-bankobs) · ECR · TAG · DOMAIN · NS (default bankobs)
# ─────────────────────────────────────────────────────────────────────────────
NS     ?= bankobs
CTX    ?= obs-v1-bankobs
ECR    ?= public.ecr.aws/w8x4g9h7/obs-v1
TAG    ?= 1.0.0
DOMAIN ?=

K = kubectl --context $(CTX)

# Every folder that is a service chart (has a Chart.yaml) — platform/ has none.
SERVICES := $(patsubst %/Chart.yaml,%,$(wildcard */Chart.yaml))

.PHONY: all namespace platform services frontend list regen destroy

all: namespace platform services frontend
	@echo ""; echo "  ✓ BankObs deployed to context $(CTX) ($(words $(SERVICES)) services + platform)."

namespace:
	$(K) create namespace $(NS) --dry-run=client -o yaml | $(K) apply -f -

# Init ConfigMaps the DB StatefulSets mount (built from platform/infrastructure/).
configmaps: namespace
	$(K) create configmap oracle-init            --from-file=platform/infrastructure/databases/oracle/init-scripts        -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap postgres-init          --from-file=platform/infrastructure/databases/postgres/init-scripts      -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap mongo-init             --from-file=platform/infrastructure/databases/mongodb/init-scripts       -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap cassandra-init-scripts --from-file=platform/infrastructure/databases/cassandra/init-scripts     -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap es-init-scripts        --from-file=platform/infrastructure/databases/elasticsearch/init-scripts -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap kafka-init-scripts     --from-file=platform/infrastructure/messaging/kafka                      -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap rabbitmq-definitions   --from-file=platform/infrastructure/messaging/rabbitmq/definitions.json  -n $(NS) --dry-run=client -o yaml | $(K) apply -f -
	$(K) create configmap redis-conf             --from-file=platform/infrastructure/databases/redis/redis.conf           -n $(NS) --dry-run=client -o yaml | $(K) apply -f -

# StatefulSet databases + license-checker + web-portal + init jobs. The *.tpl ingress
# is skipped here (kubectl ignores non-.yaml); it is applied by `make frontend`.
# (A real LICENSE_KEY secret `bankobs-license` is needed only by license-checker:
#   kubectl -n bankobs create secret generic bankobs-license --from-literal=LICENSE_KEY=... )
platform: namespace configmaps
	$(K) apply -n $(NS) -f platform/

# Fire each chart in sequence; do NOT wait for pods (helm returns once resources are applied).
services: namespace
	@for s in $(SERVICES); do \
	  echo "  → $$s"; \
	  helm --kube-context $(CTX) upgrade --install $$s ./$$s -n $(NS) \
	    --set image.registry=$(ECR) --set image.tag=$(TAG) >/dev/null || exit 1; \
	done
	@echo "  ✓ $(words $(SERVICES)) service charts applied."

frontend:
	@test -n "$(DOMAIN)" || { echo "ERROR: set DOMAIN=lab.example.com"; exit 1; }
	@sed 's|$${DOMAIN}|$(DOMAIN)|g' platform/web-portal-ingress.yaml.tpl | $(K) apply -f -
	@echo "  frontend (once DNS propagates): https://bankobs.$(DOMAIN)"

list:
	@echo $(SERVICES) | tr ' ' '\n'

regen:
	bash _generate.sh

destroy:
	-@for s in $(SERVICES); do helm --kube-context $(CTX) uninstall $$s -n $(NS) 2>/dev/null; done
	-$(K) delete -n $(NS) -f platform/ --ignore-not-found
	@echo "  ✓ BankObs removed (PVCs kept)."
