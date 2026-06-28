# Kubernetes optimization suite

Manifests and notes from tuning K8s clusters — autoscaling, spot nodes, rightsizing, multi-region patterns. Collected over a few client projects, not a product.

## What's here

| Folder | Topic |
|--------|-------|
| [01-deployments/](01-deployments/) | Deployments, services, ingress, PDBs with resource limits |
| [02-autoscaling/](02-autoscaling/) | HPA v2, KEDA scalers (Kafka, SQS, cron, Prometheus) |
| [03-cost-optimization/](03-cost-optimization/) | Spot vs on-demand pools, priority classes, descheduler |
| [04-multi-region/](04-multi-region/) | Route53 latency routing, regional overlays |
| [05-gitops/](05-gitops/) | ArgoCD and Flux examples |
| [06-observability/](06-observability/) | Prometheus rules, Grafana dashboards, Alertmanager |
| [07-rightsizing-playbook/](07-rightsizing-playbook/) | Measure → analyze → test → roll out |
| [docs/](docs/) | Architecture, cost notes, DR, troubleshooting |

## Quick start

```bash
kubectl apply -f 01-deployments/
kubectl apply -f 02-autoscaling/hpa-v2.yaml
```

See [07-rightsizing-playbook/](07-rightsizing-playbook/) for how I approach requests and limits.

**Mamoon Idrees** · [LinkedIn](https://www.linkedin.com/in/mamoon-idrees) · mamoon.idrees5@gmail.com
