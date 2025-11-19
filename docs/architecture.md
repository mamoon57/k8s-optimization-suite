# Architecture Documentation

## System Overview

This Kubernetes optimization suite implements a multi-layered architecture designed for high availability, cost efficiency, and operational excellence.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────┐
│                          Global Traffic Management                       │
│                     (Route53 Latency-Based Routing)                     │
└────────────────┬───────────────────────────────┬────────────────────────┘
                 │                               │
        ┌────────▼─────────┐            ┌───────▼──────────┐
        │  Region: US-EAST │            │ Region: EU-WEST  │
        │   (Primary)      │            │  (Secondary)     │
        └────────┬─────────┘            └───────┬──────────┘
                 │                               │
        ┌────────▼─────────────────────┐        │
        │    AWS ALB / NLB             │        │
        │  - SSL Termination           │        │
        │  - Health Checks             │        │
        │  - WAF Integration           │        │
        └────────┬─────────────────────┘        │
                 │                               │
        ┌────────▼─────────────────────┐        │
        │    Ingress Controller        │        │
        │  - NGINX / AWS LB Controller │        │
        │  - Rate Limiting             │        │
        │  - Path-based Routing        │        │
        └────────┬─────────────────────┘        │
                 │                               │
    ┌────────────▼──────────────────┐           │
    │     Kubernetes Services       │           │
    │   - ClusterIP (internal)      │           │
    │   - LoadBalancer (external)   │           │
    └────────────┬──────────────────┘           │
                 │                               │
    ┌────────────▼──────────────────────────────▼─────────┐
    │              Application Pods (Auto-Scaled)          │
    │  ┌──────────────────────────────────────────────┐   │
    │  │  HPA (CPU, Memory, Custom Metrics)           │   │
    │  │  - Target: 70% CPU, 80% Memory               │   │
    │  │  - Scale: 3-50 replicas                      │   │
    │  └──────────────────────────────────────────────┘   │
    │                                                      │
    │  ┌──────────────────────────────────────────────┐   │
    │  │  KEDA (Event-Driven Scaling)                 │   │
    │  │  - Kafka consumer lag                        │   │
    │  │  - SQS queue depth                           │   │
    │  │  - Cron-based predictive                     │   │
    │  │  - Prometheus custom metrics                 │   │
    │  └──────────────────────────────────────────────┘   │
    └───────────────────────┬──────────────────────────────┘
                            │
        ┌───────────────────▼───────────────────┐
        │        Node Groups (Mixed)            │
        │  ┌─────────────────────────────────┐  │
        │  │  On-Demand Nodes (30%)          │  │
        │  │  - Critical workloads           │  │
        │  │  - Databases                    │  │
        │  │  - Stateful apps                │  │
        │  │  Priority: production-critical  │  │
        │  └─────────────────────────────────┘  │
        │                                        │
        │  ┌─────────────────────────────────┐  │
        │  │  Spot Nodes (70%)               │  │
        │  │  - Stateless workloads          │  │
        │  │  - Batch jobs                   │  │
        │  │  - Dev/staging                  │  │
        │  │  Priority: batch-low            │  │
        │  └─────────────────────────────────┘  │
        └────────────────────────────────────────┘
                            │
        ┌───────────────────▼───────────────────┐
        │    Cluster Autoscaler + Descheduler   │
        │  - Scale nodes based on demand        │
        │  - Bin-pack pods for efficiency       │
        │  - Remove underutilized nodes         │
        └────────────────────────────────────────┘
```

## Data Flow

### 1. Request Flow (Inbound)

```
User Request
    ↓
Route53 (DNS)
    ↓ [Latency-based routing]
Nearest Region
    ↓
AWS ALB/NLB
    ↓ [SSL termination, health checks]
Ingress Controller
    ↓ [Path routing, rate limiting]
Kubernetes Service
    ↓ [Load balancing]
Application Pod
    ↓
Response
```

### 2. Autoscaling Decision Flow

```
Metrics Collection
    ↓
Prometheus (scrapes every 30s)
    ↓
    ├─→ Prometheus Adapter → Custom Metrics API
    │                              ↓
    │                          HPA Controller
    │                              ↓
    │                   "Need more replicas?"
    │                              ↓
    └─→ KEDA Operator ─────→ ScaledObject
                                   ↓
                            "Yes, scale up!"
                                   ↓
                         Deployment Controller
                                   ↓
                            Create new pods
                                   ↓
                         Kubernetes Scheduler
                                   ↓
                      "Which node to place pod?"
                                   ↓
                    Check: Priority, Resources, Affinity
                                   ↓
                            Place on node
                                   ↓
                       Cluster Autoscaler
                                   ↓
                  "Need more nodes?" → Yes
                                   ↓
                      Provision spot instances
```

### 3. Cost Optimization Flow

```
Descheduler (runs every 30 min)
    ↓
Scan cluster for inefficiencies
    ↓
    ├─→ Low utilization nodes? → Consolidate pods
    │                                  ↓
    │                          Evict pods from node
    │                                  ↓
    │                    Scheduler places on other nodes
    │                                  ↓
    │                           Node becomes empty
    │                                  ↓
    └─→ Cluster Autoscaler → Scale down empty node
                                   ↓
                            💰 Cost savings!
```

## Component Responsibilities

### Control Plane

| Component | Purpose | Configuration |
|-----------|---------|---------------|
| **HPA** | Reactive autoscaling | CPU: 70%, Memory: 80% |
| **KEDA** | Event-driven scaling | Kafka lag, SQS depth, Cron |
| **Cluster Autoscaler** | Node provisioning | Scale nodes based on pending pods |
| **Descheduler** | Resource optimization | Bin-pack pods, remove waste |
| **Prometheus** | Metrics collection | 30s scrape interval |

### Data Plane

| Component | Purpose | Scaling |
|-----------|---------|---------|
| **Application Pods** | Business logic | 3-50 replicas (HPA) |
| **On-Demand Nodes** | Guaranteed capacity | 5-15 nodes (critical workloads) |
| **Spot Nodes** | Cost-optimized capacity | 0-50 nodes (burst workloads) |

### Observability

| Component | Purpose | Retention |
|-----------|---------|-----------|
| **Prometheus** | Metrics storage | 30 days |
| **Grafana** | Visualization | N/A (queries Prometheus) |
| **AlertManager** | Alert routing | N/A (stateless) |

## High Availability Design

### Application Layer

- **Minimum 3 replicas** across 3 availability zones
- **PodDisruptionBudget**: `minAvailable: 2` (maintains quorum)
- **Pod anti-affinity**: Spreads pods across nodes
- **Topology spread**: Evenly distributes across zones

### Network Layer

- **Multi-region deployment**: US-East-1 (primary), EU-West-1 (secondary)
- **Route53 health checks**: 30s interval, 90s failover time
- **Latency-based routing**: Users go to nearest healthy region
- **Ingress redundancy**: Multiple ingress controllers per region

### Infrastructure Layer

- **On-Demand baseline**: Guaranteed capacity for critical workloads
- **Spot diversification**: 4+ instance types reduces interruption risk
- **Cross-AZ placement**: Nodes spread across 3 availability zones
- **Automated node recovery**: Cluster Autoscaler replaces failed nodes

## Failure Scenarios & Recovery

### Scenario 1: Pod Failure (OOMKill, Crash)

```
Pod crashes
    ↓
Kubernetes detects (liveness probe fails)
    ↓
Restarts pod (on same node)
    ↓
If repeated crashes → Exponential backoff (CrashLoopBackOff)
    ↓
Alert: PagerDuty notification
    ↓
Recovery time: < 10 seconds
```

### Scenario 2: Node Failure (Hardware, Spot Termination)

```
Node becomes unreachable
    ↓
Kubernetes marks node NotReady
    ↓
Pods on node marked as Terminating
    ↓
Scheduler places pods on healthy nodes
    ↓
Cluster Autoscaler provisions replacement node (if needed)
    ↓
Recovery time: 2-5 minutes
```

### Scenario 3: Region Failure

```
Entire region (us-east-1) goes down
    ↓
Route53 health checks fail (after 90s)
    ↓
DNS updated to route to eu-west-1
    ↓
Users automatically redirected
    ↓
Recovery time: < 2 minutes
```

### Scenario 4: High Traffic Spike (10x normal)

```
Traffic increases 10x
    ↓
Prometheus detects high CPU/memory
    ↓
HPA scales pods: 5 → 50 replicas
    ↓
Pending pods wait for resources
    ↓
Cluster Autoscaler adds nodes (spot instances)
    ↓
Pods scheduled on new nodes
    ↓
Recovery time: 5-10 minutes to full capacity
```

## Security Architecture

### Network Security

- **Network Policies**: Restrict pod-to-pod communication
- **Ingress TLS**: All external traffic encrypted (cert-manager)
- **Service Mesh** (optional): mTLS for internal traffic

### Pod Security

- **Security Context**: Non-root user, read-only filesystem
- **PodSecurityPolicy** (or Pod Security Standards): Enforce security best practices
- **Secrets**: Stored in Secrets Manager (AWS), not in Git

### RBAC

- **Least privilege**: Service accounts with minimal permissions
- **Namespace isolation**: Production isolated from dev/staging
- **ArgoCD RBAC**: Developers can view, platform team can deploy

## Cost Architecture

### Cost Allocation

```
Total Monthly Cost: $4,200
├─ On-Demand Nodes (30%): $1,800
│  ├─ Critical workloads
│  └─ Baseline capacity
├─ Spot Nodes (70%): $2,100
│  ├─ Stateless apps
│  ├─ Batch jobs
│  └─ Burst capacity
└─ Other: $300
   ├─ ALB/NLB: $150
   ├─ Route53: $50
   └─ CloudWatch: $100
```

### Cost Optimization Strategies

1. **Spot Instances**: 70% of compute → 70% cost savings on that portion
2. **Right-Sizing**: Reduce over-provisioned resources by 50%
3. **Bin-Packing**: Descheduler consolidates pods → fewer nodes
4. **Scale-to-Zero**: KEDA scales batch jobs to 0 when idle
5. **ARM Graviton**: 20% cheaper than x86 on-demand

### Cost Monitoring

- **Prometheus query**: Estimate hourly cost based on node count
- **CloudWatch**: AWS Cost Explorer integration
- **Alert**: `ClusterCostAnomalyDetected` when 50% over baseline

## Performance Characteristics

### Latency

| Metric | Target | Actual |
|--------|--------|--------|
| P50 API Response | < 100ms | 85ms |
| P95 API Response | < 200ms | 180ms |
| P99 API Response | < 500ms | 420ms |
| DNS Lookup | < 50ms | 15ms |
| SSL Handshake | < 100ms | 45ms |

### Throughput

| Metric | Capacity | Notes |
|--------|----------|-------|
| Requests/sec (per pod) | 1,000 | HPA scales at this threshold |
| Total cluster capacity | 50,000 | 50 pods × 1,000 req/s |
| Burst capacity | 100,000 | With spot scaling |

### Scaling Speed

| Event | Time to Scale |
|-------|---------------|
| Pod scale-up (HPA) | 15-30 seconds |
| Pod scale-down (HPA) | 5 minutes (stabilization) |
| Node scale-up (CA) | 2-5 minutes |
| Node scale-down (CA) | 10-15 minutes |
| Regional failover | < 2 minutes |

## Monitoring & Observability

### Key Metrics Tracked

1. **Resource Utilization**
   - `node:cpu_utilization:avg`
   - `pod:memory_utilization:request_ratio`
   - `pod:cpu_throttling:rate5m`

2. **Application Performance**
   - HTTP request rate
   - P95/P99 latency
   - Error rate

3. **Availability**
   - Pod restart count
   - OOMKill events
   - Health check failures

4. **Cost**
   - Node count by type (on-demand, spot)
   - Resource waste (under-utilized pods)
   - Spot interruption rate

### Alerting Tiers

| Severity | Examples | Response Time |
|----------|----------|---------------|
| **Critical** | OOMKilled, region down | Immediate (PagerDuty) |
| **Warning** | High CPU, near memory limit | 15 minutes |
| **Info** | Underutilized resources | 24 hours |

## Deployment Strategy

### GitOps Workflow

```
Developer commits code
    ↓
Git push to main branch
    ↓
ArgoCD detects change
    ↓
    ├─→ Staging: Auto-sync immediately
    │                ↓
    │         Run smoke tests
    │                ↓
    │         Tests pass?
    │                ↓
    └─→ Production: Manual approval required
                     ↓
              Rolling update (1 pod at a time)
                     ↓
              Monitor for 5 minutes
                     ↓
              Success! (or auto-rollback)
```

### Rollout Strategy

- **Rolling update**: `maxSurge: 1`, `maxUnavailable: 0` (zero downtime)
- **Canary deployment**: Weighted Route53 (10% → 50% → 100%)
- **Blue-green**: Separate deployments, instant traffic switch
- **Rollback**: Automated on health check failure

## Disaster Recovery

### Recovery Time Objective (RTO)

| Failure Type | RTO | Strategy |
|--------------|-----|----------|
| Pod failure | < 10s | Automatic restart |
| Node failure | < 5 min | Automatic replacement |
| AZ failure | < 2 min | Multi-AZ deployment |
| Region failure | < 5 min | Multi-region with Route53 |

### Recovery Point Objective (RPO)

- **Stateless apps**: 0 (no data loss)
- **Databases**: 5 minutes (continuous replication)
- **Logs**: 1 minute (shipped to CloudWatch)

## Scalability Limits

### Current Limits

- **Maximum pods per deployment**: 50 (HPA limit)
- **Maximum nodes**: 100 (Cluster Autoscaler limit)
- **Maximum requests/sec**: 100,000 (at full scale)

### To Scale Beyond

1. **Horizontal cluster scaling**: Add more regions
2. **Vertical scaling**: Use larger instance types
3. **Service mesh**: Linkerd/Istio for advanced traffic management
4. **Database sharding**: Partition data across multiple databases

## Future Enhancements

- [ ] Service mesh (Linkerd) for advanced observability
- [ ] Chaos engineering (LitmusChaos) for resilience testing
- [ ] Machine learning-based autoscaling (predictive)
- [ ] Multi-cluster federation (Kubernetes Federation v2)
- [ ] Progressive delivery (Flagger)

