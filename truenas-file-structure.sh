#!/bin/bash

# Prompt the user for the pool name
read -p "Enter the pool name: " POOLNAME

# Define datasets and directories
CONFIG_DATASETS=("prowlarr" "radarr" "sonarr" "jellyseerr" "recyclarr" "bazarr" "tdarr" "plex" "qbittorrent" "dozzle")
TDARR_SUBDIRS=("server" "logs" "transcode_cache")
MEDIA_SUBDIRECTORIES=("movies" "tv" "downloads")
DOCKER_COMPOSE_PATH="/mnt/$POOLNAME/docker"

# Function to create and set up a dataset
create_dataset() {
    local dataset_name="$1"
    local dataset_path="$POOLNAME/$dataset_name"
    local mountpoint="/mnt/$dataset_path"

    if ! zfs list "$dataset_path" >/dev/null 2>&1; then
        echo "Creating dataset: $dataset_path"
        zfs create "$dataset_path"
    fi

    # Ensure dataset is mounted
    if ! mountpoint -q "$mountpoint"; then
        echo "Mounting dataset: $dataset_path"
        zfs mount "$dataset_path"
    fi

    # Verify mount exists before applying permissions
    if [ -d "$mountpoint" ]; then
        chown apps:apps "$mountpoint"
        chmod 770 "$mountpoint"
    else
        echo "⚠️ Warning: $mountpoint does not exist after mounting. Check dataset status."
    fi
}

# Function to create a directory if it doesn't exist
create_directory() {
    local dir_path="$1"
    if [ ! -d "$dir_path" ]; then
        echo "Creating directory: $dir_path"
        mkdir -p "$dir_path"
        chown apps:apps "$dir_path"
        chmod 770 "$dir_path"
    else
        echo "Directory already exists: $dir_path, skipping..."
    fi
}

# Create the "configs" dataset (parent)
create_dataset "configs"

# Create the config datasets
for dataset in "${CONFIG_DATASETS[@]}"; do
    create_dataset "configs/$dataset"
done

# Create the "media" dataset (instead of a directory)
create_dataset "media"

# Create subdirectories inside the media dataset
for subdir in "${MEDIA_SUBDIRECTORIES[@]}"; do
    create_directory "/mnt/$POOLNAME/media/$subdir"
done

# Ensure Tdarr subdirectories exist (only if tdarr dataset is properly mounted)
TDARR_MOUNTPOINT="/mnt/$POOLNAME/configs/tdarr"
if mountpoint -q "$TDARR_MOUNTPOINT"; then
    for subdir in "${TDARR_SUBDIRS[@]}"; do
        create_directory "$TDARR_MOUNTPOINT/$subdir"
    done
else
    echo "⚠️ Skipping tdarr subdirectory creation; dataset is not mounted."
fi
# Ensure Docker Compose directory exists
create_directory "$DOCKER_COMPOSE_PATH"

# Ensure the Docker Compose file path exists
DOCKER_COMPOSE_FILE="$DOCKER_COMPOSE_PATH/docker-compose.yml"
if [ ! -d "$DOCKER_COMPOSE_PATH" ]; then
    echo "⚠️ Docker Compose directory missing, creating: $DOCKER_COMPOSE_PATH"
    mkdir -p "$DOCKER_COMPOSE_PATH"
fi

# Generate docker-compose.yml
docker_compose_file="$docker_compose_path/docker-compose.yml"


cat > "$DOCKER_COMPOSE_FILE" <<EOF
version: '3.9'

networks:
  media_network:
    driver: bridge

services:
  prowlarr:
    image: linuxserver/prowlarr
    container_name: prowlarr
    restart: unless-stopped
    ports:
      - 9696:9696
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/prowlarr:/config
      - /mnt/$POOLNAME/media:/media

  radarr:
    image: linuxserver/radarr
    container_name: radarr
    restart: unless-stopped
    ports:
      - 7878:7878
    environment:
      - PUID=568
      - PGID=568
      - TZ=Australia/Melbourne
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/radarr:/config
      - /mnt/$POOLNAME/media:/media

  sonarr:
    image: linuxserver/sonarr
    container_name: sonarr
    restart: unless-stopped
    ports:
      - 8989:8989
    environment:
      - PUID=568
      - PGID=568
      - TZ=Australia/Melbourne
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/sonarr:/config
      - /mnt/$POOLNAME/media:/media

  jellyseerr:
    image: fallenbagel/jellyseerr
    container_name: jellyseerr
    restart: unless-stopped
    ports:
      - 5055:5055
    environment:
      - TZ=Australia/Melbourne
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/jellyseerr:/app/config

  recyclarr:
    image: ghcr.io/recyclarr/recyclarr
    user: 568:568
    container_name: recyclarr
    restart: unless-stopped
    environment:
      CRON_SCHEDULE: 0 0 * * *
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/recyclarr:/config

  bazarr:
    image: linuxserver/bazarr
    container_name: bazarr
    restart: unless-stopped
    ports:
      - 6767:6767
    environment:
      - PUID=568
      - PGID=568
      - TZ=Australia/Melbourne
    networks:
      - media_network
    volumes:
      - /mnt/$POOLNAME/configs/bazarr:/config
      - /mnt/$POOLNAME/media:/media

  tdarr:
    container_name: tdarr
    image: ghcr.io/haveagitgat/tdarr:latest
    restart: unless-stopped
    ports:
      - 8265:8265 # webUI port
      - 8266:8266 # server port
    environment:
      - TZ=Australia/Melbourne
      - PUID=568
      - PGID=568
      - UMASK_SET=002
      - serverIP=0.0.0.0
      - serverPort=8266
      - webUIPort=8265
      - internalNode=true
      - inContainer=true
      - ffmpegVersion=6
      - nodeName=MyInternalNode
      - NVIDIA_DRIVER_CAPABILITIES=all
      - NVIDIA_VISIBLE_DEVICES=all
    volumes:
      - /mnt/$POOLNAME/configs/tdarr:/app/config
      - /mnt/$POOLNAME/configs/tdarr/server:/app/server
      - /mnt/$POOLNAME/configs/tdarr/logs:/app/logs
      - /mnt/$POOLNAME/configs/tdarr/transcode_cache:/temp
      - /mnt/$POOLNAME/media:/media

    devices:
      - /dev/dri:/dev/dri
  #  deploy:
  #    resources:
  #      reservations:
  #        devices:
  #        - driver: nvidia
  #          count: all
  #          capabilities: [gpu]
    networks:
      - media_network

  qbittorrent:
    container_name: qbittorrent
    image: ghcr.io/hotio/qbittorrent
    restart: unless-stopped
    ports:
      - 8080:8080
    environment:
      - PUID=568
      - PGID=568
      - UMASK=002
      - TZ=Australia/Melbourne
      - WEBUI_PORTS=8080/tcp,8080/udp
      - VPN_ENABLED=true
      - VPN_CONF=wg0
      - VPN_PROVIDER=generic
      - VPN_LAN_NETWORK=10.99.0.0/24
      - VPN_EXPOSE_PORTS_ON_LAN=
      - VPN_AUTO_PORT_FORWARD=true
      - VPN_AUTO_PORT_FORWARD_TO_PORTS=5687
      - VPN_KEEP_LOCAL_DNS=false
      - VPN_FIREWALL_TYPE=auto
      - PRIVOXY_ENABLED=false
      - UNBOUND_ENABLED=false
    cap_add:
      - NET_ADMIN
    sysctls:
      - net.ipv4.conf.all.src_valid_mark=1
      - net.ipv6.conf.all.disable_ipv6=1
    volumes:
      - /mnt/$POOLNAME/configs/qbittorrent:/config
      - /mnt/$POOLNAME/media:/media

  dozzle:
    image: amir20/dozzle
    container_name: dozzle
    restart: unless-stopped
    ports:
      - '8888:8080'
    networks:
      - media_network
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /mnt/$POOLNAME/configs/dozzle:/data
EOF

echo "Docker Compose file created at $DOCKER_COMPOSE_FILE"
echo "Script completed."
