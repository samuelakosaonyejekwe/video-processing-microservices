#!/bin/bash

kubectl apply -f infrastructure/kubernetes/namespaces/

kubectl apply -f infrastructure/kubernetes/gateway/

kubectl apply -f infrastructure/kubernetes/auth/

kubectl apply -f infrastructure/kubernetes/converter/

kubectl apply -f infrastructure/kubernetes/notification/

echo "Microservices deployed successfully."