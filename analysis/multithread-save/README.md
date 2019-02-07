# Multithread Save

With loglevel DEBUG, the XOS synchronizers will write to the logs when a
particular model is saved.  This tool pulls the information about object
saves from the logs and analyzes it.  The goal is to identify potential race
conditions caused by the same field being saved from multiple tasks, where a
task is a sync step, event step, pull step, or model policy.

For each model, the tool will print a warning if `save()` was called on a
model that hadn't changed (it's better to use `save_if_changed()`).  For fields
in the model that were saved from code in two or more files, it will print out
the file paths.  The idea is that these files should be scrutinized to make
sure the object is being updated in a safe way.

## Usage

```bash
./analyze_logs.sh
```

## Sample Output
```text
Inspecting model:  RCORDSubscriber

Inspecting model:  OLTDevice
  [WARNING] Object being saved with no changes
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
  [WARNING] Field saved from multiple tasks:  oper_status
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
     /opt/xos/synchronizers/volt/steps/sync_olt_device.py
  [WARNING] Field saved from multiple tasks:  of_id
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
     /opt/xos/synchronizers/volt/steps/sync_olt_device.py
  [WARNING] Field saved from multiple tasks:  serial_number
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
     /opt/xos/synchronizers/volt/steps/sync_olt_device.py
  [WARNING] Field saved from multiple tasks:  backend_status
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
     /opt/xos/synchronizers/volt/steps/sync_olt_device.py
  [WARNING] Field saved from multiple tasks:  device_id
     /opt/xos/synchronizers/volt/pull_steps/pull_olts.py
     /opt/xos/synchronizers/volt/steps/sync_olt_device.py

Inspecting model:  VOLTServiceInstance
  [WARNING] Object being saved with no changes
     /opt/xos/synchronizers/volt/steps/sync_volt_service_instance.py
  [WARNING] Field saved from multiple tasks:  onu_device_id
     /opt/xos/synchronizers/volt/steps/sync_volt_service_instance.py
     /opt/xos/synchronizers/volt/model_policies/model_policy_voltserviceinstance.py
  [WARNING] Field saved from multiple tasks:  subscribed_links_ids
     /opt/xos/synchronizers/volt/steps/sync_volt_service_instance.py
     /opt/xos/synchronizers/volt/model_policies/model_policy_voltserviceinstance.py

Inspecting model:  ONUDevice

Inspecting model:  AttWorkflowDriverWhiteListEntry
  [WARNING] Object being saved with no changes
     /opt/xos/synchronizers/att-workflow-driver/model_policies/model_policy_att_workflow_driver_whitelistentry.py
```
