#!/usr/bin/env bash
set -euo pipefail

istioctl install --set profile=demo -y
kubectl apply -f ../namespaces.yaml
kubectl label namespace ingress-nginx istio-injection=enabled --overwrite
kubectl apply -f .
kubectl rollout restart deployment -n yas
kubectl rollout restart deployment ingress-nginx-controller -n ingress-nginx
