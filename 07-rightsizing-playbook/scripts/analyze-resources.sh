#!/bin/bash

# Resource Analysis Script
# Analyzes Kubernetes pod resource usage from Prometheus metrics
# and provides right-sizing recommendations

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
NAMESPACE="production"
DEPLOYMENT=""
DAYS=30
PERCENTILE=95
PROMETHEUS_URL="${PROMETHEUS_URL:-http://prometheus-server.monitoring.svc:9090}"

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --deployment)
      DEPLOYMENT="$2"
      shift 2
      ;;
    --days)
      DAYS="$2"
      shift 2
      ;;
    --percentile)
      PERCENTILE="$2"
      shift 2
      ;;
    --prometheus-url)
      PROMETHEUS_URL="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --namespace NAME       Namespace to analyze (default: production)"
      echo "  --deployment NAME      Specific deployment (default: all)"
      echo "  --days NUMBER         Lookback period in days (default: 30)"
      echo "  --percentile NUMBER   Percentile to use (default: 95)"
      echo "  --prometheus-url URL  Prometheus server URL"
      echo ""
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Kubernetes Resource Analysis${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Namespace: $NAMESPACE"
echo "Lookback: $DAYS days"
echo "Percentile: P$PERCENTILE"
echo "Prometheus: $PROMETHEUS_URL"
echo ""

# Check Prometheus connectivity
if ! curl -s -f "$PROMETHEUS_URL/-/healthy" > /dev/null; then
  echo -e "${RED}Error: Cannot connect to Prometheus at $PROMETHEUS_URL${NC}"
  echo "Make sure Prometheus is running and accessible"
  exit 1
fi

# Function to query Prometheus
query_prometheus() {
  local query="$1"
  curl -s -G "$PROMETHEUS_URL/api/v1/query" \
    --data-urlencode "query=$query" \
    | jq -r '.data.result[0].value[1]' 2>/dev/null || echo "0"
}

# Function to convert bytes to Mi
bytes_to_mi() {
  echo "scale=0; $1 / 1024 / 1024" | bc
}

# Function to format CPU (cores to millicores)
format_cpu() {
  echo "scale=0; $1 * 1000" | bc | sed 's/\..*//'
}

# Get deployments to analyze
if [ -n "$DEPLOYMENT" ]; then
  DEPLOYMENTS=$DEPLOYMENT
else
  DEPLOYMENTS=$(kubectl get deployments -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')
fi

for deploy in $DEPLOYMENTS; do
  echo -e "\n${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Deployment: $deploy${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # Get current resource configuration
  CURRENT_CPU_REQUEST=$(kubectl get deployment "$deploy" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}' || echo "not set")
  CURRENT_CPU_LIMIT=$(kubectl get deployment "$deploy" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}' || echo "not set")
  CURRENT_MEM_REQUEST=$(kubectl get deployment "$deploy" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}' || echo "not set")
  CURRENT_MEM_LIMIT=$(kubectl get deployment "$deploy" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}' || echo "not set")
  
  echo ""
  echo "Current Configuration:"
  echo "  CPU Request: $CURRENT_CPU_REQUEST"
  echo "  CPU Limit: $CURRENT_CPU_LIMIT"
  echo "  Memory Request: $CURRENT_MEM_REQUEST"
  echo "  Memory Limit: $CURRENT_MEM_LIMIT"
  echo ""
  
  # Query CPU metrics
  echo "Analyzing CPU usage over last $DAYS days..."
  
  CPU_P50_QUERY="quantile_over_time(0.50, sum(rate(container_cpu_usage_seconds_total{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"}[5m]))[${DAYS}d:5m])"
  CPU_P95_QUERY="quantile_over_time(0.${PERCENTILE}, sum(rate(container_cpu_usage_seconds_total{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"}[5m]))[${DAYS}d:5m])"
  CPU_P99_QUERY="quantile_over_time(0.99, sum(rate(container_cpu_usage_seconds_total{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"}[5m]))[${DAYS}d:5m])"
  CPU_MAX_QUERY="max_over_time(sum(rate(container_cpu_usage_seconds_total{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"}[5m]))[${DAYS}d:5m])"
  
  CPU_P50=$(query_prometheus "$CPU_P50_QUERY")
  CPU_P95=$(query_prometheus "$CPU_P95_QUERY")
  CPU_P99=$(query_prometheus "$CPU_P99_QUERY")
  CPU_MAX=$(query_prometheus "$CPU_MAX_QUERY")
  
  CPU_P50_M=$(format_cpu "$CPU_P50")
  CPU_P95_M=$(format_cpu "$CPU_P95")
  CPU_P99_M=$(format_cpu "$CPU_P99")
  CPU_MAX_M=$(format_cpu "$CPU_MAX")
  
  # Query Memory metrics
  echo "Analyzing memory usage over last $DAYS days..."
  
  MEM_P50_QUERY="quantile_over_time(0.50, sum(container_memory_working_set_bytes{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"})[${DAYS}d:5m])"
  MEM_P95_QUERY="quantile_over_time(0.${PERCENTILE}, sum(container_memory_working_set_bytes{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"})[${DAYS}d:5m])"
  MEM_P99_QUERY="quantile_over_time(0.99, sum(container_memory_working_set_bytes{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"})[${DAYS}d:5m])"
  MEM_MAX_QUERY="max_over_time(sum(container_memory_working_set_bytes{namespace=\"$NAMESPACE\",pod=~\"$deploy-.*\",container!=\"\",container!=\"POD\"})[${DAYS}d:5m])"
  
  MEM_P50=$(query_prometheus "$MEM_P50_QUERY")
  MEM_P95=$(query_prometheus "$MEM_P95_QUERY")
  MEM_P99=$(query_prometheus "$MEM_P99_QUERY")
  MEM_MAX=$(query_prometheus "$MEM_MAX_QUERY")
  
  MEM_P50_MI=$(bytes_to_mi "$MEM_P50")
  MEM_P95_MI=$(bytes_to_mi "$MEM_P95")
  MEM_P99_MI=$(bytes_to_mi "$MEM_P99")
  MEM_MAX_MI=$(bytes_to_mi "$MEM_MAX")
  
  # Display usage statistics
  echo ""
  echo "┌─────────────────┬──────────┬──────────┬──────────┬──────────┐"
  echo "│ Metric          │ P50      │ P${PERCENTILE}      │ P99      │ Max      │"
  echo "├─────────────────┼──────────┼──────────┼──────────┼──────────┤"
  printf "│ %-15s │ %7sm │ %7sm │ %7sm │ %7sm │\n" "CPU" "$CPU_P50_M" "$CPU_P95_M" "$CPU_P99_M" "$CPU_MAX_M"
  printf "│ %-15s │ %7sMi │ %7sMi │ %7sMi │ %7sMi │\n" "Memory" "$MEM_P50_MI" "$MEM_P95_MI" "$MEM_P99_MI" "$MEM_MAX_MI"
  echo "└─────────────────┴──────────┴──────────┴──────────┴──────────┘"
  
  # Calculate recommendations
  echo ""
  echo -e "${YELLOW}Recommendations:${NC}"
  echo ""
  
  # CPU Request = P50 * 1.2
  CPU_REQUEST=$(echo "scale=0; $CPU_P50_M * 1.2 / 1" | bc)
  CPU_REQUEST=$(echo "scale=0; ($CPU_REQUEST + 49) / 50 * 50" | bc) # Round to nearest 50m
  
  # CPU Limit = P95 * 1.5
  CPU_LIMIT=$(echo "scale=0; $CPU_P95_M * 1.5 / 1" | bc)
  CPU_LIMIT=$(echo "scale=0; ($CPU_LIMIT + 99) / 100 * 100" | bc) # Round to nearest 100m
  
  # Memory Request = P50 * 1.3
  MEM_REQUEST=$(echo "scale=0; $MEM_P50_MI * 1.3 / 1" | bc)
  MEM_REQUEST=$(echo "scale=0; ($MEM_REQUEST + 63) / 64 * 64" | bc) # Round to nearest 64Mi
  
  # Memory Limit = P95 * 1.3
  MEM_LIMIT=$(echo "scale=0; $MEM_P95_MI * 1.3 / 1" | bc)
  MEM_LIMIT=$(echo "scale=0; ($MEM_LIMIT + 127) / 128 * 128" | bc) # Round to nearest 128Mi
  
  echo "  CPU Request:    ${CPU_REQUEST}m  (P50 × 1.2 + 20% buffer)"
  echo "  CPU Limit:      ${CPU_LIMIT}m  (P${PERCENTILE} × 1.5 + 50% burst)"
  echo "  Memory Request: ${MEM_REQUEST}Mi (P50 × 1.3 + 30% buffer)"
  echo "  Memory Limit:   ${MEM_LIMIT}Mi (P${PERCENTILE} × 1.3 + 30% buffer)"
  echo ""
  
  # Generate YAML patch
  echo -e "${BLUE}YAML Configuration:${NC}"
  echo ""
  cat << EOF
resources:
  requests:
    cpu: ${CPU_REQUEST}m
    memory: ${MEM_REQUEST}Mi
  limits:
    cpu: ${CPU_LIMIT}m
    memory: ${MEM_LIMIT}Mi
EOF
  echo ""
  
  # Calculate potential savings
  # Assuming current is over-provisioned, estimate savings
  echo -e "${GREEN}Potential Impact:${NC}"
  echo ""
  if [ "$CURRENT_CPU_REQUEST" != "not set" ]; then
    CURRENT_CPU_VALUE=$(echo "$CURRENT_CPU_REQUEST" | sed 's/m//')
    if [ "$CURRENT_CPU_VALUE" -gt "$CPU_REQUEST" ]; then
      CPU_SAVINGS=$(echo "scale=0; (($CURRENT_CPU_VALUE - $CPU_REQUEST) * 100) / $CURRENT_CPU_VALUE" | bc)
      echo -e "  ${GREEN}✓${NC} CPU Request reduction: ${CPU_SAVINGS}%"
    else
      CPU_INCREASE=$(echo "scale=0; (($CPU_REQUEST - $CURRENT_CPU_VALUE) * 100) / $CURRENT_CPU_VALUE" | bc)
      echo -e "  ${YELLOW}⚠${NC} CPU Request increase: ${CPU_INCREASE}% (may be needed)"
    fi
  fi
  
  # Check for potential issues
  echo ""
  echo -e "${YELLOW}Warnings:${NC}"
  echo ""
  
  if [ "$CPU_P99_M" -gt "$(echo "scale=0; $CPU_LIMIT * 0.9 / 1" | bc)" ]; then
    echo -e "  ${YELLOW}⚠${NC} P99 CPU (${CPU_P99_M}m) is close to recommended limit (${CPU_LIMIT}m)"
    echo "     Consider increasing limit or investigating high CPU usage"
  fi
  
  if [ "$MEM_P99_MI" -gt "$(echo "scale=0; $MEM_LIMIT * 0.9 / 1" | bc)" ]; then
    echo -e "  ${RED}⚠${NC} P99 Memory (${MEM_P99_MI}Mi) is close to recommended limit (${MEM_LIMIT}Mi)"
    echo "     Risk of OOMKill! Consider increasing memory limit"
  fi
  
  if [ "$CPU_P50_M" -lt 50 ]; then
    echo -e "  ${BLUE}ℹ${NC} Very low CPU usage. Consider consolidating with other services"
  fi
  
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Analysis Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "Next Steps:"
echo "  1. Review recommendations above"
echo "  2. Test in staging environment first"
echo "  3. Monitor for OOMKills and CPU throttling"
echo "  4. Adjust based on actual behavior"
echo ""
echo "To apply recommendations:"
echo "  kubectl set resources deployment <name> -n $NAMESPACE \\"
echo "    --requests=cpu=XXXm,memory=XXXMi \\"
echo "    --limits=cpu=XXXm,memory=XXXMi"
echo ""

