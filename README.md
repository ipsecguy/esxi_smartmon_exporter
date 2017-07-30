# esxi_smartmon_exporter

Prometheus exporter for disk S.M.A.R.T data gathered from devices in an ESXi (VMware hypervisor environment).

The script logs in to the ESXi hosts, iterates through all devices using core storage and tries to gather S.M.A.R.T. data from them using the ported smartmontools on ESXi.

Based on:
- smartmontools https://www.smartmontools.org/
- smartmontools ported to ESXi http://www.virten.net/2016/05/determine-tbw-from-ssds-with-s-m-a-r-t-values-in-esxi-smartctl/
- Node Exporter textcollector example https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/smartmon.sh
- which is based on https://github.com/samsk/collectd-scripts

Major differences to the original Node Exporter textcollector:
- instead of the textcollector script on the node_exporter I am using the pushgateway
- script is logging in to ESXi machine remotely via SSH (timeout bound, password or key-based login)
- using core storage to find all local devices (esxcli storage core device list) instead of smartctl
- changed metric (I do not know whether that is smart) to have a single metric with label value/worst/threshold/raw_value
