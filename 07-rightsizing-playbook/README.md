# Rightsizing playbook

How I tune Kubernetes requests and limits — measure first, don't guess.

## Process

1. **Measure** (2–4 weeks) — Metrics Server + Prometheus for history, VPA in recommendation mode (`updateMode: Off`)
2. **Analyze** — VPA targets for requests, P95 + headroom for limits. Scripts in `scripts/` wrap the Prometheus queries.
3. **Test** — Apply in staging, run `validation/stress-test.yaml`, watch for OOMKills and CPU throttling
4. **Roll out** — Canary one pod, then full deployment. Re-check after a week.
5. **Iterate** — Re-run quarterly or after major traffic/code changes

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/analyze-resources.sh` | Pull usage from Prometheus, print P50/P95/P99 |
| `scripts/recommend-limits.py` | Generate request/limit suggestions from history |
| `scripts/vpa-analyzer.sh` | Parse VPA output into patch-ready YAML |

## Rules of thumb

```
CPU request  = P50 × 1.2
CPU limit    = P95 × 1.5
Memory request = P50 × 1.3
Memory limit   = P95 × 1.3
```

Memory limits matter more than CPU — OOMKills are hard failures, CPU just throttles.

## Common fixes

- **OOMKilled** — memory limit too low; check `kubectl top pods`, bump limit ~50%
- **CPU throttling** — limit too tight; raise limit or drop it for bursty workloads
- **Pending pods** — requests too high for available nodes; right-size down or add capacity
- **Low utilization** — requests oversized; run analysis and test lower values in staging

More detail: [Kubernetes resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
