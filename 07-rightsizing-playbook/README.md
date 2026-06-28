# Rightsizing playbook

Don't guess requests/limits. Measure, then adjust.

1. **Measure** — couple weeks of metrics-server + prom. VPA in recommendation mode only (`updateMode: Off`).
2. **Analyze** — VPA target for requests, P95 + slack for limits. Scripts in `scripts/` hit prom.
3. **Test** — staging first, `validation/stress-test.yaml`, watch OOMKills and throttling.
4. **Roll out** — one pod canary, then rest. check again in a week.
5. **Revisit** — quarterly or after big traffic/code change.

Scripts:
- `analyze-resources.sh` — P50/P95/P99 from prom
- `recommend-limits.py` — spit out suggested yaml
- `vpa-analyzer.sh` — parse VPA into patches

Rough math:
```
cpu request  = p50 × 1.2
cpu limit    = p95 × 1.5
mem request  = p50 × 1.3
mem limit    = p95 × 1.3
```

OOMKill = mem limit too low. Throttling = cpu limit too tight. Pending = requests too big for nodes.
