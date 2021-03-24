#! /bin/bash

TOKEN=auqf
ETCDHOSTS=(10.10.206.87 10.10.206.88 10.10.206.89)
NAMES=(node01 node02 node03)


[ ! -f $HOME/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -N "" -f $HOME/.ssh/id_rsa

if ! grep -Ff $HOME/.ssh/id_rsa.pub $HOME/.ssh/authorized_keys &>/dev/null; then
  cat $HOME/.ssh/id_rsa.pub >>$HOME/.ssh/authorized_keys
fi
chmod 600 $HOME/.ssh/authorized_keys

for i in "${!ETCDHOSTS[@]}"; do
    HOST=${ETCDHOSTS[$i]}
    NAME=${NAMES[$i]}
    yum install -y rsync
    rsync -a $HOME/.ssh/id_rsa* $HOME/.ssh/authorized_keys -e 'ssh -o StrictHostKeyChecking=no -o CheckHostIP=no' root@$HOST:/root/.ssh/
    cat << EOF > /tmp/$NAME.conf
# [member]
ETCD_NAME=$NAME
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://$HOST:2380"
ETCD_LISTEN_CLIENT_URLS="http://$HOST:2379,http://127.0.0.1:2379"
#[cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$HOST:2380"
ETCD_INITIAL_CLUSTER="${NAMES[0]}=http://${ETCDHOSTS[0]}:2380,${NAMES[1]}=http://${ETCDHOSTS[1]}:2380,${NAMES[2]}=http://${ETCDHOSTS[2]}:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="$TOKEN"
ETCD_ADVERTISE_CLIENT_URLS="http://$HOST:2379"
EOF
    ssh $HOST "yum install -y etcd"
    scp /tmp/$NAME.conf $HOST:
    ssh $HOST "\mv -f $NAME.conf /etc/etcd/etcd.conf"
    ssh $HOST "\service etcd start"
    rm -f /tmp/$NAME.conf
done

etcdctl member list
etcdctl cluster-health
