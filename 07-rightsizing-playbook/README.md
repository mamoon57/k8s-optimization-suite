# Resource Right-Sizing Playbook

## 📊 Overview

This playbook provides a systematic approach to optimizing Kubernetes resource requests and limits based on actual usage data. Proper resource sizing is critical for:

- **Cost reduction**: Eliminate waste from over-provisioning
- **Performance**: Prevent OOMKilled pods and CPU throttling
- **Cluster efficiency**: Improve bin-packing and node utilization
- **Reliability**: Right-sized resources lead to more stable applications

## 🎯 The Resource Sizing Problem

### Common Anti-Patterns

**1. Guessing Resources**
```yaml
resources:
  requests:
    cpu: 1000m      # "Seems reasonable"
    memory: 2Gi     # "Should be enough"
  limits:
    cpu: 2000m
    memory: 4Gi
```
❌ No data backing these numbers  
❌ Likely over or under-provisioned  
❌ Wastes money or causes issues

**2. Copy-Paste from Examples**
```yaml
# From some blog post
resources:
  requests:
    cpu: 100m
    memory: 128Mi
```
❌ Doesn't match YOUR workload  
❌ May cause OOMKilled or throttling

**3. Set and Forget**
```yaml
# Set 2 years ago, never updated
resources:
  requests:
    cpu: 500m
    memory: 1Gi
```
❌ Application has changed  
❌ Traffic patterns evolved  
❌ Wasting resources or constrained

## 📈 The Right-Sizing Process

### Phase 1: Measure (2-4 weeks)

**Goal**: Collect actual resource usage data

#### Step 1.1: Install Metrics Collection

```bash
# Install Metrics Server (if not present)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install Prometheus (for historical data)
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Install VPA in recommendation mode
kubectl apply -f https://github.com/kubernetes/autoscaler/releases/latest/download/vertical-pod-autoscaler.yaml
```

#### Step 1.2: Deploy VPA Recommender

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: myapp-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: myapp
  updatePolicy:
    updateMode: "Off"  # Recommendation only, no auto-update
  resourcePolicy:
    containerPolicies:
    - containerName: '*'
      minAllowed:
        cpu: 50m
        memory: 64Mi
      maxAllowed:
        cpu: 4000m
        memory: 8Gi
```

#### Step 1.3: Monitor Current Usage

```bash
# Real-time CPU/Memory usage
kubectl top pods -n production --sort-by=memory

# Watch specific pod
kubectl top pod myapp-xyz -n production --containers

# Historical data from Prometheus
# See queries in scripts/analyze-resources.sh
```

### Phase 2: Analyze (1 week)

**Goal**: Understand usage patterns and calculate recommendations

#### Step 2.1: Get VPA Recommendations

```bash
# View VPA recommendations
kubectl describe vpa myapp-vpa -n production

# Output example:
# Recommendation:
#   Container Recommendations:
#     Container Name: myapp
#     Lower Bound:
#       Cpu:     250m
#       Memory:  512Mi
#     Target:
#       Cpu:     500m      # ← Use this for requests
#       Memory:  1Gi       # ← Use this for requests
#     Uncapped Target:
#       Cpu:     750m
#       Memory:  1536Mi
#     Upper Bound:
#       Cpu:     1000m     # ← Use this for limits
#       Memory:  2Gi       # ← Use this for limits
```

#### Step 2.2: Run Analysis Script

```bash
# Analyze last 30 days
./scripts/analyze-resources.sh --namespace production --days 30

# Output:
# Pod: myapp
# ┌─────────────┬────────┬────────┬────────┬────────────┐
# │ Metric      │ P50    │ P95    │ P99    │ Current    │
# ├─────────────┼────────┼────────┼────────┼────────────┤
# │ CPU         │ 200m   │ 450m   │ 600m   │ 1000m      │
# │ Memory      │ 384Mi  │ 768Mi  │ 920Mi  │ 2Gi        │
# └─────────────┴────────┴────────┴────────┴────────────┘
#
# Recommendation:
#   CPU Request: 250m (P50 + 25%)
#   CPU Limit: 750m (P95 + 50%)
#   Memory Request: 512Mi (P50 + 33%)
#   Memory Limit: 1Gi (P95 + 30%)
#
# Potential Savings: $42/month per pod (58% reduction)
```

#### Step 2.3: Calculate Recommendations

Use this formula:

```
CPU Request = P50 CPU × 1.2 (add 20% buffer)
CPU Limit = P95 CPU × 1.5 (allow burst capacity)

Memory Request = P50 Memory × 1.3 (add 30% buffer)
Memory Limit = P95 Memory × 1.3 (prevent OOMKills)
```

**Example Calculation**:
- P50 CPU: 200m, P95 CPU: 450m
- P50 Memory: 384Mi, P95 Memory: 768Mi

Recommendations:
- CPU Request: 200m × 1.2 = 240m → round to 250m
- CPU Limit: 450m × 1.5 = 675m → round to 750m
- Memory Request: 384Mi × 1.3 = 499Mi → round to 512Mi
- Memory Limit: 768Mi × 1.3 = 998Mi → round to 1Gi

### Phase 3: Test (1-2 weeks)

**Goal**: Validate recommendations in non-production

#### Step 3.1: Apply to Staging

```yaml
# staging/deployment.yaml
resources:
  requests:
    cpu: 250m      # From analysis
    memory: 512Mi
  limits:
    cpu: 750m
    memory: 1Gi
```

```bash
kubectl apply -f staging/deployment.yaml
```

#### Step 3.2: Load Test

```bash
# Run load test
kubectl apply -f validation/stress-test.yaml

# Monitor during load test
watch kubectl top pods -n staging

# Check for issues
kubectl get events -n staging --field-selector reason=OOMKilled
kubectl get events -n staging --field-selector reason=FailedScheduling
```

#### Step 3.3: Validate Metrics

Monitor for 1-2 weeks:

✅ **Success Indicators**:
- No OOMKilled events
- CPU throttling < 5%
- P95 latency unchanged or better
- Error rate unchanged
- Pod startup time normal

❌ **Failure Indicators**:
- OOMKilled events
- High CPU throttling (> 10%)
- Increased latency
- Pods stuck in Pending

### Phase 4: Deploy (Gradual Rollout)

**Goal**: Roll out to production safely

#### Step 4.1: Canary Deployment

```bash
# Deploy to 10% of production pods
kubectl patch deployment myapp -n production --type='json' \
  -p='[{"op": "replace", "path": "/spec/replicas", "value": 10}]'

# Update 1 pod with new resources
kubectl set resources deployment myapp -n production \
  --limits=cpu=750m,memory=1Gi \
  --requests=cpu=250m,memory=512Mi \
  --replicas=1

# Monitor for 24 hours
# If successful, proceed to full rollout
```

#### Step 4.2: Full Rollout

```bash
# Update all pods
kubectl set resources deployment myapp -n production \
  --limits=cpu=750m,memory=1Gi \
  --requests=cpu=250m,memory=512Mi

# Watch rollout
kubectl rollout status deployment myapp -n production
```

#### Step 4.3: Monitor

Watch for 7 days:

```bash
# Check for OOMKills
kubectl get events -n production --field-selector reason=OOMKilled

# Check resource usage
kubectl top pods -n production -l app=myapp

# Check throttling (from Prometheus)
# container_cpu_cfs_throttled_seconds_total
```

### Phase 5: Iterate (Quarterly)

**Goal**: Continuously optimize

Re-run analysis every 3 months:
1. Traffic patterns change
2. Application code changes
3. New features added
4. Usage grows

## 🛠️ Tools Provided

### 1. analyze-resources.sh

Analyzes Prometheus metrics to recommend resource sizing.

```bash
Usage:
  ./analyze-resources.sh [OPTIONS]

Options:
  --namespace NAMESPACE    Namespace to analyze (default: production)
  --deployment NAME        Specific deployment (default: all)
  --days NUMBER           Lookback period (default: 30)
  --percentile NUMBER     Percentile to use (default: 95)

Examples:
  # Analyze all deployments in production
  ./analyze-resources.sh --namespace production

  # Analyze specific deployment
  ./analyze-resources.sh --deployment myapp --days 30

  # Use P99 instead of P95
  ./analyze-resources.sh --percentile 99
```

### 2. recommend-limits.py

ML-based recommendations using historical data.

```bash
Usage:
  python3 recommend-limits.py [OPTIONS]

Options:
  --namespace NAMESPACE    Namespace to analyze
  --lookback-days DAYS    Lookback period (default: 30)
  --percentile P          Percentile for limits (default: 95)
  --output-format FORMAT  Output format: yaml, json, table (default: table)

Examples:
  # Generate YAML output for GitOps
  python3 recommend-limits.py --namespace production --output-format yaml > recommendations.yaml

  # JSON output for automation
  python3 recommend-limits.py --output-format json | jq .
```

### 3. vpa-analyzer.sh

Parses VPA recommendations and generates patch files.

```bash
Usage:
  ./vpa-analyzer.sh [OPTIONS]

Options:
  --namespace NAMESPACE    Namespace (default: all)
  --apply                 Apply recommendations (default: dry-run)

Examples:
  # View recommendations
  ./vpa-analyzer.sh --namespace production

  # Apply recommendations (dangerous!)
  ./vpa-analyzer.sh --namespace staging --apply
```

## 📋 Resource Sizing Cheat Sheet

### CPU Guidelines

| Usage Pattern | Request | Limit | Ratio |
|---------------|---------|-------|-------|
| Steady, predictable | P50 + 20% | P95 + 20% | 1.5x |
| Variable, bursty | P50 + 30% | P95 + 50% | 2-3x |
| Highly variable | P50 + 50% | No limit | Unlimited |
| CPU-bound | P90 | P95 + 20% | 1.2x |

### Memory Guidelines

| Usage Pattern | Request | Limit | Ratio |
|---------------|---------|-------|-------|
| Steady | P50 + 30% | P95 + 20% | 1.5x |
| Growing (cache) | P75 | P95 + 30% | 1.5-2x |
| Spiky | P75 + 30% | P99 + 20% | 2x |
| Leak risk | P50 + 50% | P95 + 50% | 2x |

### Workload-Specific Recommendations

**Web Frontend**:
```yaml
resources:
  requests:
    cpu: 100m-250m    # Usually light
    memory: 256Mi-512Mi
  limits:
    cpu: 500m-1000m   # Burst capacity
    memory: 512Mi-1Gi
```

**API Backend**:
```yaml
resources:
  requests:
    cpu: 250m-500m
    memory: 512Mi-1Gi
  limits:
    cpu: 1000m-2000m
    memory: 1Gi-2Gi
```

**Database**:
```yaml
resources:
  requests:
    cpu: 1000m-2000m  # Steady, high
    memory: 2Gi-8Gi
  limits:
    cpu: 2000m-4000m  # Limited burst
    memory: 2Gi-8Gi   # No limit (or same as request)
```

**Batch Jobs**:
```yaml
resources:
  requests:
    cpu: 500m-2000m   # Variable
    memory: 1Gi-4Gi
  limits:
    cpu: 4000m        # Allow full burst
    memory: 8Gi       # Prevent runaway
```

## 🚨 Common Issues & Solutions

### Issue: OOMKilled Pods

**Symptom**: Pods restarting with exit code 137

```bash
kubectl get events --field-selector reason=OOMKilled
```

**Cause**: Memory limit too low

**Solution**:
1. Check actual memory usage: `kubectl top pods`
2. Increase memory limit by 50%
3. Monitor for 1 week
4. Adjust if still seeing OOMKills

### Issue: CPU Throttling

**Symptom**: High latency, slow performance

```bash
# Check throttling in Prometheus
rate(container_cpu_cfs_throttled_seconds_total[5m])
```

**Cause**: CPU limit too low

**Solution**:
1. Increase CPU limit by 50%
2. Or remove CPU limit (allows bursting)
3. Monitor impact on node utilization

### Issue: Pods Stuck in Pending

**Symptom**: Pods can't be scheduled

```bash
kubectl get events --field-selector reason=FailedScheduling
```

**Cause**: Resource requests too high

**Solution**:
1. Check node capacity: `kubectl describe nodes`
2. Reduce requests to fit available nodes
3. Or add more/larger nodes

### Issue: Wasted Resources

**Symptom**: Low utilization, high costs

```bash
kubectl top pods | awk '{if ($3 < 50) print $0}'
```

**Cause**: Over-provisioned requests

**Solution**:
1. Reduce requests based on actual usage
2. Run analysis to get recommendations
3. Test in staging before production

## 💡 Best Practices

1. **Always set requests and limits**
   - Prevents resource starvation
   - Enables proper scheduling
   - Protects from noisy neighbors

2. **Requests = Guaranteed, Limits = Maximum**
   - Request: What you need
   - Limit: Maximum allowed

3. **CPU and Memory are different**
   - CPU: Compressible (throttled when over limit)
   - Memory: Incompressible (OOMKilled when over limit)
   - Be more generous with memory limits!

4. **Monitor continuously**
   - Set up alerts for OOMKills
   - Track CPU throttling
   - Review quarterly

5. **Use VPA in recommendation mode**
   - Don't enable auto-update in production (risky)
   - Use recommendations as input
   - Validate before applying

6. **Test in non-production first**
   - Never YOLO to production
   - Validate with load tests
   - Monitor for issues

7. **Document your decisions**
   - Why these specific values?
   - What analysis was done?
   - When to review again?

## 📊 Success Metrics

Track these KPIs to measure impact:

- **Cost Reduction**: $ saved per month
- **Cluster Utilization**: CPU/Memory utilization %
- **Reliability**: OOMKill rate, CPU throttling %
- **Performance**: P95 latency, error rate
- **Efficiency**: Pods per node, node count

## 🔗 Additional Resources

- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [VPA Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [Resource Requests and Limits](https://kubernetes.io/docs/tasks/configure-pod-container/assign-memory-resource/)

