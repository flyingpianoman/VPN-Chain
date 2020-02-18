##
## Don't change anything bellow unless you know what you are doing
##

# Make openvpn connection
function CONNECT() {
    openvpn --verb $verbose --script-security 2 --config ${config[$i]} --dev $client_tun --remote $client_remote_ip --route-nopull --allow-pull-fqdn $openvpn_route --up "$openvpn_up" --down "$openvpn_down" &
}

# Get available tun devices
function GET_TUN() {
  client_tun=
  tun_number=`cat /proc/net/dev | grep tun | head -n 1 | awk '{print substr($1,4,1)}'`
  if [ -z "$tun_number" ]; then
      tun_number=0
    else
      let tun_number=$tun_number+1;
  fi
  client_tun="tun$tun_number"
  SHOW info "Client tun: $client_tun";
}

# Check if value exists in array
function IN_ARRAY() {
    local array item=$1
    shift
    for array; do
        [[ $array == $item ]] && return 0
    done
    return 1
}

# Check if all chain is connected
function CHECK_CONNECTION() {
local t=0
local first=1
local tun_length=${#tun_array[@]};
local tun_connected=
local tun_disconnected=
local disconnect=0

while [ -n "$disconnect" ]
  do
      tun_connected=("`cat /proc/net/dev | grep tun | cut -d ':' -f1`")
      t=0
      for z in "${tun_array[@]}"
      do
	if ( IN_ARRAY $z ${tun_connected[@]} )
	then
	  let t=$t+1
	  if [ "$first" -eq "1" ]; then
	    SHOW info "Connected $z..."	Green
	  fi
	fi
      done
      if [ "$first" -eq "1" ]; then
	    SHOW info "Chain is connected... Please check your IP to make sure."	Green
	    SHOW info "Press CTRL+C to disconnect."	Green
      fi
      first=0
      sleep 2s
done

}

# SHOW debug messages with colors
function SHOW() {
  Escape="\033"; Black="${Escape}[30m"; Red="${Escape}[31m"; Green="${Escape}[32m"; Yellow="${Escape}[33m";
  Blue="${Escape}[34m"; Purple="${Escape}[35m"; Cyan="${Escape}[36m"; White="${Escape}[37m"; Reset="${Escape}[0m";

  if [ "$1" = "info" ]; then
    if [ -n "$3" ]; then
	eval echo -en "\$$3[`date +"%T"`] INFO: $2"
	echo -e "${Reset}"
      else
	echo -e "${Yellow}[`date +"%T"`] INFO: $2 ${Reset}"
    fi
  elif [ "$1" = "error" ]; then
    echo -e "${Red}[`date +"%T"`] ERROR: $2 ${Reset}"
  else
    echo -e "${White}[`date +"%T"`] $2 ${Reset}"
  fi

}

function FIREWALL() {

 if [ -z "$firewall_times_called" ] && [ "$1" != 'flush' ]; then
    firewall_times_called=0;
    firewall_iptables_array=()
    firewall_non_vpn="192.168.1.0/24 192.168.0.0/24 172.27.0.0/24 10.4.9.0/24 127.0.0.0/9 127.128.0.0/10"
    firewall_default_output_policy=`iptables -L OUTPUT -n | awk 'FNR==1 {print $4}' | sed 's/)//'`
    echo "iptables -P OUTPUT $firewall_default_output_policy" >> $firewall_rules_file
    
    iptables -P OUTPUT DROP 
    SHOW info "iptables -P OUTPUT DROP"
    for NET in $firewall_non_vpn; do
     iptables -I OUTPUT 1 -d $NET -j ACCEPT
     SHOW info "iptables -I OUTPUT 1 -d $NET -j ACCEPT"
     echo "iptables -D OUTPUT -d $NET -j ACCEPT" >> $firewall_rules_file
    done
    iptables -I OUTPUT 1 -o tun+ -j ACCEPT
    echo "iptables -D OUTPUT -o tun+ -j ACCEPT" >> $firewall_rules_file
 fi
 if [ "$1" = "add" ]; then
    shift # remove 'add' from arguments
    iptables -I OUTPUT 3 $@
    SHOW info "iptables -I 3 $@"
    echo "iptables -D OUTPUT $@" >> $firewall_rules_file
    firewall_iptables_array=( "${firewall_iptables_array[@]}" "$@" )
 fi

 if [ "$1" = "flush" ]; then        
    if [ -f "$firewall_rules_file" ]; then
      flush_rules=$(grep -v '^#' $firewall_rules_file);
      grep -v '^#' $firewall_rules_file | while read LINE ; do        
        SHOW info "Deleting rule: $LINE"
          $LINE
        done
    
    else
        SHOW error "No firewall rules file. Nothing to flush!"
        exit
    fi
 fi 
 
 if [ "$1" != 'flush' ]; then
      let firewall_times_called=$firewall_times_called+1;
 fi
}

function ON_EXIT() {
# Kill all VPN connections on script exit
SHOW info "Killing openvpn instances..."
pkill openvpn
sleep 5s
SHOW info "Disconnected."
if  [ $enable_firewall -gt 0 ]; then
  SHOW info "Don't forget to flush firewall rules: \"sudo ./`basename $0` flush\""
fi
exit
}
