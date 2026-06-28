# k8s optimization suite

Manifests from tuning a few clusters — autoscaling, spot, rightsizing. Numbered folders roughly match the order I'd apply changes.

- `01-deployments/` — base app yaml, requests/limits set
- `02-autoscaling/` — HPA v2, KEDA (kafka, sqs, cron, prom)
- `03-cost-optimization/` — spot vs on-demand, priority classes
- `04-multi-region/` — route53 latency, per-region overlays
- `05-gitops/` — argocd + flux samples
- `06-observability/` — prom rules, grafana dashboards
- `07-rightsizing-playbook/` — how I actually pick CPU/mem values
- `docs/` — longer notes on arch and DR

If you're here for rightsizing, start at 07.
