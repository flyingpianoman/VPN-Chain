#!/bin/bash
CONTROL_OPTS="--script-security 2 --up-delay --up /etc/openvpn/tunnelUp.sh --down /etc/openvpn/tunnelDown.sh"

exec openvpn ${CONTROL_OPTS} ${OPENVPN_OPTS} --config "${OPENVPN_CONFIG}"
