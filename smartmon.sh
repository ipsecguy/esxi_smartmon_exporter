#!/bin/bash
# Script informed by the collectd monitoring script for smartmontools (using smartctl)
# by Samuel B. <samuel_._behan_(at)_dob_._sk> (c) 2012
# source at: http://devel.dob.sk/collectd-scripts/

# TODO: This probably needs to be a little more complex.  The raw numbers can have more
#       data in them than you'd think.
#       http://arstechnica.com/civis/viewtopic.php?p=22062211

# modified https://github.com/prometheus/node_exporter/blob/master/text_collector_examples/smartmon.sh
#
# TODO: better login parameters on command line (user/password/key etc)
# Andreas

if [ "$#" -ne 1 ]; then
  echo "Illegal number of parameters"
  exit
fi

ESXIHOST=$1

# better use public key here
SSH="timeout 5s sshpass -p <PASSWORD> ssh -o StrictHostKeyChecking=no root@$ESXIHOST"


#
# I did changes here - use four labels for one metric instead of four metrics
# this however makes the data look different to the one produced by the node exporter textcollector
# change it back if that fits better to your environment
#
parse_smartctl_attributes_awk="$(cat << 'SMARTCTLAWK'
$1 ~ /^[0-9]+$/ && $2 ~ /^[a-zA-Z0-9_-]+$/ {
  gsub(/-/, "_");
  printf "%s{attr=\"value\",%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, tolower($4)
  printf "%s{attr=\"worst\",%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, tolower($5)
  printf "%s{attr=\"threshold\",%s,smart_id=\"%s\"} %d\n", tolower($2), labels, $1, tolower($6)
  printf "%s{attr=\"raw_value\",%s,smart_id=\"%s\"} %e\n", tolower($2), labels, $1, tolower($10)
}
SMARTCTLAWK
)"

parse_smartctl_attributes() {
  local disk="$1"
  local disk_type="$2"
  local extralabels="$3"
  local labels="disk=\"${disk}\",type=\"${disk_type}\",${extralabels}"
  sed 's/^ \+//g' \
    | awk -v labels="${labels}" "${parse_smartctl_attributes_awk}" 2>/dev/null
}

parse_smartctl_info() {
  local -i smart_available=0 smart_enabled=0 smart_healthy=0
  local disk="$1" disk_type="$2"
  while read line ; do
    info_type="$(echo "${line}" | cut -f1 -d: | tr ' ' '_')"
    info_value="$(echo "${line}" | cut -f2- -d: | sed 's/^ \+//g' | sed 's/\"//g')" # filter characters 
    case "${info_type}" in
      Model_Family) model_family="${info_value}" ;;
      Device_Model) device_model="${info_value}" ;;
      Serial_Number) serial_number="${info_value}" ;;
      Firmware_Version) fw_version="${info_value}" ;;
      Vendor) vendor="${info_value}" ;;
      Product) product="${info_value}" ;;
      Revision) revision="${info_value}" ;;
      Logical_Unit_id) lun_id="${info_value}" ;;
    esac
    if [[ "${info_type}" == 'SMART_support_is' ]] ; then
      case "${info_value:0:7}" in
        Enabled) smart_enabled=1 ;;
        Availab) smart_available=1 ;;
        Unavail) smart_available=0 ;;
      esac
    fi
    if [[ "${info_type}" == 'SMART_overall-health_self-assessment_test_result' ]] ; then
      case "${info_value:0:6}" in
        PASSED) smart_healthy=1 ;;
      esac
    elif [[ "${info_type}" == 'SMART_Health_Status' ]] ; then
      case "${info_value:0:2}" in
        OK) smart_healthy=1 ;;
      esac
    fi
  done
  if [[ -n "${device_model}" ]] ; then
    echo "device_info{disk=\"${disk}\",type=\"${disk_type}\",model_family=\"${model_family}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",firmware_version=\"${fw_version}\"} 1"
  else
    # RAID Controller Logical Drive - at least mine does not have S.M.A.R.T.
    # construct some readable names
    model_family="${vendor} ${product}"
    device_model="${vendor} ${product} ${revision}"
    serial_number=${lun_id}
    echo "device_info{disk=\"${disk}\",type=\"${disk_type}\",vendor=\"${vendor}\",product=\"${product}\",revision=\"${revision}\",lun_id=\"${lun_id}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\",firmware_version=\"${revision}\"} 1"
  fi
  echo "device_smart_available{disk=\"${disk}\",type=\"${disk_type}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\"} ${smart_available}"
  echo "device_smart_enabled{disk=\"${disk}\",type=\"${disk_type}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\"} ${smart_enabled}"
  echo "device_smart_healthy{disk=\"${disk}\",type=\"${disk_type}\",device_model=\"${device_model}\",serial_number=\"${serial_number}\"} ${smart_healthy}"

  # Hack - return parameters. As we are in a Subshell, global vars would not work
  echo "LABEL device_model=\"${device_model}\",serial_number=\"${serial_number}\""
}

output_format_awk="$(cat << 'OUTPUTAWK'
BEGIN { v = "" }
v != $1 {
  print "# HELP smartmon_" $1 " SMART metric " $1;
  print "# TYPE smartmon_" $1 " gauge";
  v = $1
}
{print "smartmon_" $0}
OUTPUTAWK
)"

format_output() {
  sort \
  | awk -F'{' "${output_format_awk}"
}


# main program

# smartctl_version="$(/usr/sbin/smartctl -V | head -n1  | awk '$1 == "smartctl" {print $2}')"
smartctl_version="$($SSH '/opt/smartmontools/smartctl -V' | head -n1)"

echo "smartctl_version{version=\"${smartctl_version}\"} 1" | format_output

# defunct version check
#if [[ "$(expr "${smartctl_version}" : '\([0-9]*\)\..*')" -lt 6 ]] ; then
#  exit
#fi

# device_list="$(/usr/sbin/smartctl --scan-open | awk '{print $1 "|" $3}')"
device_list="$($SSH 'esxcli storage core device list' | awk '/^[A-Za-z]/{printf "\n/dev/disks/" $0 } /Is SAS:/{ printf ($3=="true") ? "|scsi" : "|sat" } /Is SSD:/{printf ($3=="true") ? "|ssd" : "|hdd"}')"

for device in ${device_list}; do
  disk="$(echo ${device} | cut -f1 -d'|')"
  media="$(echo ${device} | cut -f2 -d'|')" # hdd oder ssd
  type="$(echo ${device} | cut -f3 -d'|')" # sat oder scsi (SATA/SCSI)
  echo "smartctl_run{disk=\"${disk}\",type=\"${type}\"}" $(TZ=UTC date '+%s')

  # Get the SMART information and health
  # /usr/sbin/smartctl -i -H -d "${type}" "${disk}" | parse_smartctl_info "${disk}" "${type}"
  info=$($SSH "/opt/smartmontools/smartctl -i -H -d ${type} ${disk}" | parse_smartctl_info "${disk}" "${type}")
  echo "$info" | egrep -v "^LABEL"

  extralabel="media=\"${media}\","$(echo "$info" | awk '/^LABEL/{print substr($0,7)}')

  # Get the SMART attributes
  # /usr/sbin/smartctl -A -d "${type}" "${disk}" | parse_smartctl_attributes "${disk}" "${type}"
  $SSH "/opt/smartmontools/smartctl -A -d ${type} ${disk}" | parse_smartctl_attributes "${disk}" "${type}" "${extralabel}"

done | format_output
