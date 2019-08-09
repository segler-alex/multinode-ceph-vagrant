#!/bin/bash

set -e

DEBIAN_FRONTEND=noninteractive apt-get update && apt-get install -yq ntp ceph-deploy

mkdir -p /root/.ssh
cp .ssh/id_rsa .ssh/id_rsa.pub /root/.ssh
cp .ssh/id_rsa.pub /root/.ssh/authorized_keys
mkdir -p test-cluster
cd test-cluster
ssh-keyscan -H -t rsa ceph-server-1 ceph-server-2 ceph-server-3 ceph-client > /root/.ssh/known_hosts
ceph-deploy install --release=mimic ceph-admin ceph-server-1 ceph-server-2 ceph-server-3 ceph-client
ceph-deploy new ceph-server-1 ceph-server-2 ceph-server-3
echo "mon_clock_drift_allowed = 1" >> ceph.conf
ceph-deploy mon create-initial

ssh ceph-server-2 "sudo mkdir /var/local/osd0 && sudo chown ceph:ceph /var/local/osd0"
ssh ceph-server-3 "sudo mkdir /var/local/osd1 && sudo chown ceph:ceph /var/local/osd1"

ceph-deploy admin ceph-admin ceph-server-1 ceph-server-2 ceph-server-3 ceph-client

chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-1 sudo chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-2 sudo chmod +r /etc/ceph/ceph.client.admin.keyring
ssh ceph-server-3 sudo chmod +r /etc/ceph/ceph.client.admin.keyring

ceph-deploy mgr create ceph-server-1

ceph-deploy osd prepare ceph-server-2:/var/local/osd0 ceph-server-3:/var/local/osd1
ceph-deploy osd activate ceph-server-2:/var/local/osd0 ceph-server-3:/var/local/osd1
