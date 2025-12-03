#!/bin/bash
# Cleanup orphaned IAM resources after terraform destroy
# These resources sometimes fail to delete due to AWS eventual consistency

set +e  # Don't exit on errors - resources might not exist

ENV="${1:-dev}"
PROJECT_NAME="${2:-proj}"
REGION="${3:-eu-central-1}"

echo "🧹 Cleaning up orphaned IAM resources for ${PROJECT_NAME}-${ENV}..."

# Cluster IAM role
CLUSTER_ROLE="${PROJECT_NAME}-${ENV}-eks-cluster-role"
echo "Checking for cluster role: ${CLUSTER_ROLE}"
if aws iam get-role --role-name "${CLUSTER_ROLE}" --region "${REGION}" >/dev/null 2>&1; then
    echo "  Detaching policies from ${CLUSTER_ROLE}..."
    aws iam detach-role-policy --role-name "${CLUSTER_ROLE}" --policy-arn "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${CLUSTER_ROLE}" --policy-arn "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController" 2>/dev/null || true
    echo "  Deleting ${CLUSTER_ROLE}..."
    aws iam delete-role --role-name "${CLUSTER_ROLE}" 2>/dev/null && echo "  ✓ Deleted ${CLUSTER_ROLE}" || echo "  ✗ Failed to delete ${CLUSTER_ROLE}"
else
    echo "  ✓ ${CLUSTER_ROLE} already deleted"
fi

# Node IAM role
NODE_ROLE="${PROJECT_NAME}-${ENV}-eks-node-role"
echo "Checking for node role: ${NODE_ROLE}"
if aws iam get-role --role-name "${NODE_ROLE}" --region "${REGION}" >/dev/null 2>&1; then
    echo "  Detaching policies from ${NODE_ROLE}..."
    aws iam detach-role-policy --role-name "${NODE_ROLE}" --policy-arn "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${NODE_ROLE}" --policy-arn "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy" 2>/dev/null || true
    aws iam detach-role-policy --role-name "${NODE_ROLE}" --policy-arn "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly" 2>/dev/null || true
    echo "  Deleting ${NODE_ROLE}..."
    aws iam delete-role --role-name "${NODE_ROLE}" 2>/dev/null && echo "  ✓ Deleted ${NODE_ROLE}" || echo "  ✗ Failed to delete ${NODE_ROLE}"
else
    echo "  ✓ ${NODE_ROLE} already deleted"
fi

# Instance profile
INSTANCE_PROFILE="${PROJECT_NAME}-${ENV}-eks-node-profile"
echo "Checking for instance profile: ${INSTANCE_PROFILE}"
if aws iam get-instance-profile --instance-profile-name "${INSTANCE_PROFILE}" >/dev/null 2>&1; then
    echo "  Removing role from ${INSTANCE_PROFILE}..."
    aws iam remove-role-from-instance-profile --instance-profile-name "${INSTANCE_PROFILE}" --role-name "${NODE_ROLE}" 2>/dev/null || true
    echo "  Deleting ${INSTANCE_PROFILE}..."
    aws iam delete-instance-profile --instance-profile-name "${INSTANCE_PROFILE}" 2>/dev/null && echo "  ✓ Deleted ${INSTANCE_PROFILE}" || echo "  ✗ Failed to delete ${INSTANCE_PROFILE}"
else
    echo "  ✓ ${INSTANCE_PROFILE} already deleted"
fi

echo "✅ IAM cleanup complete for ${ENV} environment"
