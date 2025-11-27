#!/bin/bash

# This script checks the status of the upstream Linux Mint server and the local mirror.
# It compares the last modification time of a reference file 
# and checks the following conditions:
#
# - If the upstream mirror has new updates, the local mirror fetches them
# - If the upstream mirror was updated less than 12 hours ago, the local mirror is considered up-to-date and no action is taken.
# - If the upstream mirror was updated more than 24 hours ago it synchronizes again
#
# This script is intended to be run repeatedly by a systemd timer.

# Metadata of the mirror
MIRROR_DIRECTORY=/srv/linux-mint
LOCAL_MIRROR="lidsol.fi-b.unam.mx"
MIRROR_DIRECTORY_SO=${MIRROR_DIRECTORY}/images
LATEST_UPDATE_FILE=latest_sync_images.meta

mkdir -p ${MIRROR_DIRECTORY_SO}

MAIN_SERVER_URL=https://pub.linuxmint.io
MAIN_SERVER_RSYNC=pub.linuxmint.com::pub
function get_upstream_time(){
      dates=()
      while IFS= read -r line; do
      dates+=("$line")
      done < <(curl -s --compressed "$MAIN_SERVER_URL" \
        | grep -Eo '[0-9]{2}-[A-Za-z]{3}-[0-9]{4} [0-9]{2}:[0-9]{2}')
      local latest=""
      local latest_epoch=0
      # In case we don't receive any date for connection problems
      if [ ${#dates[@]} -eq 0 ]; then
        echo "1970-01-01 00:00:00 UTC"
        return
      fi

      for d in "${dates[@]}"; do
            converted_date=$(echo "$d" | awk '{
                  split($1, parts, "-")
                  day = parts[1]
                  month = parts[2]
                  year = parts[3]
                  time = $2
                  
                  # Convert month name to number
                  if (month == "Jan") month = "01"
                  else if (month == "Feb") month = "02"
                  else if (month == "Mar") month = "03"
                  else if (month == "Apr") month = "04"
                  else if (month == "May") month = "05"
                  else if (month == "Jun") month = "06"
                  else if (month == "Jul") month = "07"
                  else if (month == "Aug") month = "08"
                  else if (month == "Sep") month = "09"
                  else if (month == "Oct") month = "10"
                  else if (month == "Nov") month = "11"
                  else if (month == "Dec") month = "12"
                  
                  printf "%s-%s-%s %s:00", year, month, day, time
            }')
            epoch=$(date -d "$converted_date" +"%s" 2>/dev/null)
            if [[ $? -eq 0 && $epoch -gt $latest_epoch ]]; then
                  latest_epoch=$epoch
                  latest="$converted_date"
            fi
      done

      echo "$latest UTC"
}

function get_local_time() {
    if [ -f ${MIRROR_DIRECTORY}/${LATEST_UPDATE_FILE} ]; then
        head -n 1 ${MIRROR_DIRECTORY}/${LATEST_UPDATE_FILE}
    else
        echo "1970-01-01 00:00:00 UTC" >${MIRROR_DIRECTORY}/${LATEST_UPDATE_FILE}
        echo "1970-01-01 00:00:00 UTC"
    fi
}

function should_pull()
{
    local_mirror_time=$1
    upstream_time=$2
    current_time=$3
    # Log input of function to stderr
    local_mirror_time_epoch=$(date -d "$local_mirror_time" +%s)
    upstream_time_epoch=$(date -d "$upstream_time" +%s)
    current_time_epoch=$(date -d "$current_time" +%s)

    #If the local mirror is older than 24 hours, the it will update automatically
    if [ $(($current_time_epoch - $local_mirror_time_epoch)) -gt 86400 ]; then
        echo "true"
        return
    fi

    #If the local mirror is younger than 12 hours, then it's not necessary to update it
    if [ $(($current_time_epoch - $local_mirror_time_epoch)) -lt 43200  ]; then
        
        echo "false"
        return
    fi

    # If the local mirror is older than the upstream mirror, then the local mirror
    # is considered out of date
    if [ $local_mirror_time_epoch -lt $upstream_time_epoch ]; then
        echo "true"
    else
        echo "false"
    fi
}

if [ $(should_pull "$(get_local_time)" "$(get_upstream_time)" "$(date -u)") == "true" ]; then
    echo "Local mirror is out of date, pulling from upstream mirror. Upstream date: $(get_upstream_time), Local date: $(get_local_time) - current date: $(date -u)"
    new_date="$(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    if rsync -av --delete --partial \
      ${MAIN_SERVER_RSYNC} ${MIRROR_DIRECTORY_SO}; then
    sed -i "1s/.*/$new_date/" ${MIRROR_DIRECTORY}/${LATEST_UPDATE_FILE}
    else
        echo "Error: rsync failed"
        exit 1
    fi  
else
    echo "Local mirror is up to date. Upstream date: $(get_upstream_time), Local date: $(get_local_time) - current date: $(date -u)"
fi
