# ADR-0001: Alert on error-budget burn rate, not on static error thresholds

- **Status:** accepted
- **Date:** 2026-08-04

## Context

The platform had no reliability signal. Services deployed through the golden
path shipped with admission policy and GitOps reconciliation but no definition
of what "working" meant, so the first question during any incident was whether
there was an incident.

Constraints that actually bind here:

- **On-call capacity is one person.** Every page has to be worth waking up for.
  A noisy alert is not a minor annoyance, it is the mechanism by which real
  pages get ignored.
- **The cluster is deploy/demo/destroy.** It lives for hours, not months, and
  costs are watched closely. Anything that provisions a load balancer or an EBS
  volume per component is out.
- **Nothing may outlive `terraform destroy`.** Orphaned resources that keep
  billing after teardown are the failure mode this platform is built to avoid.
- **Application teams do not write PromQL.** Whatever is chosen has to arrive
  with the paved road, not as homework.

## Decision

Define two SLIs per service, measured at the ingress proxy, and alert on
multi-window multi-burn-rate error-budget consumption (Google SRE Workbook
chapter 5) rather than on static error-rate thresholds.

## Alternatives rejected

| Option | Why not |
| ------ | ------- |
| Static threshold, e.g. "page if 5xx rate > 1% for 5m" | Simplest possible option, and the one this replaces. It fails in both directions: it pages on a 90-second blip costing a rounding error of budget, and it never fires on a 0.9% leak that spends the entire month. The threshold encodes no notion of how much unreliability is affordable. |
| Single-window burn rate (long window only) | Fixes the sensitivity problem but not the recovery problem. An alert on a 1h window keeps firing for up to an hour after the fix lands, which trains people to ignore it and to close incidents on a stopwatch instead of on a signal. |
| Availability SLI only | Cheaper, and covers hard failure well. It is blind to the most common real degradation: the service returns 200 for everything and takes two seconds to do it. A latency SLO is what makes that page. |
| Instrument the application, not the proxy | More precise attribution, but a crash-looping app reports no metrics, and an SLI that goes silent during an outage reads as success. The proxy keeps counting when the backend is down. |
| Managed AMP plus AMG instead of self-hosted | Removes the operational burden and survives cluster teardown. It also adds a per-workspace monthly cost to a cluster meant to exist for an afternoon, and it hides the mechanics this platform exists to demonstrate. Worth revisiting for a permanent environment. |

## Consequences

**Committed to:** four alerts per SLO instead of one, and a recording rule per
SLI per window. That is seven windows x two SLIs of boilerplate, and it grows
linearly with every SLO added. The next service onboarded by copy-paste is the
signal to templatize this into the Backstage golden path or generate it with
Sloth, rather than hand-maintaining a third copy.

**Made harder:** the latency objective is pinned to a histogram bucket edge
(250ms, because 0.25 is a default ingress-nginx bucket). Changing it to a round
number that is not an edge means reconfiguring the controller's buckets or
accepting interpolated numbers in the thing that pages a human.

**Accepted tradeoff:** Prometheus runs on an `emptyDir` with 4 days of
retention, so a pod restart loses history and the 30-day compliance window
cannot be honestly reported on a short-lived cluster. This is the price of
guaranteeing that teardown leaves nothing behind. On a permanent cluster this
becomes a PVC with a documented deletion step, or remote write to a durable
store.

**Revisit when:** a third service needs SLOs (templatize), or the cluster
becomes long-lived (durable storage, real 30-day windows, and a real
Alertmanager receiver instead of the null route in place today).
