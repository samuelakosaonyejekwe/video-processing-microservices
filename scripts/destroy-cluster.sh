#!/bin/bash

CLUSTER_NAME="video-converter-cluster"
REGION="eu-west-2"

echo "Deleting EKS Cluster..."

eksctl delete cluster \
  --name $CLUSTER_NAME \
  --region $REGION

echo "Cluster deleted successfully."