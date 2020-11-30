#!/bin/bash

# RKE User
useradd rke
echo RKE_PASSWD | passwd rke --stdin

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