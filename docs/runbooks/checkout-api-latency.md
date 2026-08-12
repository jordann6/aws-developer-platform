# Runbook: checkout-api latency budget burn

Linked from `CheckoutAPILatencyFastBurn`, `...SlowBurn`, and `...BudgetLeak`.

## What fired and what it means

More than the budgeted share of requests are taking longer than 250ms. The
objective is that 99% of requests complete under 250ms over 30 days, so 1% of
requests is the entire budget.

Important: the service is almost certainly **up**. Every one of these requests
returned a 2xx. The availability alerts will stay silent through this, which is
why latency is a separate SLI rather than a footnote on the availability one.

## Triage

```bash
scripts/slo-demo.sh status
```

Then look at the latency percentile panel on the `SLO: checkout-api` dashboard
(`scripts/slo-demo.sh grafana`). The shape narrows the cause quickly:

| Shape | Likely cause |
| --- | --- |
| p50 flat, p99 spiking | A slow dependency on some requests, or GC pauses |
| All percentiles up together | Saturation: CPU throttling, or too few replicas for the traffic |
| Step change at a deploy | A regression that shipped |

```bash
# Saturation check
kubectl -n slo-demo top pods
kubectl -n slo-demo describe pod -l app.kubernetes.io/name=checkout-api | grep -A5 Limits

# Recent rollouts
kubectl -n slo-demo rollout history deployment/checkout-api
```

CPU throttling is the usual answer when everything moves together. The
container requests 50m, and a request-sized burst hits the limit long before
anything looks unhealthy.

Demo platform: check whether the failure was injected before investigating a
real one.

```bash
kubectl -n slo-demo get configmap loadgen-config -o jsonpath='{.data.TARGET_MODE}'
# "slow" means the loadgen is calling /delay/0.6 on purpose
```

## Mitigate

```bash
# Add capacity
kubectl -n slo-demo scale deployment/checkout-api --replicas=4

# Roll back a regression
kubectl -n slo-demo rollout undo deployment/checkout-api

# Demo only
scripts/slo-demo.sh heal
```

## A note on the threshold

The SLI counts requests in the `le="0.25"` histogram bucket, which is a real
ingress-nginx bucket edge. If someone proposes changing the objective to 300ms,
that is not a one-line edit: 0.3 is not a bucket boundary, and the SLI would
have to switch to interpolation or the controller's buckets would have to be
reconfigured with `--time-buckets`. Interpolated numbers should not be the
thing that pages a human.

## Afterward

```promql
slo:error_budget_remaining:ratio{slo="checkout-api-latency"}
```

Latency budget and availability budget are tracked separately and enforced
separately. Spending the latency budget does not license spending the
availability one.
