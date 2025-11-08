# 🚀 Quick Start Guide

Get up and running with the Kubernetes Optimization Suite in 10 minutes.

## Prerequisites Check

```bash
# Verify tools are installed
kubectl version --client
helm version
kustomize version

# Verify cluster access
kubectl cluster-info
kubectl get nodes
```

## Option A: Full Deployment (All Features)

### Step 1: Clone and Configure

```bash
# Clone repository
git clone https://github.com/mamoonidrees/k8s-optimization-suite.git
cd k8s-optimization-suite

# Create namespace
kubectl create namespace production
```

### Step 2: Deploy Application

```bash
# Deploy core application
kubectl apply -f 01-deployments/

# Verify deployment
kubectl get all -n production
kubectl top pods -n production
```

### Step 3: Enable Autoscaling

```bash
# Install Metrics Server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Deploy HPA
kubectl apply -f 02-autoscaling/hpa-v2.yaml

# Install KEDA (optional)
helm repo add kedacore https://kedacore.github.io/charts
helm install keda kedacore/keda --namespace keda --create-namespace

# Deploy KEDA scalers
kubectl apply -f 02-autoscaling/keda-scalers/cron-scaler.yaml
```

### Step 4: Cost Optimization

```bash
# Create priority classes
kubectl apply -f 03-cost-optimization/priority-classes.yaml

# Configure spot/on-demand nodes (AWS EKS)
eksctl create nodegroup -f 03-cost-optimization/spot-node-pool.yaml
eksctl create nodegroup -f 03-cost-optimization/ondemand-node-pool.yaml

# Install Descheduler
kubectl apply -f 03-cost-optimization/descheduler-policy.yaml
```

### Step 5: Monitoring

```bash
# Install Prometheus stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace

# Apply custom alerts
kubectl apply -f 06-observability/prometheus/rules.yaml
```

---

## Option B: Minimal Setup (Just Basics)

Perfect for testing or learning.

```bash
# 1. Deploy application
kubectl create namespace production
kubectl apply -f 01-deployments/app-deployment.yaml
kubectl apply -f 01-deployments/service.yaml

# 2. Enable basic autoscaling
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl apply -f 02-autoscaling/hpa-v2.yaml

# 3. Done! Monitor with:
kubectl get hpa -n production -w
```

---

## Verification Commands

```bash
# Check deployments
kubectl get deployments -n production

# Check autoscaling
kubectl get hpa -n production

# Check resource usage
kubectl top pods -n production

# Check events for issues
kubectl get events -n production --sort-by='.lastTimestamp'

# Check for OOMKills (should be none)
kubectl get events -n production --field-selector reason=OOMKilled
```

---

## What to Customize

### Before Production Use:

1. **Update application name and image**:
   ```bash
   # Find and replace in all files
   find . -name "*.yaml" -exec sed -i 's/myapp/your-app-name/g' {} +
   ```

2. **Update domain names**:
   ```bash
   find . -name "*.yaml" -exec sed -i 's/example\.com/your-domain.com/g' {} +
   ```

3. **Right-size resources**:
   ```bash
   # Run analysis after collecting metrics for 30 days
   cd 07-rightsizing-playbook
   ./scripts/analyze-resources.sh --namespace production
   ```

4. **Update Prometheus URL** (if different):
   ```bash
   export PROMETHEUS_URL=http://your-prometheus-server:9090
   ```

---

## Troubleshooting

### Pods not starting?

```bash
# Check pod status
kubectl describe pod <pod-name> -n production

# Common issues:
# - ImagePullBackOff: Wrong image name
# - CrashLoopBackOff: Application error, check logs
# - Pending: Insufficient resources, check nodes
```

### HPA not scaling?

```bash
# Check metrics availability
kubectl top pods -n production

# If empty, metrics-server might not be running
kubectl get pods -n kube-system | grep metrics-server

# Check HPA status
kubectl describe hpa -n production
```

### High costs?

```bash
# Check node utilization
kubectl top nodes

# If low (< 30%), you're wasting money:
# 1. Enable descheduler for bin-packing
# 2. Add spot instances
# 3. Right-size pod resources
```

---

## Next Steps

1. **Collect metrics for 30 days**
2. **Run resource analysis**: `./scripts/analyze-resources.sh`
3. **Apply recommendations to staging**
4. **Load test and validate**
5. **Gradually roll out to production**

---

## Support

- 📖 Full documentation: `MANIFEST.md`
- 🔧 Right-sizing guide: `07-rightsizing-playbook/README.md`
- 💰 Cost optimization: `03-cost-optimization/*.yaml`
- 📊 Monitoring setup: `06-observability/prometheus/rules.yaml`

---

**Estimated time to full deployment**: 30-60 minutes  
**Estimated time to first cost savings**: 7-14 days (after right-sizing)

