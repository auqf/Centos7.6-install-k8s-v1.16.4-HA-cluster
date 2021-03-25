#1.执行以下命令来配置kubectl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

#2.使用以下命令安装Calico(参见calico_kubenetes.yaml)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

#3.使用以下命令确认所有Pod正在运行
kubectl get pod --all-namespaces

#5、移除master的污点
kubectl taint nodes --all node-role.kubernetes.io/master-

#6、使用以下命令确认集群中现在有一个节点
kubectl get node -o wide


#7.安装Calicoctl
#二进制安装calicoctl

curl -O -L  https://github.com/projectcalico/calicoctl/releases/download/v3.13.3/calicoctl
mv calicoctl /usr/local/bin/
chmod +x calicoctl

#8.配置calicoctl以连接到Kubernetes API数据存储
#通过命令行设置calicoctl所需的环境变量
DATASTORE_TYPE=kubernetes KUBECONFIG=~/.kube/config calicoctl get nodes
export CALICO_DATASTORE_TYPE=kubernetes
export CALICO_KUBECONFIG=~/.kube/config
calicoctl get workloadendpoints
calicoctl node status