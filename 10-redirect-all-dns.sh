#!/bin/sh

# set these values to your secondary DNS - in my case this is NextDNS
BACKUP_IP4_DNS=45.90.28.161,45.90.30.161
BACKUP_IP6_DNS=2a07:a8c0::45:dea4,2a07:a8c1::45:dea4

# set these values to your Pi-Hole's IP Address
PIHOLE_IP4_HOST=192.168.1.2
PIHOLE_IP6_HOST=2600:6c65:757f:b21f:beef:beef:beef:beef

# set this to the list of hosts that should never be redirected
IP4_NO_REDIRECT="${PIHOLE_IP4_HOST},192.168.1.1"
IP6_NO_REDIRECT="${PIHOLE_IP6_HOST}"

# this shouldn't have to be changed
TABLE_NAME=nat
CHAIN_NAME=dns-redirect-prerouting

####################################
# NOTHING BELOW HERE SHOULD CHANGE #
####################################
function create_rules {
    IPTABLES=$1
    BACKUP_DNS=$2
    PIHOLE_HOST=$3
    NO_REDIRECT=$4

    # this line may faile if the chain does not already exist, that's fine
    ${IPTABLES} -t nat -F ${CHAIN_NAME} >/dev/null 2>&1
    # this line may fail if there are already redirect rules to the chain or the chain does not exist, but you can ignore that
    ${IPTABLES} -t nat -X ${CHAIN_NAME} >/dev/null 2>&1 
    # this line will fail if the previous line failed, but you can ignore that
    ${IPTABLES} -t nat -N ${CHAIN_NAME} >/dev/null 2>&1


    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -d ${BACKUP_DNS} -j RETURN
    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -s ${NO_REDIRECT} -p tcp --dport 53 -j RETURN
    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} -s ${NO_REDIRECT} -p udp --dport 53 -j RETURN
    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} ! -s ${PIHOLE_HOST} -p tcp --dport 53 -j DNAT --to ${PIHOLE_HOST}
    ${IPTABLES} -t ${TABLE_NAME} -A ${CHAIN_NAME} ! -s ${PIHOLE_HOST} -p udp --dport 53 -j DNAT --to ${PIHOLE_HOST}


    TCP_REDIRECT_RULE="PREROUTING -p tcp --dport 53 -j ${CHAIN_NAME}"
    UDP_REDIRECT_RULE="PREROUTING -p udp --dport 53 -j ${CHAIN_NAME}"
    ${IPTABLES} -t ${TABLE_NAME} -C ${TCP_REDIRECT_RULE} >/dev/null 2>&1 || ${IPTABLES} -t nat -A ${TCP_REDIRECT_RULE}
    ${IPTABLES} -t ${TABLE_NAME} -C ${UDP_REDIRECT_RULE} >/dev/null 2>&1 || ${IPTABLES} -t nat -A ${UDP_REDIRECT_RULE}


    UDP_MASQUERADE_RULE="POSTROUTING -p udp --dport 53 -j MASQUERADE"
    TCP_MASQUERADE_RULE="POSTROUTING -p tcp --dport 53 -j MASQUERADE"
    ${IPTABLES} -t ${TABLE_NAME} -C ${TCP_MASQUERADE_RULE} >/dev/null 2>&1 || ${IPTABLES} -t ${TABLE_NAME} -A ${TCP_MASQUERADE_RULE}
    ${IPTABLES} -t ${TABLE_NAME} -C ${UDP_MASQUERADE_RULE} >/dev/null 2>&1 || ${IPTABLES} -t ${TABLE_NAME} -A ${UDP_MASQUERADE_RULE}
}

create_rules iptables ${BACKUP_IP4_DNS} ${PIHOLE_IP4_HOST} ${IP4_NO_REDIRECT}
create_rules ip6tables ${BACKUP_IP6_DNS} ${PIHOLE_IP6_HOST} ${IP6_NO_REDIRECT}
