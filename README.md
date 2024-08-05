# Airchains

Run the script : 

``` 
wget https://raw.githubusercontent.com/ArgonStark/Airchains/main/Setup-Airchains.sh && chmod +x Setup-Airchains.sh  && ./Setup-Airchains.sh 
```

Now Run the script to transact : 
```
git clone https://github.com/sarox0987/evmos-farmer.git
cd evmos-farmer
```

Now open screen :

```
screen -S farm
```

```
go mod tidy
go run main.go
```
Enter your EVM private-key 
Enter this for RPC : 

```
http://127.0.0.1:17545
```
این رو وارد کنید


Press ctrl A + D and exit the screen !

Open another screen : 
```
screen -S fix
```

```
nano fix.sh
```

Paste all this code in fix.sh : 

```
service_name="stationd"
error_strings=(
  "ERROR"
  "with gas used"
  "Failed to Init VRF"
  "Client connection error: error while requesting node"
  "Error in getting sender balance : http post error: Post"
  "rpc error: code = ResourceExhausted desc = request ratelimited"
  "rpc error: code = ResourceExhausted desc = request ratelimited: System blob rate limit for quorum 0"
  "ERR"
  "Retrying the transaction after 10 seconds..."
  "Error in VerifyPod transaction Error"
  "Error in ValidateVRF transaction Error"
  "Failed to get transaction by hash: not found"
  "json_rpc_error_string: error while requesting node"
  "can not get junctionDetails.json data"
  "JsonRPC should not be empty at config file"
  "Error in getting address"
  "Failed to load conf info"
  "error unmarshalling config"
  "Error in initiating sequencer nodes due to the above error"
  "Failed to Transact Verify pod"
  " VRF record is nil"
)
restart_delay=120
config_file="$HOME/.tracks/config/sequencer.toml"

unique_urls=(
  "https://airchains-testnet-rpc.crouton.digital/"
  "https://rpc-testnet-airchains.nodeist.net/"
  "https://airchains-rpc.sbgid.com/"
)

function select_random_url {
  local array=("$@")
  local rand_index=$(( RANDOM % ${#array[@]} ))
  echo "${array[$rand_index]}"
}

function update_rpc_and_restart {
  local random_url=$(select_random_url "${unique_urls[@]}")
  sed -i -e "s|JunctionRPC = \"[^\"]*\"|JunctionRPC = \"$random_url\"|" "$config_file"
  systemctl restart "$service_name"
  echo "Service $service_name restarted"
  echo -e "\e[32mRemoved RPC URL: $random_url\e[0m"
  sleep "$restart_delay"
}

function display_waiting_message {
  echo -e "\e[35mI am waiting for you AIRCHAIN\e[0m"
}

echo "Script started to monitor errors in PC logs..."
echo -e "\e[32mby onixia\e[0m"
echo "Timestamp: $(date)"

while true; do
  logs=$(systemctl status "$service_name" --no-pager | tail -n 10)

  for error_string in "${error_strings[@]}"; do
    if echo "$logs" | grep -q "$error_string"; then
      echo "Found error ('$error_string') in logs, updating $config_file and restarting $service_name..."

      update_rpc_and_restart

      systemctl stop "$service_name"
      cd ~/tracks

      echo "Starting rollback after changing RPC..."
      go run cmd/main.go rollback
      go run cmd/main.go rollback
      go run cmd/main.go rollback
      echo "Rollback completed, restarting $service_name..."

      systemctl start "$service_name"
      display_waiting_message
      break
    fi
  done

  sleep "$restart_delay"
done
```

Ctrl X - Enter Y - to save the file . 

```
chmod +x fix.sh

bash fix.sh
```

Press ctrl A + D and exit !

