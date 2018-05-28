# Interface configuration

CORD will require various interfaces bonded then bridged, when used with VTN.

This playbook creates interfaces in the following topology for both fabric and
management networks. The example below is for the fabric interfaces - replace
`fabric` with `management` for all variable names for that interface:

A bond interface is defined, named `fabricbond`, which contains physical
interfaces connected to the switching fabric.

A `fabricbridge` is defined, which contains:

- fabricbond (containing with physical interfaces)
- veth pairs for connecting to VM's and containers

The bridge is assigned an IP address, specified by `fabric_net_ip_cidr`, which
is an IP address in CIDR format (ex: `10.234.56.7/8`) which is used to create
the IP address of the interface, it's network mask, broadcast address, and so
on. The `ipcalc` tool can be useful for calculating these values.

The interface configuration files are stored in
`/etc/network/interfaces.d/management.cfg` and
`/etc/network/interfaces.d/fabric.cfg`.

Once these files are created, the interfaces they describe are brought up using
`ifup`, and should be recreated if the system reboots.

## Using the playbook

### Defining an Inventory

An example ansible inventory is given in `example-inventory.yaml`, and uses the
[YAML inventory
format](https://docs.ansible.com/ansible/latest/plugins/inventory/yaml.html)

For this playbook to function, you must define one or both of the the
`fabric_net_ip_cidr` or `management_net_ip_cidr` variables as described above
for each host.  If you don't define one of these variables, the corresponding
bridge or bond will not be created.

### Running the playbook

`ansible-playbook -i <inventory_file> prep-interfaces-playbook.yaml`

## Selecting interfaces

There are three ways to select which interfaces are added to each bond. You may
use these additively in any combination - they'll simply add more interfaces to
the bond.

The three methods are:

- *By interface name*: Specific interface names can be listed for each bond.
  This is useful if you have a specific configuration and know the names of
  interfaces before you configure the system, or if you have multiple of the
  same manufacturer of NIC.  This is used by adding interface names (as listed
  in `ansible_intefaces` when running the `setup` task) to the
  `(fabric|management)_net_interfaces` list.

- *By kernel module name*: By creating a list of kernel module names for the
  bond device, interfaces can be selected. For example, every interface
  using the `em` or `mlx4` driver might be in the `fabric` bond.  The specific
  driver names can be found by running ansible's setup module on a host, and
  looking through the output.  For example, if you have an interface on the
  system named `eth0`, the driver name would befound in `ansible_eth0.module`.
  This is used by adding kernel module names to the
  `(fabric|management)_net_kmods` list.

- *By hardware (MAC) address*: The MAC addresses of the interfaces can be
  listed. This can be useful in systems where the intefaces change names
  through kernel or driver updates.  This is used by adding 48-bit hardware
  addresses in the lowercase, zero padded, colon delimited hex format
  (`01:23:45:67:89:ab`) to the `(fabric|management)_net_hwaddrs` list.

These variables are optional, and set on a per-host basis. Not setting them
will result in an empty bond in a bridge.

