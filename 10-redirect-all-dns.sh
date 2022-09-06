#!/bin/bash

# set these values to your secondary DNS - in my case this is NextDNS
# I also leave an escape hatch to quad9
BACKUP_IP4_DNS=45.90.28.161,45.90.30.161,9.9.9.9
BACKUP_IP6_DNS=2a07:a8c0::45:dea4,2a07:a8c1::45:dea4

# set these values to your Pi-Hole's IP Address
PIHOLE_IP4_HOST=192.168.151.2
PIHOLE_IP6_HOST=2600:6c65:757f:b21f:beef:beef:beef:beef

# set this to the list of hosts that should never be redirected
IP4_NO_REDIRECT="${PIHOLE_IP4_HOST},192.168.151.3,192.168.151.1"
IP6_NO_REDIRECT="${PIHOLE_IP6_HOST}"

# set this to eth8 if using the RJ45 port, or eth9 if using SFP
IFACE=eth9

# this shouldn't have to be changed
TABLE_NAME=nat
CHAIN_NAME=dns-redirect-prerouting

####################################
# NOTHING BELOW HERE SHOULD CHANGE #
####################################
function remove_rules {
    IPTABLES=$1
    CHAIN=$2

    # this line may fail if the chain does not already exist, that's fine
    ${IPTABLES} -t nat -F ${CHAIN} >/dev/null 2>&1
    # this line may fail if there are already redirect rules to the chain or the chain does not exist, but you can ignore that
    ${IPTABLES} -t nat -X ${CHAIN} >/dev/null 2>&1 
}

function create_rules {
    IPTABLES=$1
    BACKUP_DNS=$2
    PIHOLE_HOST=$3
    NO_REDIRECT=$4
    TRANSPARENT_REDIRECT=${5:-true}

    echo "iptables command: ${IPTABLES}"
    echo "backup dns: ${BACKUP_DNS}"
    echo "pihole host: ${PIHOLE_HOST}"
    echo "no redirect: ${NO_REDIRECT}"
    echo "transparent redirect: ${TRANSPARENT_REDIRECT}"

    remove_rules ${IPTABLES} ${CHAIN_NAME}
    # this line will fail if the previous line failed, but you can ignore that
    ${IPTABLES} -t nat -N ${CHAIN_NAME} >/dev/null 2>&1


    # uncomment this to allow direct access to the backup DNS
    # ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -d ${BACKUP_DNS} -j RETURN

    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -s ${NO_REDIRECT} -p tcp --dport 53 -j RETURN
    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -s ${NO_REDIRECT} -p udp --dport 53 -j RETURN

    # uncomment these lines to do transparent redirection
    if [ ! -z "${TRANSPARENT_REDIRECT}" ]; then
        ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} ! -s ${PIHOLE_HOST} -p tcp --dport 53 -j DNAT --to ${PIHOLE_HOST}
        ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} ! -s ${PIHOLE_HOST} -p udp --dport 53 -j DNAT --to ${PIHOLE_HOST}
    fi
    
    ${IPTABLES} -A FORWARD -o ${IFACE} -s ${NO_REDIRECT} -p tcp --dport 53 -j ACCEPT
    ${IPTABLES} -A FORWARD -o ${IFACE} -s ${NO_REDIRECT} -p udp --dport 53 -j ACCEPT
    ${IPTABLES} -A FORWARD -o ${IFACE} -p tcp --dport 53 -j REJECT
    ${IPTABLES} -A FORWARD -o ${IFACE} -p udp --dport 53 -j REJECT

    TCP_REDIRECT_RULE="PREROUTING -p tcp --dport 53 -j ${CHAIN_NAME}"
    UDP_REDIRECT_RULE="PREROUTING -p udp --dport 53 -j ${CHAIN_NAME}"
    ${IPTABLES} -t ${TABLE_NAME} -C ${TCP_REDIRECT_RULE} >/dev/null 2>&1 || ${IPTABLES} -t nat -A ${TCP_REDIRECT_RULE}
    ${IPTABLES} -t ${TABLE_NAME} -C ${UDP_REDIRECT_RULE} >/dev/null 2>&1 || ${IPTABLES} -t nat -A ${UDP_REDIRECT_RULE}


    UDP_MASQUERADE_RULE="POSTROUTING -p udp --dport 53 -j MASQUERADE"
    TCP_MASQUERADE_RULE="POSTROUTING -p tcp --dport 53 -j MASQUERADE"
    ${IPTABLES} -t ${TABLE_NAME} -C ${TCP_MASQUERADE_RULE} >/dev/null 2>&1 || ${IPTABLES} -t ${TABLE_NAME} -A ${TCP_MASQUERADE_RULE}
    ${IPTABLES} -t ${TABLE_NAME} -C ${UDP_MASQUERADE_RULE} >/dev/null 2>&1 || ${IPTABLES} -t ${TABLE_NAME} -A ${UDP_MASQUERADE_RULE}
}

function create_ipv6_dns_block_rules {
    ip6tables -t OUTPUT -A -p tcp --dport 53 -j REJECT
    ip6tables -t OUTPUT -A -p udp --dport 53 -j REJECT
}

if [ "$1" = "stop" ]; then
    remove_rules ip6tables ${CHAIN_NAME}
    remove_rules iptables ${CHAIN_NAME}
    exit
fi

create_rules iptables ${BACKUP_IP4_DNS} ${PIHOLE_IP4_HOST} ${IP4_NO_REDIRECT}
if [[ -z ${DISABLE_IP6_DNS} ]]; then
    create_rules ip6tables ${BACKUP_IP6_DNS} ${PIHOLE_IP6_HOST} ${IP6_NO_REDIRECT}
else
    create_ipv6_dns_block_rules
fi
