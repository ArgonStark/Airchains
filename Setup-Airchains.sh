#!/bin/bash

set -e

# Update and install packages
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y

# Install Go
VERSION="1.21.6"
ARCH="amd64"
curl -O -L "https://golang.org/dl/go${VERSION}.linux-${ARCH}.tar.gz"
tar -xf "go${VERSION}.linux-${ARCH}.tar.gz"
sudo rm -rf /usr/local/go
sudo mv -v go /usr/local
export GOPATH=$HOME/go
export PATH=$PATH:/usr/local/go/bin:$GOPATH/bin
source ~/.bash_profile
go version

# Setup EVM station service
git clone https://github.com/airchains-network/evm-station.git
git clone https://github.com/airchains-network/tracks.git

# Setup the station
rm -r ~/.evmosd || true
cd ~/evm-station
git checkout --detach v1.0.2
go mod tidy
/bin/bash ./scripts/local-setup.sh

# Create env file
cd ~
cat << EOF > .rollup-env
MONIKER="localtestnet"
KEYRING="test"
KEYALGO="eth_secp256k1"
LOGLEVEL="info"
HOMEDIR="$HOME/.evmosd"
TRACE=""
BASEFEE=1000000000
CONFIG=$HOMEDIR/config/config.toml
APP_TOML=$HOMEDIR/config/app.toml
GENESIS=$HOMEDIR/config/genesis.json
TMP_GENESIS=$HOMEDIR/config/tmp_genesis.json
VAL_KEY="mykey"
EOF

# Create evmosd service file
sudo tee /etc/systemd/system/evmosd.service > /dev/null << EOF
[Unit]
Description=ZK
After=network.target

[Service]
User=root
EnvironmentFile=/root/.rollup-env
ExecStart=/root/evm-station/build/station-evm start --metrics "" --log_level info --json-rpc.api eth,txpool,personal,net,debug,web3 --chain-id "stationevm_1234-1"
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# Start evmosd service
sudo systemctl enable evmosd
sudo systemctl start evmosd
echo "Evmosd Started Successfully ..."

# Backup EVM private-key
cd evm-station
/bin/bash ./scripts/local-keys.sh

read -p "Did you save your private key? (Y/N) " response
if [[ "$response" != "Y" ]]; then
  echo "Please save your private key before continuing."
  exit 1
fi

# Changing evmosd ports
sudo systemctl stop evmosd

echo "export G_PORT='17'" >> $HOME/.bash_profile
source $HOME/.bash_profile

sed -i.bak -e "s%:1317%:${G_PORT}317%g;
s%:8080%:${G_PORT}080%g;
s%:9090%:${G_PORT}090%g;
s%:9091%:${G_PORT}091%g;
s%:8545%:${G_PORT}545%g;
s%:8546%:${G_PORT}546%g;
s%:6065%:${G_PORT}065%g" $HOME/.evmosd/config/app.toml

sed -i.bak -e "s%:26658%:${G_PORT}658%g;
s%:26657%:${G_PORT}657%g;
s%:6060%:${G_PORT}060%g;
s%:26656%:${G_PORT}656%g;
s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):${G_PORT}656\"%;
s%:26660%:${G_PORT}660%g" $HOME/.evmosd/config/config.toml

sed -i -e 's/address = "127.0.0.1:17545"/address = "0.0.0.0:17545"/' -e 's/ws-address = "127.0.0.1:17546"/ws-address = "0.0.0.0:17546"/' $HOME/.evmosd/config/app.toml

sudo ufw allow 17545
sudo ufw allow 17546

# Start evmosd service again
sudo systemctl start evmosd
echo "Evmosd Started Successfully ..."

# Setup EigenDA Keys
cd ~
wget https://github.com/airchains-network/tracks/releases/download/v0.0.2/eigenlayer

# Create and List Keys
chmod +x ./eigenlayer
./eigenlayer operator keys create --key-type ecdsa myEigenDAKey

read -p "Did you save your EigenDA key? (Y/N) " response
if [[ "$response" != "Y" ]]; then
  echo "Please save your EigenDA key before continuing."
  exit 1
fi

# Setup and Run Tracker
sudo rm -rf ~/.tracks
cd tracks
go mod tidy

read -p "Enter your EigenDA address: " eigen_address
go run cmd/main.go init --daRpc "disperser-holesky.eigenda.xyz" --daKey "$eigen_address" --daType "eigen" --moniker "mySequencer" --stationRpc "http://127.0.0.1:17545" --stationAPI "http://127.0.0.1:17545" --stationType "evm"

read -p "Enter your Switchyard Secret phrase: " mnemonic
go run cmd/main.go keys import --accountName mySequencerAccount --accountPath $HOME/.tracks/junction-accounts/keys --mnemonic "$mnemonic"

# Initiating Prover
go run cmd/main.go prover v1EVM

node_id=$(cat ~/.tracks/config/sequencer.toml | grep node_id | cut -d '"' -f 2)
echo "Node ID: $node_id"
read -p "Did you save your node ID? (Y/N) " response
if [[ "$response" != "Y" ]]; then
  echo "Please save your node ID before continuing."
  exit 1
fi

read -p "Enter your Airchain address: " tracker_wallet_address
go run cmd/main.go create-station --accountName mySequencerAccount --accountPath $HOME/.tracks/junction-accounts/keys --jsonRPC "https://junction-testnet-rpc.synergynodes.com/" --info "EVM Track" --tracks "$tracker_wallet_address" --bootstrapNode "/ip4/127.0.0.1/tcp/2300/p2p/$node_id"

# Create stationd service file
sudo tee /etc/systemd/system/stationd.service > /dev/null << EOF
[Unit]
Description=station track service
After=network-online.target

[Service]
User=root
WorkingDirectory=/root/tracks/
ExecStart=/usr/local/go/bin/go run cmd/main.go start
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

# Running stationd service
sudo systemctl enable stationd
sudo systemctl restart stationd
echo "Stationd Started Successfully ..."

echo "Setup completed successfully."
