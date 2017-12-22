#!/bin/bash

set -e

yum install -y salt-minion

mkdir -p /etc/salt/minion.d

cp /srv/eemt/opal2-vm/salt/salt/sol-vm.conf /etc/salt/minion.d/

salt-call state.highstate

