# Testing for kubespray-installer

These scripts allow you to test the kubespray installer on a single machine.

## Prepare system

Requires an Ubuntu 16.04 machine, with a user with sudo access

Copy the `test_boostrap.sh` script onto the target machine and run it.

## Bring up VM's

Run the follwing to bring up VM's with vagrant

```shell
cd cord/automation-tools/test
vagrant up
vagrant ssh-config > ~/.ssh/config
vagrant ssh-config | sed -e 's/k8s-0/10.90.0.10/g' >> ~/.ssh/config
```

## Run kubespray-installer/setup.sh script

```shell
cd cord/automation-tools
./setup.sh
```

It fails here as there's an assumption that the login user == remote user on
target machines.

