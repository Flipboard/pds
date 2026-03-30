#!/usr/bin/env bash
#
# run as ubuntu

set -o errexit
set -o xtrace

if [[ $(whoami) != 'ubuntu' ]]; then
    echo 'This script must be run as ubuntu.'
    exit 1
fi

if [[ $# -eq 0 ]] ; then
    echo 'git commit hash must be passed as an argument'
    exit 1
fi

SRC_DIR="/mnt/jenkins-bluesky/workspace/${2}"
TARGET_DIR="/home/bluesky"
DATE=$(date +%Y%m%dT%H%M)
GIT_COMMIT="$1"

# save 1 level of backups
sudo rm -rfd "${TARGET_DIR}/"backup.*
sudo rm -rfd "${TARGET_DIR}/"*.tar.gz
sudo rm -rfd "${TARGET_DIR}/"updater_post_install.sh
sudo chmod -f 755 "${TARGET_DIR}"

# copy over current code
sudo cp -r "${SRC_DIR}" "${TARGET_DIR}"

# tar and upload
tar cvf ${GIT_COMMIT}.tar .
gzip ${GIT_COMMIT}.tar
aws s3 cp ${GIT_COMMIT}.tar.gz s3://flipboard.prod.releases/bluesky/${GIT_COMMIT}.tar.gz

exit 0

