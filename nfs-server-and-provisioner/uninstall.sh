#!/bin/bash

NAMESPACE=nfs-server
BASE_URL=https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/nfs-server-and-provisioner

kubectl delete -f $BASE_URL/storageclass.yaml
kubectl delete -f $BASE_URL/deployment.yaml -n $NAMESPACE
curl $BASE_URL/rbac.yaml | sed -E "s/namespace:.*/namespace: $NAMESPACE/g" | kubectl delete -f -
kubectl delete -f $BASE_URL/psp.yaml 
kubectl delete ns $NAMESPACE

