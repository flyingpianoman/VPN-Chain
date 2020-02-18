#!/bin/bash
# exit when any command fails
set -e
sudo su

##
## CONFIG SECTION:
##

# Config array number is used for ordering chain
config[1]=/config/AU_Perth.ovpn
config[2]=/config/Austria.ovpn
#config[3]=config3.ovpn
#config[4]=config4.ovpn

verbose=6           # verbose level; from 0 to 6
enable_firewall=0   # Block outgoing traffic except openvpn servers (HIGHLY RECOMMENDED)

##
## Don't change anything bellow unless you know what you are doing
##

## Code begins:
# Some vars:
vpnchain_helper='/etc/vpnchain/vpnchain_helper.sh'; # set firewall rules file
firewall_rules_file='/config/.vpnchain.firewall'; # set firewall rules file
source '/etc/vpnchain/functions.vpnchain.sh' # read functions file

if [ "$1" = "flush" ]; then
    FIREWALL flush
    rm $firewall_rules_file
    exit
fi
if [ $enable_firewall -gt 0 ] && [ -f "$firewall_rules_file" ]; then
    FIREWALL flush
    rm $firewall_rules_file
fi

#already disabled in the docker-compose by using 'sysctls: - net.ipv6.conf.all.disable_ipv6=1'
#if [ $block_ipv6 -gt 0 ]; then
  #echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6 
#fi

# execute function on exit
trap " ON_EXIT " INT TERM

config_length=${#config[@]};
i=1
tun_array=()

SHOW info "Resolving possible hostnames in config files before disabling routes to DNS servers"
while [ $i -le $config_length ]; do
  # Parse Client's remote server ip from config
  client_remote_ip_or_host=$(grep -v '^#' ${config[$i]} | grep -v '^$' | grep remote\  | awk '{print $2}' | head -n 1)

  if [[ $client_remote_ip_or_host =~ ^[0-9.]+$ ]]; then 
    SHOW info "${config[$i]} listed an IP address" 
    remote_ip=$client_remote_ip_or_host
  else 
    SHOW info "Config ${config[$i]} has remote hostname: $client_remote_ip_or_host"
    remote_ip="$(host $client_remote_ip_or_host | awk '/has address/ { print $4 ; exit }')"
    SHOW info "Config ${config[$i]}: Client remote hostname: $client_remote_ip_or_host, remote IP $remote_ip"
  fi

  remote_ips[i]=$remote_ip

  let i++;
done

i=1
# Loop for configs array:
while [ $i -le $config_length ]; do
  SHOW info "Using config [$i]: ${config[$i]}"
  client_remote_ip="${remote_ips[i]}"

  SHOW info "Remote IP: $client_remote_ip" 

  # For routing purposes we need to get next Client's remote server ip from next config
  let next=$i+1;
  if [ "$next" -le "$config_length" ]; then
    next_client_remote_ip="${remote_ips[next]}"
  else # leave var empty if there is no next config left
    next_client_remote_ip=
  fi

  # Get default gateway for routing purposes
  default_gateway=$(route -nee | awk 'FNR==3 {print $2}')
  SHOW info "Using default gateway: $default_gateway"

  # Check if we don't have last config or if there is only one config set;
  # or else we don't need to provide any route directly to openvpn command. In that case all needed routing is done
  # by vpnchain_helper.sh script
  if [[ "$i" -eq "1" || "$config_length" -eq "1" ]]; then
      openvpn_route="--route $client_remote_ip 255.255.255.255 $default_gateway"
  else
      openvpn_route=
  fi

  # Check if we have last config and if so, we provide different arguments for vpnchain_helper.sh script;
  # or else we proceed normaly
  if [ "$i" -eq "$config_length" ]; then
      openvpn_up="$vpnchain_helper -u -l"
      openvpn_down="$vpnchain_helper -d -l"
  else
      openvpn_up="$vpnchain_helper -u $next_client_remote_ip"
      openvpn_down="$vpnchain_helper -d $next_client_remote_ip"
  fi

  # We need to get available tun device (that is not currently in use). Yes, openvpn can detect this automaticaly,
  # but in our case we need to assign them manualy, because we need to put them in array for function that checks
  # if all chains are connected. Maybe this can be done in more elegant way...
  GET_TUN
  client_tun="tun$i"

  if [ -z "$tun_array" ]; then
    tun_array=( "$client_tun" )
  else
    tun_array=( "${tun_array[@]}" "$client_tun" )
  fi

# Block all outgoing traffic except openvpn servers

  if  [ $enable_firewall -gt 0 ]; then
    if [[ -n "$client_remote_ip" && "$i" -eq "1" ]]; then
        SHOW info "Add firewall exception for ${config[$i]}"
        FIREWALL add "-d $client_remote_ip -j ACCEPT"
    fi
  fi

  # Start vpn connection
  SHOW info "Starting vpn connection ${config[$i]}"
  CONNECT

  SHOW info "Wait for vpnclient to connect"
  while [ -z "$(cat /proc/net/dev | grep -o $client_tun)" ]
  do
    SHOW info "Waiting for $client_tun..."
    sleep 1s;
  done
  
  SHOW info "Client tuner found, assuming it connected"

  # If all connections done, then we jump to chains connection checking function
  if [ "$i" -eq "$config_length" ]; then
    SHOW info "Checking connection chain"
    CHECK_CONNECTION
  fi

  sleep 5s

  let i++;
done

#if [ $block_ipv6 -gt 0 ]; then
#  echo 0 > /proc/sys/net/ipv6/conf/all/disable_ipv6
#fi

exit
