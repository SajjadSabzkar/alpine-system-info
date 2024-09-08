#!/usr/bin/env bash
apk update
apk upgrade
#lshw
apk add lshw --repository=https://dl-cdn.alpinelinux.org/alpine/edge/community

#system_info
cat << 'EOF' > /usr/sbin/system_info.sh
#!/bin/sh

BASE_DIR="/home/mr/reports"  
mkdir -p $BASE_DIR

LATEST_INDEX=$(ls -v $BASE_DIR | grep -E '^system_info_([0-9]+)\.html$' | sed -E 's/system_info_([0-9]+)\.html/\1/' | tail -n 1)
if [[ -z "$LATEST_INDEX" ]]; then
    NEXT_INDEX=1
else
    NEXT_INDEX=$((LATEST_INDEX + 1))
fi

NEW_FILE="$BASE_DIR/system_info_$NEXT_INDEX.html"

lshw -html > "$NEW_FILE"

echo "System Information Data Saved in : $NEW_FILE"

#poweroff
EOF
#chmod file
chmod +x  /usr/sbin/system_info.sh
#change root password
echo -e "live\nlive\n" | passwd root

#auto login
cat << 'EOF'> /usr/sbin/autologin
#!/bin/sh
exec login -f root
EOF
#chmod 
chmod +x /usr/sbin/autologin
#replace autologin script
sed -i 's@:respawn:/sbin/getty@:respawn:/sbin/getty -n -l /usr/sbin/autologin@g' /etc/inittab 


