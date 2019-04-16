# Kubespray Installer

This script will clone [kubespray](https://github.com/kubernetes-sigs/kubespray) automatically, and deploy production ready Kubernetes cluster by kubespray.

## Install public key to target nodes

```bash
# ./copy-ssh-keys.sh <set_of_target_nodes>
./copy-ssh-keys.sh 192.168.0.1 192.168.0.2 192.168.0.3

# Assign customized username if username isn't cord
REMOTE_SSH_USER=ubuntu ./copy-ssh-keys.sh 192.168.0.1 192.168.0.2 192.168.0.3

# Select the desired public key (default: id_rsa.pub)
SSH_PUBKEY_PATH=~/.ssh/onoscorddev.pub ./copy-ssh-keys.sh 192.168.0.1 192.168.0.2 192.168.0.3
```

Then you are able to ssh into the target nodes without password, this is required by Kuberspray script.

## Run the installation script

```bash
# ./setup -i <inventory_name> <set_of_target_nodes>
./setup -i pod1 192.168.0.1 192.168.0.2 192.168.0.3

# You can also pipe the output to stdout & file
./setup -i pod1 192.168.0.1 192.168.0.2 192.168.0.3 | tee /tmp/kubespray-installer.log

# Assign customized username
REMOTE_SSH_USER=ubuntu ./setup -i pod1 192.168.0.1 192.168.0.2 192.168.0.3
```
