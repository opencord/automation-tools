# Testing for kubespray-installer

These scripts allow you to test the kubespray installer on a single machine.

## Prepare system

Requires an Ubuntu 16.04 machine, with a user with sudo enabled. Works on cloudlab.

Copy the `test_boostrap.sh` script onto the target machine and run it.

## Bring up VM's

Run the follwing to bring up VM's with vagrant

```shell
cd ~/automation-tools/kubespray-installer/test
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

