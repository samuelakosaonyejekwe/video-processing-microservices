#!/bin/bash

CLUSTER_NAME="video-converter-cluster"
REGION="eu-west-2"

echo "Creating EKS Cluster..."

eksctl create cluster \
  --name $CLUSTER_NAME \
  --region $REGION \
  --nodes 2 \
  --node-type t3.medium \
  --managed

echo "EKS Cluster deployment completed."