#!/bin/bash
set -e

SCALING_GROUP_NAME=$1
REGION=$2

echo "Fetching Scaling Group ID..."
RAW=$(aliyun ess DescribeScalingGroups \
  --RegionId "$REGION" \
  --ScalingGroupName "$SCALING_GROUP_NAME")

SG_ID=$(echo "$RAW" | jq -r '.ScalingGroups.ScalingGroup[0].ScalingGroupId')

echo "Creating Scaling Configuration..."
CONFIG_JSON=$(aliyun ess ApplyEciScalingConfiguration \
  --RegionId "$REGION" \
  --ScalingGroupId "$SG_ID" \
  --Content "$(cat final.yml)" \
  --version 2022-02-22 --method POST --force)

CONFIG_ID=$(echo "$CONFIG_JSON" | jq -r '.ScalingConfigurationId')
echo "New Config ID: $CONFIG_ID"

echo "Starting Instance Refresh..."
REFRESH=$(aliyun ess StartInstanceRefresh \
  --ScalingGroupId "$SG_ID" \
  --DesiredConfiguration.ScalingConfigurationId "$CONFIG_ID" \
  --RegionId "$REGION" \
  --Strategy Rolling \
  --DesiredPercentage 100 \
  --SkipMatching false \
  --version 2022-02-22 --method POST --force)

REFRESH_ID=$(echo "$REFRESH" | jq -r '.InstanceRefreshTaskId')

echo "Monitoring Instance Refresh..."
for i in {1..40}; do
  STATUS=$(aliyun ess DescribeInstanceRefreshes \
    --ScalingGroupId "$SG_ID" \
    --InstanceRefreshTaskIds "$REFRESH_ID" \
    --RegionId "$REGION" \
    --version 2022-02-22 | jq -r '.InstanceRefreshTasks[0].Status')

  echo "Status: $STATUS"

  if [[ "$STATUS" == "Successful" ]]; then
    echo "Deployment finished!"
    exit 0
  elif [[ "$STATUS" == "Failed" ]]; then
    echo "Deployment FAILED!"
    exit 1
  fi

  sleep 15
done

echo "Timeout waiting for instance refresh!"
exit 1