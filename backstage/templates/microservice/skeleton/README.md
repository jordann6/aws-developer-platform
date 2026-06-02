# ${{ values.name }}

${{ values.description }}

Owned by **${{ values.owner }}**. Scaffolded from the platform golden-path template.

## What you get out of the box

- A minimal HTTP service (`index.js`) with a `/healthz` endpoint
- A `Dockerfile` for containerization
- A Helm chart under `helm/` (Deployment + Service, non-root, health-probed)
- An ArgoCD `Application` under `argocd/` so the service deploys via GitOps

## Deploy

The platform's ArgoCD picks up `argocd/application.yaml`, which renders the Helm
chart. Build and push the image to your registry, set `image.repository` in
`helm/values.yaml`, and commit.
