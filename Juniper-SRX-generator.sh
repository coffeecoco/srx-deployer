#!/usr/bin/env bash -e

cat <<HEREDOC
delete applications
delete security address-book
delete security nat
delete security policies
HEREDOC

while IFS=, read SOURCE_ZONE DESTINATION_ZONE PROTOCOL SOURCE_IP SOURCE_PORT DESTINATION_IP DESTINATION_PORT NAT_DESTINATION_IP NAT_DESTINATION_PORT SERVICE DESCRIPTION; do

  # Waarom? "ANY" -> "any"
  SOURCE_IP=${SOURCE_IP,,}
  SOURCE_PORT=${SOURCE_PORT,,}
  DESTINATION_IP=${DESTINATION_IP,,}
  DESTINATION_PORT=${DESTINATION_PORT,,}
  PROTOCOL=${PROTOCOL,,}

#  case ${DESTINATION_PORT} in
#    22) APPLICATION=junos-ssh;;
#    80) APPLICATION=junos-http;;
#    443) APPLICATION=junos-https;;
#    3306) APPLICATION=mysql;;
#    5432) APPLICATION=pgsql;;
#    8140) APPLICATION=puppet;;
#  esac
  
  APPLICATION=application-$PROTOCOL-$SOURCE_PORT-$DESTINATION_PORT
  SOURCE_PORT=${SOURCE_PORT/any/1-65535}
  DESTINATION_PORT=${DESTINATION_PORT/any/1-65535}

  echo set applications application $APPLICATION protocol $PROTOCOL source-port $SOURCE_PORT destination-port $DESTINATION_PORT inactivity-timeout $[60 * 60 * 24]

  if [[ -n "$NAT_DESTINATION_IP" ]]; then 
# ########## DNAT ###########

# Waarom? Hierom:
# root@fw1# set security nat static pool 172.16.1.1 address 172.16.1.1    
# error: pool-name: '172.16.1.1': Must be a string beginning with a number or letter and consisting of letters, numbers, dashes and underscores.
    NAT_POOL=${NAT_DESTINATION_IP//\./_}

# Waarom? Beestje moet naam hebben.
    NAT_RULESET=${SOURCE_ZONE}

# Waarom? Hierom:
# root@fw1# set security nat static rule-set $SOURCE_ZONE-to-DMZ rule 172.16.1.1-80       
# error: rule-name: '172.16.1.1-80': Must be a string beginning with a number or letter and consisting of letters, numbers, dashes and underscores.
    NAT_RULE=${DESTINATION_IP//\./_}-${NAT_DESTINATION_IP//\./_}-${DESTINATION_PORT}

    echo set security nat proxy-arp interface $InternetInterface address $DESTINATION_IP/32
    echo set security address-book global address $NAT_DESTINATION_IP $NAT_DESTINATION_IP
    echo set security nat static rule-set $NAT_RULESET from zone $SOURCE_ZONE
    echo set security nat static rule-set $NAT_RULESET rule $NAT_RULE match destination-address $DESTINATION_IP
    echo set security nat static rule-set $NAT_RULESET rule $NAT_RULE match destination-port $DESTINATION_PORT
    echo set security nat static rule-set $NAT_RULESET rule $NAT_RULE then static-nat prefix $NAT_DESTINATION_IP mapped-port $NAT_DESTINATION_PORT
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $NAT_RULE match source-address $SOURCE_IP
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $NAT_RULE match destination-address $NAT_DESTINATION_IP
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $NAT_RULE match application $APPLICATION 
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $NAT_RULE then permit

  else 
# ########## Geen DNAT ###########
    FW_RULE=FW-${SOURCE_IP//\./_}-${DESTINATION_IP//\./_}-${DESTINATION_PORT}

    if [[ "$SOURCE_IP" != "any" ]]; then
      echo set security address-book global address $SOURCE_IP $SOURCE_IP
    fi
    if [[ "$DESTINATION_IP" != "any" ]]; then
      echo set security address-book global address $DESTINATION_IP $DESTINATION_IP
    fi
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $FW_RULE match source-address $SOURCE_IP
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $FW_RULE match destination-address $DESTINATION_IP
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $FW_RULE match application $APPLICATION
    echo set security policies from-zone $SOURCE_ZONE to-zone $DESTINATION_ZONE policy $FW_RULE then permit
  fi

done

cat <<HEREDOC
set security policies global policy deny-logger match source-address any destination-address any application any
set security policies global policy deny-logger then log session-init 
set security policies global policy deny-logger then deny
set security nat source rule-set SNAT-To-Internet from zone Beheerders
set security nat source rule-set SNAT-To-Internet from zone DMZ-Beheer
set security nat source rule-set SNAT-To-Internet from zone DMZ-Productie
set security nat source rule-set SNAT-To-Internet from zone Database-Beheer
set security nat source rule-set SNAT-To-Internet from zone Database-Productie
set security nat source rule-set SNAT-To-Internet to zone Internet
set security nat source rule-set SNAT-To-Internet rule SNAT-To-Internet match source-address 0.0.0.0/0
set security nat source rule-set SNAT-To-Internet rule SNAT-To-Internet match destination-address 0.0.0.0/0
set security nat source rule-set SNAT-To-Internet rule SNAT-To-Internet then source-nat interface
HEREDOC

