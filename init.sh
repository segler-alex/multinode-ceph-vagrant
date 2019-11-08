#!/bin/bash

export CEPH_RELEASE="nautilus"

set -e

# add ceph repository
wget -q -O- 'https://download.ceph.com/keys/release.asc' | sudo apt-key add -
echo deb https://download.ceph.com/debian-${CEPH_RELEASE}/ $(lsb_release -sc) main | sudo tee /etc/apt/sources.list.d/ceph.list

# install self
DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -yq ntp ceph-deploy jq

# Keys
mkdir -p /root/.ssh
cp .ssh/id_rsa .ssh/id_rsa.pub /root/.ssh
cp .ssh/id_rsa.pub /root/.ssh/authorized_keys
ssh-keyscan -H -t rsa ceph-server-1 ceph-server-2 ceph-server-3 ceph-client > /root/.ssh/known_hosts

# setup config
mkdir -p test-cluster
cd test-cluster
ceph-deploy install --release=${CEPH_RELEASE} ceph-admin ceph-server-1 ceph-server-2 ceph-server-3 ceph-client
ceph-deploy new ceph-server-1 ceph-server-2 ceph-server-3
echo "mon_clock_drift_allowed = 1" >> ceph.conf
echo "rbd default features = 5" >> ceph.conf
echo "[mon]" >> ceph.conf
echo "mon_allow_pool_delete = true" >> ceph.conf

# other dependencies
ssh ceph-server-1 DEBIAN_FRONTEND=noninteractive apt install -yq ceph-mgr-dashboard python-routes

# ceph-deploy
ceph-deploy mon create-initial
ceph-deploy admin ceph-admin ceph-server-1 ceph-server-2 ceph-server-3 ceph-client
ceph-deploy mgr create ceph-server-1
ceph-deploy rgw create ceph-server-1
ceph-deploy mds create ceph-server-1

# keyrings
chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-1 sudo chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-2 sudo chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-3 sudo chmod +r /etc/ceph/ceph.client.admin.keyring

# setup osd
ceph-deploy osd create --bluestore --data /dev/sdc ceph-server-1
ceph-deploy osd create --bluestore --data /dev/sdc ceph-server-2
ceph-deploy osd create --bluestore --data /dev/sdc ceph-server-3

# ceph fs setup
ceph osd pool create cephfs_data 8
ceph osd pool create cephfs_metadata 8
ceph fs new cephfs cephfs_metadata cephfs_data

# rbd pool setup
ceph osd pool create rbd 8
ceph osd pool application enable rbd rbd

# ceph dashboard
ceph mgr module enable dashboard
ceph dashboard create-self-signed-cert
ceph config set mgr mgr/dashboard/ssl false
ceph config set mgr mgr/dashboard/server_port 7000
ceph config set mgr mgr/dashboard/ssl_server_port 8443

# create rgw user
radosgw-admin user create --uid=system --display-name=system --system
ACCESS_KEY=$(radosgw-admin user info --uid=system | jq -r '.keys[0].access_key')
SECRET_KEY=$(radosgw-admin user info --uid=system | jq -r '.keys[0].secret_key')

# set rgw accesskey/secret to dashboard
ceph dashboard set-rgw-api-access-key $ACCESS_KEY
ceph dashboard set-rgw-api-secret-key $SECRET_KEY

# create dashboard admin user
ceph dashboard ac-user-create administrator password administrator

# restart dashboard
ceph mgr module disable dashboard
ceph mgr module enable dashboard