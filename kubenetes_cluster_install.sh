#! /bin/bash


TOKEN=auqf
etcd1=10.10.206.87
etcd2=10.10.206.88
etcd3=10.10.206.89
ETCDHOSTS=(etcd1 etcd2 etcd3)
NAMES=(node01 node02 node03)
master1=$etcd1
master2=$etcd2
master3=$etcd3
proxy=auqf.jslife.com

#init hosts file
cat >> /etc/hosts << EOF
$etcd1 node01
$etcd2 node02
$etcd3 node03
EOF

#init ssh login by no password key
[ ! -f $HOME/.ssh/id_rsa ] && ssh-keygen -t rsa -b 2048 -N "" -f $HOME/.ssh/id_rsa

if ! grep -Ff $HOME/.ssh/id_rsa.pub $HOME/.ssh/authorized_keys &>/dev/null; then
  cat $HOME/.ssh/id_rsa.pub >>$HOME/.ssh/authorized_keys
fi

chmod 600 $HOME/.ssh/authorized_keys

#modify the network mode to bridge
cat <<EOF >  /usr/lib/sysctl.d/00-system.conf
	net.bridge.bridge-nf-call-ip6tables = 1
	net.bridge.bridge-nf-call-iptables = 1
EOF

#init the system config && init the etcd cluster && init k8s cluster
for i in "${!ETCDHOSTS[@]}"; do
    HOST=${ETCDHOSTS[$i]}
    NAME=${NAMES[$i]}
        # config the ssh login by no password
	yum install -y rsync
    rsync -a $HOME/.ssh/id_rsa* $HOME/.ssh/authorized_keys -e 'ssh -o StrictHostKeyChecking=no -o CheckHostIP=no' root@$HOST:/root/.ssh/
    
    # init the system config
    ssh $HOST "\hostnamectl set-hostname $NAME"
	ssh $HOST "\systemctl disable firewalld && systemctl stop firewalld"
	ssh $HOST "\setenforce 0 && sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config"
	ssh $HOST "\swapoff -a"
	ssh $HOST "\swapoff -a && sed -i.bak '/swap/s/^/#/' /etc/fstab"
    
    #init the etcd cluster config file
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
    ssh $HOST "\yum install -y etcd"
    scp /tmp/$NAME.conf $HOST:
	scp /usr/lib/sysctl.d/00-system.conf $HOST:/usr/lib/sysctl.d/
    ssh $HOST "\mv -f $NAME.conf /etc/etcd/etcd.conf && service etcd start"
    rm -f /tmp/$NAME.conf
    etcdctl member list
    etcdctl cluster-health
    #init k8s cluster yum repo
    wget -P /etc/yum.repos.d/  https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
    cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg
EOF
    scp /etc/yum.repos.d/*.repo $HOST:/etc/yum.repos.d/
    yum install -y docker-ce kubelet kubeadm kubectl --disableexcludes=kubernetes
    cat >> /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": ["https://5z6d320l.mirror.aliyuncs.com"],
"exec-opts": ["native.cgroupdriver=systemd"]
}
EOF
    systemctl enable docker && systemctl restart docker
    systemctl enable kubelet && systemctl restart kubelet
    systemctl restart chronyd
done

cat << EOF > kubeadm-config.yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
kubernetesVersion: stable
apiServer:
  certSANs:
  - "$proxy"
etcd:
  external:
    endpoints:
    - "http://$etcd1:2379"
    - "http://$etcd2:2379"
    - "http://$etcd3:2379"
networking:
    podSubnet: "10.244.0.0/16"
controlPlaneEndpoint: "$proxy:6443"
imageRepository: registry.cn-hangzhou.aliyuncs.com/google_containers
EOF
kubeadm init --config kubeadm-config.yaml 2>&1 > res.out
cat << EOF > certificate_files.txt
/etc/kubernetes/pki/ca.crt
/etc/kubernetes/pki/ca.key
/etc/kubernetes/pki/sa.key
/etc/kubernetes/pki/sa.pub
/etc/kubernetes/pki/front-proxy-ca.crt
/etc/kubernetes/pki/front-proxy-ca.key
EOF
# create the archive
tar -czPf control-plane-certificates.tar.gz -T certificate_files.txt
masters=($etcd1 $etcd2 $etcd3)
for host in ${masters[@]:1}; do
    scp control-plane-certificates.tar.gz $host:
	mkdir -p /etc/kubernetes/pki && tar -xzPf control-plane-certificates.tar.gz -C /etc/kubernetes/pki --strip-components 3
	ssh	$host "\mkdir -p /etc/kubernetes/pki && tar -xzPf control-plane-certificates.tar.gz -C /etc/kubernetes/pki --strip-components 3"
done

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

echo "Please Read The res.out For The Subsequent Operations"

#安装flannel网络插件，在任意master节点上执行
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
# 查看etcd集群状态
kubectl get cs      
# 查看系统服务状态
kubectl get pods -o wide -n kube-system 
# 查看集群节点状态
kubectl get nodes
