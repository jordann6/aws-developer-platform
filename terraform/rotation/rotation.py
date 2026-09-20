"""Secrets Manager rotation Lambda for the platform's paved-road secrets.

External Secrets distributes a secret into the cluster; this closes the other
half of the loop by rotating it on a schedule. Secrets Manager invokes this
function four times per rotation, once per Step, passing a ClientRequestToken
that names the new version:

  createSecret  stage a new AWSPENDING version with a fresh password
  setSecret     change the credential in the backing service
  testSecret    prove the new credential works
  finishSecret  promote AWSPENDING to AWSCURRENT, demote old to AWSPREVIOUS

The demo secret is a JSON {"username", "password"} with no external database
behind it, so createSecret rotates the password and keeps the username,
setSecret is a no-op, and testSecret checks the pending value parses and carries
a password. A secret backed by a real datastore would do the credential change
in setSecret; the four-step contract and the staging moves stay identical.
"""

import json
import logging

import boto3

log = logging.getLogger()
log.setLevel(logging.INFO)

PENDING = "AWSPENDING"
CURRENT = "AWSCURRENT"
PASSWORD_LENGTH = 32


def _new_pending_value(client, current_string):
    try:
        current = json.loads(current_string) if current_string else {}
    except json.JSONDecodeError:
        current = {}
    new_password = client.get_random_password(
        PasswordLength=PASSWORD_LENGTH, ExcludePunctuation=True)["RandomPassword"]
    current["password"] = new_password
    return json.dumps(current)


def create_secret(client, arn, token):
    stages = client.describe_secret(SecretId=arn).get("VersionIdsToStages", {})
    if token in stages and PENDING in stages[token]:
        log.info("createSecret: AWSPENDING already staged for %s", token)
        return
    current = client.get_secret_value(SecretId=arn, VersionStage=CURRENT)
    pending = _new_pending_value(client, current.get("SecretString"))
    client.put_secret_value(
        SecretId=arn, ClientRequestToken=token,
        SecretString=pending, VersionStages=[PENDING])
    log.info("createSecret: staged AWSPENDING version %s", token)


def set_secret(client, arn, token):
    # No external datastore behind the demo secret. A DB-backed secret would
    # apply the pending password to the service here before testSecret runs.
    log.info("setSecret: no external service to update for %s", arn)


def test_secret(client, arn, token):
    pending = client.get_secret_value(
        SecretId=arn, VersionId=token, VersionStage=PENDING)
    parsed = json.loads(pending["SecretString"])
    if not parsed.get("password"):
        raise ValueError("pending secret has no password; refusing to finish")
    log.info("testSecret: pending value parses and carries a password")


def finish_secret(client, arn, token):
    stages = client.describe_secret(SecretId=arn).get("VersionIdsToStages", {})
    current_version = next(
        (v for v, labels in stages.items() if CURRENT in labels), None)
    if current_version == token:
        log.info("finishSecret: %s already AWSCURRENT", token)
        return
    client.update_secret_version_stage(
        SecretId=arn, VersionStage=CURRENT,
        MoveToVersionId=token, RemoveFromVersionId=current_version)
    log.info("finishSecret: promoted %s to AWSCURRENT (was %s)",
             token, current_version)


_STEPS = {
    "createSecret": create_secret,
    "setSecret": set_secret,
    "testSecret": test_secret,
    "finishSecret": finish_secret,
}


def handler(event, context):
    arn = event["SecretId"]
    token = event["ClientRequestToken"]
    step = event["Step"]
    log.info("rotation step %s for %s", step, arn)
    client = boto3.client("secretsmanager")
    meta = client.describe_secret(SecretId=arn)
    if not meta.get("RotationEnabled", False):
        log.warning("rotation not enabled on %s", arn)
    handler_fn = _STEPS.get(step)
    if not handler_fn:
        raise ValueError(f"unknown rotation step {step!r}")
    handler_fn(client, arn, token)
    return {"status": "ok", "step": step}
