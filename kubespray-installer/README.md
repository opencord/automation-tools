# Kubespray Installer

This script will clone
[kubespray](https://github.com/kubernetes-sigs/kubespray) automatically, and
deploy production ready Kubernetes cluster by kubespray.

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

Now you should be able to use your newly installed kubernetes cluster.

## Testing kubespray-installer in VM's

These scripts allow you to test a multi-node kubespray installer on a single
machine, with additional disks attached for testing persistent storage.

### Prepare test system

Run the `kubespray-vagrant.sh` script which will install all the necesary
prerequisites and tools.
#
Only tested on an Ubuntu 16.04 machine, with a user that has passwordless sudo
enabled. Works/tested on CloudLab.

Requires a considerable amount of CPU, RAM, and disk space - 3 VM's each with 8
cores, 16GB RAM, and multiple 40GB drives (sparsely allocated).

## Bring up VM's

Check out `automation_tools` on the target system, then run the following to
bring up VM's with `vagrant`:

```shell
vagrant up
vagrant ssh-config >> ~/.ssh/config
vagrant ssh-config | sed -e 's/Host k8s-0/Host 10.90.0.10/g' >> ~/.ssh/config
```

> NOTE: If you tear down and rebuild the VM's in vagrant, you will need to
> delete the configuration of the previous VM's from ~/.ssh/config before
> running the `vagrant ssh-config ...` commands.

### Run kubespray-installer/setup.sh script

```shell
REMOTE_SSH_USER="vagrant" ./setup.sh -i test
```

### Copy config for k8s tools, bootstrap helm

```shell
mkdir ~/.kube/
cp inventories/test/artifacts/admin.conf ~/.kube/config

helm init --upgrade
```
