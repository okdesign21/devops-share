#!/usr/bin/env bash
set -euo pipefail
# Reads JSON from stdin: {"alb_name": "name", "timeout": 600, "interval": 5, "region": "eu-central-1"}
# Outputs JSON to stdout: {"dns":"...","zone_id":"..."}

if ! command -v aws >/dev/null 2>&1; then
  echo '{"dns":"","zone_id":""}'
  echo "Error: aws cli not found" >&2
  exit 0
fi

read -r input
alb_name=$(echo "$input" | jq -r '.alb_name // ""')
timeout=$(echo "$input" | jq -r '.timeout // 600')
interval=$(echo "$input" | jq -r '.interval // 5')
region=$(echo "$input" | jq -r '.region // ""')

if [ -z "$alb_name" ] || [ "$alb_name" = "null" ]; then
  jq -n '{dns: "", zone_id: ""}'
  exit 0
fi

elapsed=0
while [ "$elapsed" -lt "$timeout" ]; do
  # Try to describe the ALB by name
  lb_json=$(aws elbv2 describe-load-balancers --names "$alb_name" ${region:+--region "$region"} --output json 2>/dev/null || true)
  if [ -n "$lb_json" ] && [ "$lb_json" != "null" ]; then
    dns=$(echo "$lb_json" | jq -r '.LoadBalancers[0].DNSName // ""')
    zone=$(echo "$lb_json" | jq -r '.LoadBalancers[0].CanonicalHostedZoneId // ""')
    jq -n --arg d "$dns" --arg z "$zone" '{dns: $d, zone_id: $z}'
    exit 0
  fi
  sleep "$interval"
  elapsed=$((elapsed + interval))
done

# timed out
jq -n '{dns: "", zone_id: ""}'
exit 0
