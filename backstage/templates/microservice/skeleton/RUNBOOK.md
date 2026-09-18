# Runbook: ${{ values.name }}

Owner: ${{ values.owner }} | Cost centre: ${{ values.costCenter }}

Every service on this platform ships with a runbook so the first responder is
never starting from a blank page. Fill the blanks below before your first
production deploy.

## SLOs

- Availability: 99.5% non-5xx over 30 days (error budget 0.005).
- Latency: _fill in your objective, e.g. 99% under 250ms over 30 days._

Burn-rate alerts live in `slo/burn-rate.yaml`. Page-severity alerts route to the
platform incident responder (Claude summary + Slack verify/escalate, human in the
loop). See the platform runbook `docs/runbooks/incident-auto-response.md`.

## First response (contain, fix, make it permanent)

1. **Contain first.** Take the lowest-risk reversible action: hold the current
   rollout (`kubectl rollout pause`), or roll back to the last good revision
   (`kubectl rollout undo`). Do not take a destructive action without approval.
2. **Read the summary.** The responder posts a plain-language incident summary to
   Slack; start there, not in raw PromQL.
3. **Diagnose.** _List this service's top failure modes and where to look:
   dashboards, log queries, upstream dependencies._
4. **Fix.**
5. **Postmortem as a control.** The output is a permanent guardrail (a policy, a
   tightened SLO, a new alert), change-controlled, not just a wiki note.

## Dashboards and links

- Grafana: _link_
- Logs: _link_
- Upstream dependencies: _list_
