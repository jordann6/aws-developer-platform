#!/usr/bin/env bash
#
# Runs the burn-rate alert unit tests. No cluster required.
#
# The rules ship as PrometheusRule CRDs, which promtool cannot read directly,
# so their .spec is extracted to a gitignored .slo-test/ directory first. That
# is the only reason this script exists rather than a bare promtool invocation.
#
# Requires promtool (brew install prometheus).
set -euo pipefail

cd "$(dirname "$0")/.."

command -v promtool >/dev/null 2>&1 || {
  echo "promtool not found. Install with: brew install prometheus" >&2
  exit 1
}

mkdir -p .slo-test

python3 - <<'PY'
import yaml

for src, out in [
    ("platform/slo/rules/00-sli-recording-rules.yaml", ".slo-test/rec.rules.yaml"),
    ("platform/slo/rules/10-burn-rate-alerts.yaml", ".slo-test/alerts.rules.yaml"),
]:
    with open(src) as fh:
        spec = yaml.safe_load(fh)["spec"]
    with open(out, "w") as fh:
        yaml.safe_dump(spec, fh, default_flow_style=False, sort_keys=False)
PY

promtool check rules .slo-test/rec.rules.yaml .slo-test/alerts.rules.yaml
promtool test rules platform/slo/tests/burn-rate-tests.yaml
