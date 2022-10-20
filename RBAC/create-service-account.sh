#!/bin/sh

# This shell script is intended for Kubernetes clusters running 1.24+ as secrets are no longer auto-generated with serviceaccount creations
# The script does a few things: creates a serviceaccount, creates a secret for that serviceaccount (and annotates accordingly), creates a clusterrolebinding or rolebinding
# provides a kubeconfig output to the screen as well as writing to a file that can be included in the KUBECONFIG or PATH

# Feed variables to kubectl commands (modify as needed).  crb and rb can not both be true
# ------------------------------------------- #
clustername=cluster.local
name=dev-user
ns=dev-ns # namespace
server=https://192.168.10.11:6443
crb=true # clusterrolebinding
crb_name=crb-dev # clusterrolebindingname_name
rb=false # rolebinding
rb_name=some_binding # rolebinding_name
# ------------------------------------------- #

# Check for existing serviceaccount first
sa_precheck=$(kubectl get sa $name -o jsonpath='{.metadata.name}' -n $ns) > /dev/null 2>&1

if [ -z "$sa_precheck" ]
then 
    kubectl create serviceaccount $name -n $ns
	echo "Creating serviceacccount/"$name""  
else
    echo "serviceacccount/"$sa_precheck" already exists"  
fi

sa_name=$(kubectl get sa $name -o jsonpath='{.metadata.name}' -n $ns)
sa_uid=$(kubectl get sa $name -o jsonpath='{.metadata.uid}' -n $ns)

# Check for existing secret/service-account-token, if one does not exist create one but do not output to external file
secret_precheck=$(kubectl get secret $sa_name-token-$sa_uid -o jsonpath='{.metadata.name}' -n $ns) > /dev/null 2>&1

if [ -z "$secret_precheck" ]
then 
    kubectl apply -f - <<EOF
    apiVersion: v1
    kind: Secret
    type: kubernetes.io/service-account-token
    metadata:
      name: $sa_name-token-$sa_uid
      namespace: $ns
      annotations:
        kubernetes.io/service-account.name: $sa_name
EOF
else
    echo "secret/"$secret_precheck" already exists"
fi

# Check for adding clusterrolebinding or rolebinding (both can not be true)
if [ "$crb" = "true" ] && [ "$rb" = "true" ] 
then
    echo "Both clusterrolebinding and rolebinding can not be true, please fix"
    exit

elif [ "$crb" = "true" ]
then
    crb_test=$(kubectl get clusterrolebinding $crb_name -o jsonpath='{.metadata.name}') > /dev/null 2>&1
    if [ "$crb_name" = "$crb_test" ]
    then
        kubectl patch clusterrolebinding $crb_name --type='json' -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "ServiceAccount", "name": '$sa_name', "namespace": '$ns' } }]'
    else
        echo "clusterrolebinding/"$crb_name" does not exist, creating clusterrolebinding/"$crb_name" with clusterrole=view"
		kubectl create clusterrolebinding $crb_name --clusterrole=view --serviceaccount=$ns:$sa_name
        #exit    
    fi

elif [ "$rb" = "true" ]
then
    rb_test=$(kubectl get rolebinding $rb_name -n $ns -o jsonpath='{.metadata.name}' -n $ns) > /dev/null 2>&1
    if [ "$rb_name" = "$rb_test" ]
    then
        kubectl patch rolebinding $rb_name -n $ns --type='json' -p='[{"op": "add", "path": "/subjects/-", "value": {"kind": "ServiceAccount", "name": '$sa_name', "namespace": '$ns' } }]'
    else 
        echo "rolebinding/"$rb_name" does not exist in "$ns" namespace, please fix"
        exit
    fi
fi

# Create Kube Config and output to config file
ca=$(kubectl get secret $sa_name-token-$sa_uid -o jsonpath='{.data.ca\.crt}' -n $ns)
token=$(kubectl get secret $sa_name-token-$sa_uid -o jsonpath='{.data.token}' -n $ns | base64 --decode)

echo "
apiVersion: v1
kind: Config
clusters:
  - name: ${clustername}
    cluster:
      certificate-authority-data: ${ca}
      server: ${server}
contexts:
  - name: ${sa_name}@${clustername}
    context:
      cluster: ${clustername}
      namespace: ${ns}
      user: ${sa_name}
users:
  - name: ${sa_name}
    user:
      token: ${token}
current-context: ${sa_name}@${clustername}
" | tee $sa_name@${clustername}
