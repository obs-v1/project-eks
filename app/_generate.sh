#!/usr/bin/env bash
# Generates one self-contained Helm chart folder per bankobs microservice:
#   <svc>/{Chart.yaml, values.yaml, Dockerfile, Makefile, templates/{deployment,service}.yaml}
#
# There is NO service source here. The Dockerfile is a passthrough `FROM` the published
# image, so a student can rebuild, push to THEIR OWN registry and run their own CI/CD —
# the real source stays private. Re-run any time; it is idempotent.
set -euo pipefail
cd "$(dirname "$0")"

REGISTRY_DEFAULT="public.ecr.aws/w8x4g9h7/obs-v1"
TAG_DEFAULT="1.0.0"
OTEL_ENDPOINT="http://otel-collector.obs.internal:4317"   # private, cross-VPC (obs cluster)

# svc|domain|port  — fault-injector ships dormant (replicas 0), armed by scaling to 1.
SERVICES="
aadhaar-adapter|customer-identity|8032
account-service|core-banking|8001
aml-service|fraud-risk|8042
audit-service|audit-compliance|8060
auth-service|core-banking|8080
balance-service|core-banking|8003
bharat-qr-service|payments|8016
branch-service|core-banking|8007
case-management|fraud-risk|8045
cbs-adapter|core-banking|8008
cersai-adapter|audit-compliance|8063
cheque-service|core-banking|8006
ckyc-service|customer-identity|8034
compliance-checker|audit-compliance|8064
consent-service|customer-identity|8036
credit-card-service|retail-banking|8024
demat-service|retail-banking|8026
eligibility-engine|retail-banking|8028
email-service|notifications|8052
fault-injector|fault-injector|8000
fd-service|retail-banking|8022
fraud-detection|fraud-risk|8040
fx-service|payments|8017
gateway-service|core-banking|8000
ibm-mq-bridge|legacy-stack|8072
identity-vault|customer-identity|8035
imps-service|payments|8014
insurance-service|retail-banking|8025
interest-engine|core-banking|8005
kyc-service|customer-identity|8030
ledger-service|core-banking|8002
loan-origination|retail-banking|8021
loan-service|retail-banking|8020
nach-service|payments|8015
neft-service|payments|8012
notification-orchestrator|notifications|8050
onboarding-service|customer-identity|8031
pan-adapter|customer-identity|8033
payment-gateway|payments|8010
payment-router|payments|8019
pci-logger|audit-compliance|8062
push-service|notifications|8053
rate-limiter|core-banking|8082
rbi-reporter|audit-compliance|8061
rd-service|retail-banking|8023
remittance-service|payments|8018
report-generator|audit-compliance|8065
risk-scoring|fraud-risk|8044
rtgs-service|payments|8013
rules-engine|fraud-risk|8041
sanctions-service|fraud-risk|8043
sms-gateway|notifications|8051
statement-service|core-banking|8004
tomcat-loan-legacy|legacy-stack|8071
transaction-monitor|fraud-risk|8046
upi-service|payments|8011
velocity-checker|fraud-risk|8047
wealth-service|retail-banking|8027
weblogic-cbs-simulator|legacy-stack|8070
whatsapp-service|notifications|8054
"

gen() {
  local svc=$1 domain=$2 port=$3 replicas=$4
  mkdir -p "$svc/templates"

  cat > "$svc/Chart.yaml" <<EOF
apiVersion: v2
name: $svc
description: bankobs microservice $svc ($domain domain)
type: application
version: 1.0.0
appVersion: "$TAG_DEFAULT"
EOF

  cat > "$svc/values.yaml" <<EOF
replicaCount: $replicas
image:
  registry: $REGISTRY_DEFAULT   # override with YOUR ECR (make deploy ECR=...) to run your own build
  tag: "$TAG_DEFAULT"
  pullPolicy: IfNotPresent
service:
  port: $port
domain: $domain
otel:
  endpoint: $OTEL_ENDPOINT
observabilityMode: full
resources:
  requests: { cpu: 100m, memory: 128Mi }
  limits:   { cpu: 500m, memory: 512Mi }
EOF

  cat > "$svc/Dockerfile" <<EOF
# Passthrough image — NO source here. This re-tags the published bankobs image so you
# can push it to YOUR registry and run your own CI/CD, keeping the real source private.
#   make build ECR=<your-ecr>  &&  make push ECR=<your-ecr>
FROM $REGISTRY_DEFAULT/$svc:$TAG_DEFAULT
EOF

  cat > "$svc/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Chart.Name }}
  labels: { app: {{ .Chart.Name }}, domain: {{ .Values.domain }}, log_format: json }
spec:
  replicas: {{ .Values.replicaCount }}
  selector: { matchLabels: { app: {{ .Chart.Name }} } }
  template:
    metadata:
      labels: { app: {{ .Chart.Name }}, domain: {{ .Values.domain }}, log_format: json }
      # The bankobs-cluster collector agent discovers /metrics via these annotations.
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/metrics"
        prometheus.io/port: {{ .Values.service.port | quote }}
    spec:
      # Stop k8s injecting REDIS_PORT=tcp://ip:6379 etc. (service links), which clobbers
      # the apps' ${REDIS_PORT:6379}-style config and breaks Spring/boot startup.
      enableServiceLinks: false
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.registry }}/{{ .Chart.Name }}:{{ .Values.image.tag }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports: [{ containerPort: {{ .Values.service.port }} }]
          # Shared env: DB creds, auth secrets, and the full-observability telemetry flags.
          envFrom:
            - configMapRef: { name: bankobs-env }
          env:
            - { name: SERVICE_NAME, value: {{ .Chart.Name | quote }} }
            - { name: SERVICE_PORT, value: {{ .Values.service.port | quote }} }
          livenessProbe:  { httpGet: { path: /health/live,  port: {{ .Values.service.port }} }, initialDelaySeconds: 30 }
          readinessProbe: { httpGet: { path: /health/ready, port: {{ .Values.service.port }} }, initialDelaySeconds: 10 }
          resources:
{{ toYaml .Values.resources | indent 12 }}
EOF

  cat > "$svc/templates/service.yaml" <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Chart.Name }}
  labels: { app: {{ .Chart.Name }}, domain: {{ .Values.domain }} }
spec:
  selector: { app: {{ .Chart.Name }} }
  ports:
    - { name: http, port: {{ .Values.service.port }}, targetPort: {{ .Values.service.port }} }
EOF

  {
    printf 'SVC := %s\n' "$svc"
    printf 'ECR ?= %s\n' "$REGISTRY_DEFAULT"
    printf 'TAG ?= %s\n' "$TAG_DEFAULT"
    printf 'NS  ?= bankobs\n'
    printf 'CTX ?= obs-v1-bankobs\n\n'
    printf '.PHONY: build push deploy undeploy\n\n'
    printf 'build:\n\tdocker build -t $(ECR)/$(SVC):$(TAG) .\n\n'
    printf 'push:\n\tdocker push $(ECR)/$(SVC):$(TAG)\n\n'
    printf 'deploy:\n\thelm --kube-context $(CTX) upgrade --install $(SVC) . -n $(NS) --create-namespace --set image.registry=$(ECR) --set image.tag=$(TAG)\n\n'
    printf 'undeploy:\n\thelm --kube-context $(CTX) uninstall $(SVC) -n $(NS)\n'
  } > "$svc/Makefile"
}

echo "$SERVICES" | while IFS='|' read -r svc domain port; do
  [ -z "$svc" ] && continue
  replicas=1
  [ "$svc" = "fault-injector" ] && replicas=0
  gen "$svc" "$domain" "$port" "$replicas"
done
echo "generated $(echo "$SERVICES" | grep -c '|') service charts."
