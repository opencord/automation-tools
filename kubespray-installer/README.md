# Testing kubespray-installer

These scripts allow you to test a multi-node kubespray installer on a single
machine, with additional disks attached for testing persistent storage.

## Prepare system

Only tested on an Ubuntu 16.04 machine, with a user that has passwordless sudo
enabled. Works/tested on CloudLab.

Requires a considerable amount of CPU, RAM, and disk space - 3 VM's each with 8
cores, 16GB RAM, and multiple 40GB drives (sparsely allocated).

## Bring up VM's

Check out `automation_tools` on the target system, then run the following to
bring up VM's with `vagrant`:

```shell
cd ~/automation-tools/kubespray-installer
vagrant up
vagrant ssh-config >> ~/.ssh/config
vagrant ssh-config | sed -e 's/Host k8s-0/Host 10.90.0.10/g' >> ~/.ssh/config
```

> NOTE: If you tear down and rebuild the VM's in vagrant, you will need to
> delete the configuration of the previous VM's from ~/.ssh/config before
> running the `vagrant ssh-config ...` commands.

## Run kubespray-installer/setup.sh script

```shell
cd ~/automation-tools/kubespray-installer
REMOTE_SSH_USER="vagrant" ./setup.sh -i test
```

## Copy config for k8s tools, bootstrap helm

```shell
mkdir ~/.kube/
cp inventories/test/artifacts/admin.conf ~/.kube/config

helm init --upgrade
```
