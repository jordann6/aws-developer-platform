# Reliability: SLIs, SLOs, and error budgets

The platform ships an opinionated reliability layer alongside the paved road.
A team that deploys through the golden path gets availability and latency
objectives, burn-rate alerting, a dashboard, and a runbook without writing a
single PromQL query.

`checkout-api` is the reference service the objectives are written against.

## The objectives

| SLO | Objective | Window | Error budget |
| --- | --- | --- | --- |
| Availability | 99.5% of requests do not return 5xx | 30 days rolling | 0.5% of requests |
| Latency | 99% of requests complete in under 250ms | 30 days rolling | 1% of requests |

Two decisions worth stating outright.

**Measured at the proxy, not in the app.** Both SLIs come from ingress-nginx
metrics. An application that is crash-looping reports nothing, and an SLI that
goes quiet during an outage is worse than no SLI at all, because it looks like
success. The proxy keeps counting when the backend is on fire.

**250ms, not 300ms.** The latency SLI reads a histogram bucket boundary
(`le="0.25"`), and 0.25s is a real ingress-nginx bucket edge. An objective set
between edges can only be reached by interpolation, and an interpolated SLO is
an estimate being reported as a fact. The objective was moved to the data
rather than the data being bent to the objective.

## Why burn rate instead of a threshold

A static "alert if errors > 1%" does both wrong things at once. It pages on a
90-second blip that costs a rounding error of budget, and it stays silent
through a 0.9% leak that quietly spends the entire month.

Burn rate asks a better question: at the current error rate, how fast is the
30-day budget being consumed? Burn rate 1 exhausts the budget exactly at the
end of the window. Burn rate 14.4 exhausts it in about 50 hours, which means 2%
of the month's budget is gone in the first hour.

Each alert pairs a long window with a short one. The long window establishes
that the problem is real; the short window confirms it is still happening, so
the alert clears promptly after recovery instead of hanging on for hours.

| Burn rate | Long window | Short window | Budget consumed | Severity |
| --- | --- | --- | --- | --- |
| 14.4x | 1h | 5m | 2% in an hour | page |
| 6x | 6h | 30m | 5% in six hours | page |
| 3x | 1d | 2h | 10% in a day | ticket |
| 1x | 3d | 6h | 10% in three days | ticket |

There is a fifth alert, `CheckoutAPISLIMissing`, that fires when the SLI stops
producing samples at all. Every burn-rate expression above evaluates to empty
if the ingress stops exporting metrics, and empty expressions do not fire. Left
alone, a broken exporter looks exactly like a perfectly healthy service.

## How it is wired

| Piece | Path | Role |
| --- | --- | --- |
| Metrics stack | `platform/argocd/apps/kube-prometheus-stack.yaml` | Prometheus, Alertmanager, Grafana |
| Measurement point | `platform/argocd/apps/ingress-nginx.yaml` | Exports the request and latency metrics the SLIs read |
| Measured service | `platform/slo/workload/` | `checkout-api` plus an in-cluster load generator |
| SLI definitions | `platform/slo/rules/00-sli-recording-rules.yaml` | One recording rule per SLI per alert window |
| Alerts | `platform/slo/rules/10-burn-rate-alerts.yaml` | Multi-window multi-burn-rate rules |
| Dashboard | `platform/slo/rules/20-grafana-dashboard.yaml` | ConfigMap imported by the Grafana sidecar |
| Tests | `platform/slo/tests/` | promtool unit tests for the rules, run in CI |
| Runbooks | `docs/runbooks/` | Linked from every alert's `runbook_url` |

Every alert window is precomputed as a recording rule rather than inlined into
alert expressions. That keeps the alerts readable, and it guarantees the
dashboard and the pager are reading the identical number. "The dashboard says
we are fine" is not a conversation worth having at 3am.

The dashboard is a ConfigMap under GitOps, so a panel edited by hand in the
Grafana UI is reverted on the next ArgoCD sync. Dashboards are code here.

## The rules are tested

Untested alerting rules fail in the worst way available: silently, during the
incident they were written for. `platform/slo/tests/burn-rate-tests.yaml` feeds
synthetic ingress metrics through the real rule files and asserts on what
fires. No cluster needed, and it runs on every pull request that touches
`platform/slo/`.

```bash
brew install prometheus   # for promtool
scripts/slo-test.sh
```

Five cases, chosen because each one is a way this design could be wrong:

- **10% errors** pages on fast burn, and trips the slow-burn window too.
- **0.4% errors**, just under the budget, fires nothing. A static 0.1%
  threshold would have paged here for a service that is meeting its SLO.
- **Zero errors** records an SLI of exactly 0, not an empty result. This is the
  test that would catch someone removing `or on() vector(0)`.
- **20% of requests over 250ms, all returning 200** pages on latency while
  availability stays silent. This is the case that justifies two SLIs.
- **No metrics at all** fires `CheckoutAPISLIMissing` and nothing else,
  confirming that a dead exporter does not read as a healthy service.

## The demo

`scripts/slo-demo.sh` drives a full incident cycle. The load generator's mode
lives in a ConfigMap; flipping it makes the service genuinely fail, and every
layer downstream reacts on its own.

```bash
scripts/slo-demo.sh status         # healthy: SLI ~1.0, burn rate ~0
scripts/slo-demo.sh break errors   # checkout-api starts returning 503s
scripts/slo-demo.sh watch          # burn rate climbs past 14.4x, alert fires
scripts/slo-demo.sh heal           # traffic returns to normal
scripts/slo-demo.sh watch          # 5m window recovers first, alert resolves
```

Expected timing at roughly 20 requests per second:

- **t+0** mode flips, loadgen restarts
- **t+1m** the 5m error ratio crosses 7.2% (14.4 x 0.005)
- **t+2m** the 1h window crosses too, alert enters pending
- **t+3-4m** `CheckoutAPIAvailabilityFastBurn` fires
- after `heal`, the 5m window drops within about five minutes and the `and`
  clears the alert, even though the 1h window is still elevated. That is the
  short window doing its job.

`break slow` exercises the latency SLO instead: the service returns HTTP 200
the whole time, so availability alerts stay silent and only the latency budget
burns. Two SLIs exist precisely because one of them cannot see that failure.

## Cost and teardown

This layer adds no billable AWS resources of its own. It runs on the existing
node group, and both ingress-nginx and Grafana are `ClusterIP`, reached by
`kubectl port-forward`. Exposing either would provision an NLB at roughly $16
a month on a platform meant to be destroyed the same day.

Prometheus storage is deliberately ephemeral, with 4 days of retention on an
`emptyDir`. A PVC here would outlive `terraform destroy` and leave an orphaned
EBS volume billing quietly after the cluster is gone. The tradeoff is real and
accepted: restarting the Prometheus pod loses history, and on a permanent
cluster this would be a PVC with a documented deletion step. Verify the claim
rather than trusting it:

```bash
scripts/slo-demo.sh orphan-check
```

The 30-day compliance window also cannot be honestly reported on a cluster that
lives for an afternoon. The 30d recording rules exist so the dashboard and the
alert thresholds share one definition of the budget, but on a fresh cluster
they read as "budget spent so far", not as a real monthly figure.
