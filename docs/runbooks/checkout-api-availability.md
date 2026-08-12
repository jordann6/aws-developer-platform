# Runbook: checkout-api availability budget burn

Linked from `CheckoutAPIAvailabilityFastBurn`, `...SlowBurn`, `...BudgetLeak`,
`...BudgetDrain`, and `CheckoutAPISLIMissing`.

## What fired and what it means

The service is returning 5xx fast enough to threaten the 30-day availability
budget (99.5% of requests non-5xx, so 0.5% of requests is the whole budget).

Severity tells you the response, not the size of the problem:

- **page** (14.4x or 6x burn): respond now. At 14.4x the month's budget is gone
  in about two days.
- **ticket** (3x or 1x burn): file it, fix it this week. Nobody gets woken up.

## First: is it the service or the monitoring?

`CheckoutAPISLIMissing` firing means there is no SLI data at all. Treat this as
an outage of the measurement, not proof of health.

```bash
kubectl -n ingress-nginx get pods
kubectl -n monitoring get servicemonitor -A | grep ingress-nginx
kubectl -n slo-demo get ingress slo-demo
```

Every SLI query filters on `ingress="slo-demo"`. Renaming that Ingress silently
empties every recording rule and every alert. If the Ingress was renamed,
that is the incident.

## Triage

```bash
# Where the errors are coming from
kubectl -n slo-demo get pods
kubectl -n slo-demo logs -l app.kubernetes.io/name=checkout-api --tail=100

# Status code breakdown at the proxy
scripts/slo-demo.sh status
scripts/slo-demo.sh alerts
```

Three common shapes:

| Symptom | Likely cause | Check |
| --- | --- | --- |
| 503 with no backend pods ready | Deployment scaled to zero, or readiness probe failing | `kubectl -n slo-demo describe deploy checkout-api` |
| 5xx from healthy pods | Application-level failure | Pod logs |
| 5xx immediately after a deploy | Bad rollout | `kubectl -n slo-demo rollout history deploy/checkout-api` |

On this demo platform there is a fourth: the load generator was deliberately
put into `errors` mode. Check it before hunting for a real fault.

```bash
kubectl -n slo-demo get configmap loadgen-config -o jsonpath='{.data.TARGET_MODE}'
```

## Mitigate

Stop the bleeding before finding root cause. The budget is being spent either
way.

```bash
# Roll back a bad deploy
kubectl -n slo-demo rollout undo deployment/checkout-api

# Restore capacity
kubectl -n slo-demo scale deployment/checkout-api --replicas=2

# Demo only: end the injected failure
scripts/slo-demo.sh heal
```

## Confirm recovery

The short window is what clears the alert. The 5m error ratio should fall below
7.2% within roughly five minutes of the fix, and the alert resolves then, even
though the 1h window is still elevated.

```bash
scripts/slo-demo.sh watch
```

If the 5m window is healthy but the alert is still firing after ten minutes,
suspect Alertmanager rather than the service.

## Afterward

Record how much budget the incident cost:

```promql
slo:error_budget_remaining:ratio{slo="checkout-api-availability"}
```

If the remaining budget is under 25%, the team stops shipping features and
spends the time on reliability until the window rolls forward. That is the
policy the budget exists to trigger; an error budget nobody ever enforces is
just a chart.
