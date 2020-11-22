#!/bin/bash

NAMESPACE=nfs-server
BASE_URL=https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/nfs-server-and-provisioner

kubectl create ns $NAMESPACE
kubectl create -f $BASE_URL/psp.yaml 
curl $BASE_URL/rbac.yaml | sed -E "s/namespace:.*/namespace: $NAMESPACE/g" | kubectl create -f -
kubectl create -f $BASE_URL/deployment.yaml -n $NAMESPACE
kubectl create -f $BASE_URL/storageclass.yaml