#!/bin/bash

# URL of the site
URL="https://publicpeers.neilalexander.dev"

# Temporary file for storing HTML
TEMP_FILE=$(mktemp)
YGG_CONF="/etc/yggdrasil/yggdrasil.conf"

# Function to fetch the site with IPv4 priority, then IPv6
fetch_site() {
  echo "Trying to fetch the site via IPv4..."
  wget -4 -q -O "$TEMP_FILE" "$URL"
  if [[ $? -ne 0 ]]; then
    echo "Failed to fetch via IPv4, trying IPv6..."
    wget -6 -q -O "$TEMP_FILE" "$URL"
    if [[ $? -ne 0 ]]; then
      echo "Error: failed to fetch the site via both IPv4 and IPv6."
      return 1
    fi
  fi
  return 0
}

# Fetch the site
if ! fetch_site; then
  exit 1
fi

# Extract peers with protocols from HTML
peers=$(grep -oP '(tcp|quic|tls|ws|wss)://[0-9a-zA-Z:.]+:[0-9]+' "$TEMP_FILE" | sort -u)

# Check if peers are found
if [[ -z "$peers" ]]; then
  echo "No peers found in the HTML."
  rm "$TEMP_FILE"
  exit 1
fi

# Notification about starting the ping check
echo "Checking ping for peers, please wait..."

# Array to store peers and their ping times
declare -A ping_times

# Iterate over all peers and measure ping
for peer in $peers; do
  protocol=$(echo "$peer" | awk -F'://' '{print $1}')
  host=$(echo "$peer" | awk -F'://' '{print $2}' | awk -F':' '{print $1}')
  port=$(echo "$peer" | awk -F':' '{print $3}')
  ping_time=$(ping -c 1 -W 1 $host | grep 'time=' | awk -F'=' '{print $4}' | awk '{print $1}')
  
  if [[ -n $ping_time ]]; then
    echo "Peer $protocol://$host:$port - ping $ping_time ms"
    ping_times["$peer"]=$ping_time
  else
    echo "Peer $protocol://$host:$port - unavailable"
  fi
done

# Remove temporary file
rm "$TEMP_FILE"

# Sort peers by ping time and determine top-3
echo "Top 3 peers with the lowest ping:"
best_peers=$(for peer in "${!ping_times[@]}"; do
  echo "$peer ${ping_times[$peer]}"
done | sort -k2 -n | head -n 3 | awk '{print $1}')

# Check the content of best_peers for debugging
echo "Best peers: $best_peers"

# Check if the best peers are found
if [[ -z "$best_peers" ]]; then
  echo "Failed to determine the best peers."
  exit 1
fi

# Remove existing peers that are not in the top-3
echo "Removing old peers..."
sed -i 's/Peers: \[.*\]/Peers: \[\]/' $YGG_CONF

peers_config=$(printf '"%s", ' $best_peers)
peers_config="[ ${peers_config%, } ]"

sed -i "s|  Peers: \[\]|  Peers: $peers_config|" $YGG_CONF

# Restart Yggdrasil
echo "Restarting Yggdrasil to apply changes..."
sudo systemctl restart yggdrasil

if systemctl is-active --quiet yggdrasil; then
  echo "Yggdrasil is running with the updated peers."
else
  echo "Error: Yggdrasil failed to restart."
  exit 1
fi

