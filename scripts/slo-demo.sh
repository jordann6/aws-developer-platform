#!/usr/bin/env bash
#
# Drives the error-budget demo end to end: inject a failure, watch the burn
# rate climb, watch the alert fire, recover, watch it resolve.
#
# Everything here talks to the cluster through kubectl. There is no LoadBalancer
# anywhere in the observability stack, so Grafana, Prometheus and Alertmanager
# are reached by port-forward.
#
# Usage:
#   scripts/slo-demo.sh status          current SLI, burn rate, budget
#   scripts/slo-demo.sh break errors    serve 503s (availability SLO)
#   scripts/slo-demo.sh break slow      serve 600ms responses (latency SLO)
#   scripts/slo-demo.sh heal            back to healthy traffic
#   scripts/slo-demo.sh watch           poll burn rate and firing alerts
#   scripts/slo-demo.sh alerts          list firing SLO alerts
#   scripts/slo-demo.sh grafana         port-forward Grafana on :3000
#   scripts/slo-demo.sh orphan-check    confirm nothing survives teardown
set -euo pipefail

NS_APP="slo-demo"
NS_MON="monitoring"
PROM_SVC="svc/kube-prometheus-stack-prometheus"
LOCAL_PORT="19090"

die() { echo "error: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is required but not on PATH"; }

need kubectl
need curl
need python3

# Runs a PromQL instant query through a short-lived port-forward, so reading a
# number does not require exposing Prometheus to the internet.
promql() {
  local query="$1" pf_pid rc=0
  kubectl -n "$NS_MON" port-forward "$PROM_SVC" "${LOCAL_PORT}:9090" >/dev/null 2>&1 &
  pf_pid=$!
  for _ in $(seq 1 40); do
    curl -sf "http://127.0.0.1:${LOCAL_PORT}/-/ready" >/dev/null 2>&1 && break
    sleep 0.5
  done
  curl -sG "http://127.0.0.1:${LOCAL_PORT}/api/v1/query" \
    --data-urlencode "query=${query}" || rc=$?
  kill "$pf_pid" 2>/dev/null || true
  wait "$pf_pid" 2>/dev/null || true
  return "$rc"
}

# First sample value, or "n/a" when the series does not exist yet. A fresh
# cluster has no data for the longer windows, and "n/a" is the honest answer
# there rather than zero.
value_of() {
  python3 -c 'import json,sys
try:
    res = json.load(sys.stdin).get("data", {}).get("result", [])
    print("%.4f" % float(res[0]["value"][1]) if res else "n/a")
except Exception:
    print("n/a")'
}

set_mode() {
  local mode="$1"
  kubectl -n "$NS_APP" patch configmap loadgen-config \
    --type merge -p "{\"data\":{\"TARGET_MODE\":\"${mode}\"}}" >/dev/null
  # The mode is read into an env var at container start, so it only takes
  # effect on a restart. An explicit rollout beats waiting on kubelet's
  # ConfigMap propagation, which can lag by a minute.
  kubectl -n "$NS_APP" rollout restart deployment/loadgen >/dev/null
  kubectl -n "$NS_APP" rollout status deployment/loadgen --timeout=120s >/dev/null
  echo "loadgen mode: ${mode}"
}

cmd_status() {
  local mode avail lat burn budget
  mode=$(kubectl -n "$NS_APP" get configmap loadgen-config -o jsonpath='{.data.TARGET_MODE}')
  avail=$(promql '1 - slo:availability_errors:ratio_rate5m{slo="checkout-api-availability"}' | value_of)
  lat=$(promql '1 - slo:latency_errors:ratio_rate5m{slo="checkout-api-latency"}' | value_of)
  burn=$(promql 'slo:availability_errors:ratio_rate5m{slo="checkout-api-availability"} / 0.005' | value_of)
  budget=$(promql 'slo:error_budget_remaining:ratio{slo="checkout-api-availability"}' | value_of)

  printf '\n  loadgen mode          %s\n' "$mode"
  printf '  availability SLI 5m   %s   (objective 0.9950)\n' "$avail"
  printf '  latency SLI 5m        %s   (objective 0.9900)\n' "$lat"
  printf '  availability burn 5m  %sx  (pages at 14.4x)\n' "$burn"
  printf '  budget remaining      %s\n\n' "$budget"
}

cmd_alerts() {
  promql 'ALERTS{alertstate="firing", slo=~"checkout-api.*"}' | python3 -c 'import json,sys
res = json.load(sys.stdin).get("data", {}).get("result", [])
if not res:
    print("  (no SLO alerts firing)")
for s in res:
    m = s["metric"]
    print("  %-8s %s" % (m.get("severity", "?"), m.get("alertname", "?")))'
  echo
}

cmd_watch() {
  echo "watching burn rate and firing alerts, ctrl-c to stop"
  while true; do
    cmd_status
    cmd_alerts
    sleep 30
  done
}

# The observability stack is deliberately PVC-free so `terraform destroy` does
# not strand EBS volumes. This verifies that claim rather than trusting it.
cmd_orphan_check() {
  local count
  count=$(kubectl -n "$NS_MON" get pvc --no-headers 2>/dev/null | wc -l | tr -d ' ')
  if [ "${count:-0}" = "0" ]; then
    echo "no PVCs in ${NS_MON}: nothing in the observability stack survives cluster teardown"
  else
    kubectl -n "$NS_MON" get pvc
    echo
    echo "${count} PVC(s) found. Delete them before terraform destroy, or the backing"
    echo "EBS volumes are orphaned and keep billing after the cluster is gone."
  fi
}

case "${1:-status}" in
  status)  cmd_status ;;
  alerts)  cmd_alerts ;;
  watch)   cmd_watch ;;
  heal)    set_mode healthy ;;
  break)
    case "${2:-errors}" in
      errors) set_mode errors ;;
      slow)   set_mode slow ;;
      *)      die "break takes 'errors' or 'slow'" ;;
    esac
    echo "fast burn should page within about 3 minutes: scripts/slo-demo.sh watch"
    ;;
  grafana)
    echo "Grafana on http://localhost:3000  (admin / prom-operator)"
    kubectl -n "$NS_MON" port-forward svc/kube-prometheus-stack-grafana 3000:80
    ;;
  prometheus)
    echo "Prometheus on http://localhost:9090"
    kubectl -n "$NS_MON" port-forward "$PROM_SVC" 9090:9090
    ;;
  orphan-check) cmd_orphan_check ;;
  *) die "unknown command: ${1}" ;;
esac
