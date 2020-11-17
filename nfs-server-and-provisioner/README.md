# NFS Server and Provisioner

Install/unstall scripts for NFS Server and provisioner based on [nfs-ganesha-server-and-external-provisioner](https://github.com/kubernetes-sigs/nfs-ganesha-server-and-external-provisioner)

Installation can be done by executing following command;

     sh -c "$(curl -fsSL https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/nfs-server-and-provisioner/install.sh)"

This will install application on **nfs-server** namespace. Also default storage class with name enterprisecoding-nfs will be installed.

An existion installation can be uninstall by executing following command;

     sh -c "$(curl -fsSL https://raw.githubusercontent.com/enterprisecoding-ltd/k8s-resources/main/nfs-server-and-provisioner/uninstall.sh)"
