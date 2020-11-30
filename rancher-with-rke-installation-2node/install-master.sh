#!/bin/bash

RKE_VERSION=v1.2.3
MASTER_IP=$(hostname -I | cut -d' ' -f1) 

read -p 'Worker node ip address? ' WORKER_NODE_IP
read -p 'Worker node user? ' WORKER_NODE_USER
read -p 'RKE user password? ' RKE_PASSWD

RANCHER_PASS=$(openssl rand -base64 12)
echo $RANCHER_PASS > /root/rancher_sifresi

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
  role: ['controlplane', 'etcd']
- address: $WORKER_NODE_IP
  user: rke
  role: ['worker']
kubernetes_version: v1.18.10-rancher1-1
EOF

curl -sfL https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/rancher-with-rke-installation-2node/install-worker.sh -Lo install-worker.sh
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

docker run --privileged -d --restart=unless-stopped -p 80:80 -p 443:443 rancher/rancher:v2.5.1
while true; do curl -sLk https://127.0.0.1/ping && break; printf "."; sleep 2; done

#Rancher'a giriş yap
while true; do
  printf "."
  LOGINRESPONSE=$(curl -sk "https://127.0.0.1/v3-public/localProviders/local?action=login" -H 'content-type: application/json' --data-binary '{"username":"admin","password":"admin"}')
  LOGINTOKEN=$(echo $LOGINRESPONSE | jq -r .token)

  if [ "$LOGINTOKEN" != "null" ]; then
    break
  else
    sleep 5
  fi
done

#Varsayılan Rancher şifresini değiştir
curl -sk 'https://127.0.0.1/v3/users?action=changepassword' -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"currentPassword":"admin","newPassword":"'"${RANCHER_PASS}"'"}' 

#API token al
APIRESPONSE=$(curl -sk 'https://127.0.0.1/v3/token' -H 'content-type: application/json' -H "Authorization: Bearer $LOGINTOKEN" --data-binary '{"type":"token","description":"automation"}')
APITOKEN=`echo $APIRESPONSE | jq -r .token`

#Rancher sunucu adresini ayarla
RANCHER_SERVER="https://${WORKER_NODE_IP}.nip.io"
curl -sk 'https://127.0.0.1/v3/settings/server-url' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"server-url","value":"'"${RANCHER_SERVER}"'"}'
   
#Telemetriyi kapat
curl -sk 'https://127.0.0.1/v3/settings/telemetry-opt' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"telemetry-opt","value":"out"}'

#Firma adını ayarla
curl -sk 'https://127.0.0.1/v3/settings/ui-pl' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" -X PUT --data-binary '{"name":"ui-pl","value":"Enterprisecoding"}'

# Custer kaydı oluştur
CLUSTERRESPONSE=`curl -s 'https://127.0.0.1/v3/cluster' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"dockerRootDir":"/var/lib/docker","enableClusterAlerting":false,"enableClusterMonitoring":false,"enableNetworkPolicy":false,"windowsPreferedCluster":false,"type":"cluster","name":"enterprisecoding-cluster","labels":{}}' --insecure`

# Docker run komutunu oluşturabilmek için clusterid'yi ayıkla
CLUSTERID=`echo $CLUSTERRESPONSE | jq -r .id`

# Cluster kayıt token'ı oluştur
curl -s 'https://127.0.0.1/v3/clusterregistrationtoken' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --data-binary '{"type":"clusterRegistrationToken","clusterId":"'$CLUSTERID'"}' --insecure > /dev/null

# Master bayrakları
MASTER_ROLEFLAGS="--etcd --controlplane --worker"

# Worker bayrakları
WORKER_ROLEFLAGS="--worker"

# node komutu oluştur
AGENTCMD=`curl -s 'https://127.0.0.1/v3/clusterregistrationtoken?id="'$CLUSTERID'"' -H 'content-type: application/json' -H "Authorization: Bearer $APITOKEN" --insecure | jq -r '.data[].nodeCommand' | head -1`

MASTER_DOCKERRUNCMD="$AGENTCMD $MASTER_ROLEFLAGS"
echo "$MASTER_DOCKERRUNCMD" > /tmp/komut
chmod +x /tmp/komut
/tmp/komut