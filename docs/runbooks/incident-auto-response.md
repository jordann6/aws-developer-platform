# Runbook: automated incident response for burn-rate pages

## What fires this

The SLO burn-rate rules in `platform/slo/rules/10-burn-rate-alerts.yaml` raise
`severity: page` alerts on a fast (14.4x) or medium (6x) burn of the checkout-api
error budget. Alertmanager routes those to the `incident-responder` receiver
(configured in `platform/argocd/apps/kube-prometheus-stack.yaml`) rather than to
the null receiver that swallows ticket-severity noise.

## The loop (contain, fix, make it permanent)

This platform routes the page; the responder itself is the `aws-incident-responder`
project, wired as the webhook target. The loop is deliberately the same one used
across the incident-response builds:

1. **Detect.** Prometheus evaluates the multi-window burn-rate expression;
   Alertmanager groups and forwards the page to the responder webhook.
2. **Summarize.** The responder calls Claude (Haiku) to turn the raw alert plus
   recent metrics into a plain-language incident summary, so the first human to
   look is not reading PromQL at 2am.
3. **Triage / contain.** A deterministic runbook step takes the low-risk,
   reversible action first (for example, hold a rollout or scale a replica),
   never a destructive one without approval.
4. **Escalate with a human in the loop.** A Slack verify/escalate message goes
   out; a person confirms or escalates. The model never self-approves a
   destructive action, the same guardrail as the golden-path copilot's cleanup
   PRs.
5. **Resolve.** `send_resolved: true` means the responder also learns when the
   burn stops, so the incident closes instead of hanging open.

## The postmortem is a control, not a wiki page

The output of the postmortem is a permanent guardrail: a new Kyverno policy, a
tightened SLO, a new burn-rate rule, or an Infracost/OPA gate. In a GxP + SOC 2
environment the postmortem and its fix are themselves change-controlled and
evidenced (SOC 2 CC8.1). The failure is not closed until the class of failure
cannot recur on the paved road.

## Arming it

The receiver URL is an in-cluster placeholder by default so a fresh deploy never
pages a live endpoint. To arm:

- set the `incident-responder` webhook URL to the responder's ingest endpoint
  (or an Alertmanager-to-Slack bridge), and
- confirm the responder has its Slack and Bedrock credentials.

Until then, pages are visible in Alertmanager and the routing is proven; no
external side effects fire.
