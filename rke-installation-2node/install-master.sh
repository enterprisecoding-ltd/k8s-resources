#!/bin/bash

RKE_VERSION=v1.2.3
MASTER_IP=$(hostname -I | cut -d' ' -f1) 

read -p 'Worker node ip address? ' WORKER_NODE_IP
read -p 'Worker node user? ' WORKER_NODE_USER
read -p 'RKE user password? ' RKE_PASSWD

ssh-keygen -q -f ~/.ssh/id_rsa -N ""


ssh-copy-id ${WORKER_NODE_USER}@${WORKER_NODE_IP}


yum install sshpass -y

# RKE User
useradd rke
echo $RKE_PASSWD | passwd rke --stdin

#Disable Swap
swapoff -a
sed -i.bak -r 's/(.+ swap .+)/#\1/' /etc/fstab

systemctl stop firewalld
systemctl disable firewalld

echo "AllowTcpForwarding yes" >> /etc/ssh/sshd_config

# Install Docker

curl https://releases.rancher.com/install-docker/18.09.sh | sh
usermod -aG docker rke

systemctl enable docker
systemctl start docker

cat <<EOF >> rancher-cluster.yml
nodes:
- address: $MASTER_IP
  user: rke
  role: ['controlplane', 'etcd', 'worker']
- address: $WORKER_NODE_IP
  user: rke
  role: ['worker']
kubernetes_version: v1.18.10-rancher1-1
EOF

curl -sfL https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/rke-installation-2node/install-worker.sh -Lo install-worker.sh
chmod +x install-worker.sh
sed -i 's@RKE_PASSWD@'"$RKE_PASSWD"'@g' install-worker.sh

scp install-worker.sh ${WORKER_NODE_USER}@${WORKER_NODE_IP}:/tmp/install-worker.sh
rm -f install-worker.sh


ssh -t ${WORKER_NODE_USER}@${WORKER_NODE_IP} "/tmp/install-worker.sh && rm -f install-worker.sh"

sshpass -p "$RKE_PASSWD" ssh-copy-id -o "StrictHostKeyChecking no" rke@${WORKER_NODE_IP}
sshpass -p "$RKE_PASSWD" ssh-copy-id -o "StrictHostKeyChecking no" rke@${MASTER_IP}

curl -L https://github.com/rancher/rke/releases/download/$RKE_VERSION/rke_linux-amd64 -o rke
chmod +x rke
mv rke /usr/local/bin
rke up --config ./rancher-cluster.yml

curl -LO "https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x ./kubectl
mv ./kubectl /usr/local/bin/kubectl

curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash

mkdir -p $HOME/.kube
cp -i kube_config_rancher-cluster.yml $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

kubectl wait --for=condition=Ready node $WORKER_NODE_IP