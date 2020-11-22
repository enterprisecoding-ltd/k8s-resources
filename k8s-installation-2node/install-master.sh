#!/bin/bash

read -p 'Worker node ip address? ' WORKER_NODE_IP
read -p 'Worker node user? ' WORKER_NODE_USER

ssh-keygen -q -f ~/.ssh/id_rsa -N ""

ssh-copy-id ${WORKER_NODE_USER}@${WORKER_NODE_IP}

systemctl stop firewalld
systemctl disable firewalld

modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
 net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sysctl --system

echo overlay >> /etc/modules-load.d/overlay.conf
echo br_netfilter >> /etc/modules-load.d/br_netfilter.conf

yum update -y

swapoff -a
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab

sudo setenforce 0
sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

yum install -y yum-utils device-mapper-persistent-data lvm2
yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
yum install -y docker-ce

systemctl daemon-reload
systemctl enable docker
systemctl start docker


cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
exclude=kubelet kubeadm kubectl
EOF


yum update -y

yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

systemctl enable --now kubelet

systemctl daemon-reload
systemctl restart kubelet

kubeadm config images pull

kubeadm init --pod-network-cidr 10.244.0.0/16

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl create -f https://docs.projectcalico.org/manifests/tigera-operator.yaml 

cat <<EOF | kubectl create -f -
apiVersion: operator.tigera.io/v1
kind: Installation
metadata:
  name: default
spec:
  calicoNetwork:
    ipPools:
    - blockSize: 26
      cidr: 10.244.0.0/16
      encapsulation: VXLANCrossSubnet
      natOutgoing: Enabled
      nodeSelector: all()
EOF

JOIN_COMMAND=$(kubeadm token create --print-join-command)

ssh -t ${WORKER_NODE_USER}@${WORKER_NODE_IP} "curl -sfL https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/k8s-installation-2node/install-worker.sh | sh -"
ssh -t ${WORKER_NODE_USER}@${WORKER_NODE_IP} "$JOIN_COMMAND"

echo "Waiting worker node to be ready"
RET=1
until [ ${RET} -eq 0 ]; do
  kubectl wait --for=condition=ready node node01 2>/dev/null &> /dev/null
  RET=$?
  printf "."
  sleep 2
done