#!/bin/bash
#
# This script is developed to delete and clena the specific Consul iptables rules created by
# command: "consul connect redirect-traffic"
#
# We are using specific deletion of certain iptables chains because we don't to flush all the iptables,
# so other rules created that are required will remain (Consul DNS forward rules, for example)
#
# Color
RED=$(tput setaf 1)
BLUE=$(tput setaf 4)
DGRN=$(tput setaf 2)
GRN=$(tput setaf 10)
YELL=$(tput setaf 3)
NC=$(tput sgr0) #No color

CHAINS=("CONSUL_PROXY_INBOUND" "CONSUL_PROXY_IN_REDIRECT" "CONSUL_PROXY_REDIRECT" "CONSUL_DNS_REDIRECT" "CONSUL_PROXY_OUTPUT")

# Function to get the status of the NAT rules
info () {
  echo "---"
  sudo iptables -L -t nat
  echo "---"
}

# Function to delete some specific rules that are references in other chains, so we remove dependencies
clean_deps () {
  # Set the rule number for the chains that are dependent in PREROUTING and OUTPUT chains
  RULNUM_PREROUTING="$(sudo iptables -L PREROUTING -t nat --line-numbers | grep CONSUL_PROXY_INBOUND | awk '{print $1}')"
  RULNUM_OUTPUT="$(sudo iptables -L OUTPUT -t nat --line-numbers | grep CONSUL_PROXY_OUTPUT | awk '{print $1}')"
  # And we delete those rules by their number
  sudo iptables -D PREROUTING $RULNUM_PREROUTING -t nat
  sudo iptables -D OUTPUT $RULNUM_OUTPUT -t nat
}

# Function to delete all the chains. It first flush them and then delete, just in case
delete_chains () {
  echo "${GRN}==> Flushing all required chains...${NC}"
  for i in ${CHAINS[@]};do
    echo "Flushing $i..."
    sudo iptables -F $i -t nat
  done

  echo -e "\n"

  echo "${GRN}==> Deleting all required chains...${NC}"
  for i in ${CHAINS[@]};do
    echo "Deleting $i..."
    sudo iptables -X $i -t nat
  done
}

# ---------------
# Fun starts here
# ---------------

echo "These are all the iptables rules for NAT: "
info
echo ""
echo -e "\n${YELL}We are deleting the following iptables chains: ${NC}"
for i in ${CHAINS[@]};do
  echo $i
done
echo ""
read -p "${YELL}Do you want to continue? (Any key to continue or Crtl-C to cancel)...$NC}"
echo ""
clean_deps
echo ""
delete_chains
echo ""
echo "${GRN}==> Checking status of iptables after deleting Consul chains...${NC}"
info