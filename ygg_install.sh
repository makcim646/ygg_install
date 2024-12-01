#!/bin/bash

# Website URL
URL="https://publicpeers.neilalexander.dev"

# Temporary file for storing HTML
TEMP_FILE=$(mktemp)

# Path to the Yggdrasil configuration file
YGG_CONF="/etc/yggdrasil/yggdrasil.conf"

# Function to install Yggdrasil
install_yggdrasil() {
  echo "Installing Yggdrasil..."
  apt install dirmngr -y
  mkdir -p /usr/local/apt-keys
  gpg --fetch-keys https://neilalexander.s3.dualstack.eu-west-2.amazonaws.com/deb/key.txt
  gpg --export BC1BF63BD10B8F1A | tee /usr/local/apt-keys/yggdrasil-keyring.gpg > /dev/null
  echo 'deb [signed-by=/usr/local/apt-keys/yggdrasil-keyring.gpg] http://neilalexander.s3.dualstack.eu-west-2.amazonaws.com/deb/ debian yggdrasil' > /etc/apt/sources.list.d/yggdrasil.list

  apt update && apt install yggdrasil -y
}

# Function to fetch the website with IPv4 priority, fallback to IPv6
fetch_site() {
  echo "Trying to fetch the website via IPv4..."
  wget -4 -q -O "$TEMP_FILE" "$URL"
  if [[ $? -ne 0 ]]; then
    echo "Failed to fetch via IPv4, trying IPv6..."
    wget -6 -q -O "$TEMP_FILE" "$URL"
    if [[ $? -ne 0 ]]; then
      echo "Error: Failed to fetch the website via both IPv4 and IPv6."
      return 1
    fi
  fi
  return 0
}

# Install Yggdrasil
install_yggdrasil

# Fetch the website
if ! fetch_site; then
  exit 1
fi

# Extract peers with protocols from the HTML
peers=$(grep -oP '(tcp|quic|tls|ws|wss)://[0-9a-zA-Z:.]+:[0-9]+' "$TEMP_FILE" | sort -u)

# Check if peers were found
if [[ -z "$peers" ]]; then
  echo "Failed to find peers in the HTML."
  rm "$TEMP_FILE"
  exit 1
fi

# Notify about starting ping checks
echo "Checking ping to peers, please wait..."

# Array to store peers and ping times
declare -A ping_times

# Iterate over all peers and measure ping
for peer in $peers; do
  protocol=$(echo "$peer" | awk -F'://' '{print $1}')
  host=$(echo "$peer" | awk -F'://' '{print $2}' | awk -F':' '{print $1}')
  port=$(echo "$peer" | awk -F':' '{print $3}')

  echo "Checking $protocol://$host:$port..."
  ping_time=$(ping -c 1 -W 1 $host | grep 'time=' | awk -F'=' '{print $4}' | awk '{print $1}')

  if [[ -n $ping_time ]]; then
    echo "Peer $protocol://$host:$port - ping $ping_time ms"
    ping_times["$peer"]=$ping_time
  else
    echo "Peer $protocol://$host:$port - unavailable"
  fi
done

# Remove the temporary file
rm "$TEMP_FILE"

# Sort the array by ping time and determine the top 3
echo "Top 3 peers with the lowest ping time:"
best_peers=$(for peer in "${!ping_times[@]}"; do
  echo "$peer ${ping_times[$peer]}"
done | sort -k2 -n | head -n 3 | awk '{print $1}')

# Debug: Check the contents of best_peers
echo "Best peers: $best_peers"

# Check if best peers were found
if [[ -z "$best_peers" ]]; then
  echo "Failed to determine the best peers."
  exit 1
fi

# Prepare the replacement string for the configuration
peers_config=$(printf '"%s", ' $best_peers)
peers_config="[ ${peers_config%, } ]"

sed -i "s|  Peers: \[\]|  Peers: $peers_config|" /etc/yggdrasil/yggdrasil.conf

# Restart Yggdrasil
systemctl restart yggdrasil

