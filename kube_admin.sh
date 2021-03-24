#! /bin/bash

etcd1=10.10.206.87
etcd2=10.10.206.88
etcd3=10.10.206.89
ETCDHOSTS=(etcd1 etcd2 etcd3)
NAMES=(node01 node02 node03)
masters=($etcd1 $etcd2 $etcd3)
proxy=auqf.jslife.com

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
kubeadm init --config kubeadm-config.yaml

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
for host in ${masters[@]:1}; do
    scp control-plane-certificates.tar.gz $host:
	mkdir -p /etc/kubernetes/pki && tar -xzPf control-plane-certificates.tar.gz -C /etc/kubernetes/pki --strip-components 3
	ssh	$host "\mkdir -p /etc/kubernetes/pki && tar -xzPf control-plane-certificates.tar.gz -C /etc/kubernetes/pki --strip-components 3"
done

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
