%{
  title: "From zero to hero with kops and AWS",
  author: "Gabriel Garrido",
  description: "This is an awesome tool to setup and maintain your clusters, currently only compatible with AWS and GCE...",
  tags: ~w(kubernetes kops aws),
  published: true,
  image: "kubernetes-aws.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![kubernetes](/images/kubernetes-aws.png){:class="mx-auto"}

### **Introduction**
In this article we will create a cluster from scratch with [kops](https://github.com/kubernetes/kops) (K8s installation, upgrades and management) in [AWS](https://aws.amazon.com/), We will configure [aws-alb-ingress-controller](https://github.com/kubernetes-sigs/aws-alb-ingress-controller) (External traffic into our services/pods) and [external dns](https://github.com/kubernetes-incubator/external-dns) (Update the records based in the ingress rules) and also learn a bit about awscli in the process.
<br />

Basically we will have a fully functional cluster that will be able to handle public traffic in minutes, first we will install the cluster with kops, then we will enable the ingress controller and lastly external-dns, then we will deploy a basic app to test that everything works fine, SSL/TLS is out of the scope but it's fairly easy to implement if you are using ACM.
<br />

Just in case you don't know this setup is not going to be free, cheap for sure because we will use small instances, etc, but not completely free, so before you dive in, be sure that you can spend a few bucks testing it out.
<br />

### **Kops**
This is an awesome tool to setup and maintain your clusters, currently only compatible with AWS and GCE, other platforms are planned and some are also supported in alpha, we will be using AWS in this example, it requires kubectl so make sure you have it installed:
```elixir
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops
```
<br />

**Export the credentials that we will be using to create the kops user and policies**
```elixir
export AWS_ACCESS_KEY_ID=XXXX && export AWS_SECRET_ACCESS_KEY=XXXXX
```
You can do it this way or just use `aws configure` and set a profile.
<br />

The next thing that we need are IAM credentials for kops to work, you will need awscli configured and working with your AWS admin-like account most likely before proceeding:
```elixir
# Create iam group
aws iam create-group --group-name kops
# OUTPUT:
# {
#     "Group": {
#         "Path": "/",
#         "GroupName": "kops",
#         "GroupId": "AGPAIABI3O4WYM46AIX44",
#         "Arn": "arn:aws:iam::894527626897:group/kops",
#         "CreateDate": "2019-01-18T01:04:23Z"
#     }
# }

aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name kops

# Attach policies
aws iam create-user --user-name kops
aws iam add-user-to-group --user-name kops --group-name kops
# OUTPUT:
# {
#     "Group": {
#         "Path": "/",
#         "GroupName": "kops",
#         "GroupId": "AGPAIABI3O4WYM46AIX44",
#         "Arn": "arn:aws:iam::894527626897:group/kops",
#         "CreateDate": "2019-01-18T01:04:23Z"
#     }
# }

# Create access key - save the output of this command.
aws iam create-access-key --user-name kops
# OUTPUT:
# {
#     "AccessKey": {
#         "UserName": "kops",
#         "AccessKeyId": "AKIAJE*********",
#         "Status": "Active",
#         "SecretAccessKey": "zWJhfemER**************************",
#         "CreateDate": "2019-01-18T01:05:44Z"
#     }
# }
```
The last command will output the access key and the secret key for the _kops_ user, save that information because we will use it from now on, note that we gave kops a lot of power with that user, so be careful with the keys.
<br />

**Additional permissions to be able to create ALBs**
```elixir
cat << EOF > kops-alb-policy.json
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "ec2:Describe*",
       "iam:CreateServiceLinkedRole",
       "tag:GetResources",
       "elasticloadbalancing:*"
     ],
     "Resource": [
       "*"
     ]
   }
 ]
}
EOF

aws iam create-policy --policy-name kops-alb-policy --policy-document file://kops-alb-policy.json
# OUTPUT:
# {
#     "Policy": {
#         "PolicyName": "kops-alb-policy",
#         "PolicyId": "ANPAIRIYZZZTCPJGNZZXS",
#         "Arn": "arn:aws:iam::894527626897:policy/kops-alb-policy",
#         "Path": "/",
#         "DefaultVersionId": "v1",
#         "AttachmentCount": 0,
#         "PermissionsBoundaryUsageCount": 0,
#         "IsAttachable": true,
#         "CreateDate": "2019-01-18T03:50:00Z",
#         "UpdateDate": "2019-01-18T03:50:00Z"
#     }
# }

cat << EOF > kops-route53-policy.json
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "route53:ChangeResourceRecordSets"
     ],
     "Resource": [
       "arn:aws:route53:::hostedzone/*"
     ]
   },
   {
     "Effect": "Allow",
     "Action": [
       "route53:ListHostedZones",
       "route53:ListResourceRecordSets"
     ],
     "Resource": [
       "*"
     ]
   }
 ]
}
EOF

aws iam create-policy --policy-name kops-route53-policy --policy-document file://kops-route53-policy.json
# OUTPUT:
# {
#     "Policy": {
#         "PolicyName": "kops-route53-policy",
#         "PolicyId": "ANPAIEWAGN62HBYC7QOS2",
#         "Arn": "arn:aws:iam::894527626897:policy/kops-route53-policy",
#         "Path": "/",
#         "DefaultVersionId": "v1",
#         "AttachmentCount": 0,
#         "PermissionsBoundaryUsageCount": 0,
#         "IsAttachable": true,
#         "CreateDate": "2019-01-18T03:15:37Z",
#         "UpdateDate": "2019-01-18T03:15:37Z"
#     }
# }
```
Note that even we just created these kops policies for alb and route53 we cannot add them right now, we need to first create the cluster, you can skip them if you don't plan on using these resources.
<br />

**Now we will also export or set the cluster name and kops state store as environment variables**
```elixir
export NAME=k8s.techsquad.rocks
export KOPS_STATE_STORE=techsquad-cluster-state-store
```
We will be using these in a few places, so to not repeat ourselves let's better have it as variables.
<br />

**Create the zone for the subdomain in Route53**
```elixir
ID=$(uuidgen) && aws route53 create-hosted-zone --name ${NAME} --caller-reference $ID | jq .DelegationSet.NameServers
# OUTPUT:
# [
#   "ns-848.awsdns-42.net",
#   "ns-12.awsdns-01.com",
#   "ns-1047.awsdns-02.org",
#   "ns-1862.awsdns-40.co.uk"
# ]
```
As I'm already using this domain for the blog with github we can create a subdomain for it and add some NS records in our root zone for that subdomain, in this case k8s.techsquad.rocks. To make this easier I will show you how it should look like:
![img](/images/kops-dns-subdomain.png){:class="mx-auto"}
So with this change and our new zone in Route53 for the subdomain, we can freely manage it like if it was another domain, this means that everything that goes to \*.k8s.techsquad.rocks will be handled by our Route53 zone.
<br />

**Create a bucket to store the cluster state**
```elixir
aws s3api create-bucket \
    --bucket ${KOPS_STATE_STORE} \
    --region us-east-1
# OUTPUT:
# {
#     "Location": "/techsquad-cluster-state-store"
# }
```
Note that bucket names are unique, so it's always a good idea to prefix them with your domain name or something like that.
<br />

**Set the versioning on, in case we need to rollback at some point**
```elixir
aws s3api put-bucket-versioning --bucket ${KOPS_STATE_STORE}  --versioning-configuration Status=Enabled
```
<br />

**Set encryption on for the bucket**
```elixir
aws s3api put-bucket-encryption --bucket ${KOPS_STATE_STORE} --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```
<br />

**And finally let's create our cluster**
```elixir
export KOPS_STATE_STORE="s3://${KOPS_STATE_STORE}"

kops create cluster \
    --zones us-east-1a \
    --networking calico \
    ${NAME} \
    --yes
# OUTPUT:
# I0117 23:14:06.449479   10314 create_cluster.go:1318] Using SSH public key: /home/kainlite/.ssh/id_rsa.pub
# I0117 23:14:08.367862   10314 create_cluster.go:472] Inferred --cloud=aws from zone "us-east-1a"
# I0117 23:14:09.736030   10314 subnets.go:184] Assigned CIDR 172.20.32.0/19 to subnet us-east-1a
# W0117 23:14:18.049687   10314 firewall.go:249] Opening etcd port on masters for access from the nodes, for calico.  This is unsafe in untrusted environments.
# I0117 23:14:19.385541   10314 executor.go:91] Tasks: 0 done / 77 total; 34 can run
# I0117 23:14:21.779681   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-aggregator-ca"
# I0117 23:14:21.940026   10314 vfs_castore.go:731] Issuing new certificate: "ca"
# I0117 23:14:24.404810   10314 executor.go:91] Tasks: 34 done / 77 total; 24 can run
# I0117 23:14:26.548234   10314 vfs_castore.go:731] Issuing new certificate: "master"
# I0117 23:14:26.689470   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-aggregator"
# I0117 23:14:26.766563   10314 vfs_castore.go:731] Issuing new certificate: "kube-scheduler"
# I0117 23:14:26.863562   10314 vfs_castore.go:731] Issuing new certificate: "kube-controller-manager"
# I0117 23:14:26.955776   10314 vfs_castore.go:731] Issuing new certificate: "kubecfg"
# I0117 23:14:26.972837   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-proxy-client"
# I0117 23:14:26.973239   10314 vfs_castore.go:731] Issuing new certificate: "kops"
# I0117 23:14:27.055466   10314 vfs_castore.go:731] Issuing new certificate: "kubelet"
# I0117 23:14:27.127778   10314 vfs_castore.go:731] Issuing new certificate: "kubelet-api"
# I0117 23:14:27.570516   10314 vfs_castore.go:731] Issuing new certificate: "kube-proxy"
# I0117 23:14:29.503168   10314 executor.go:91] Tasks: 58 done / 77 total; 17 can run
# I0117 23:14:31.594404   10314 executor.go:91] Tasks: 75 done / 77 total; 2 can run
# I0117 23:14:33.297131   10314 executor.go:91] Tasks: 77 done / 77 total; 0 can run
# I0117 23:14:33.297168   10314 dns.go:153] Pre-creating DNS records
# I0117 23:14:34.947302   10314 update_cluster.go:291] Exporting kubecfg for cluster
# kops has set your kubectl context to k8s.techsquad.rocks
#
# Cluster is starting.  It should be ready in a few minutes.
#
# Suggestions:
#  * validate cluster: kops validate cluster
#  * list nodes: kubectl get nodes --show-labels
#  * ssh to the master: ssh -i ~/.ssh/id_rsa admin@api.k8s.techsquad.rocks
#  * the admin user is specific to Debian. If not using Debian please use the appropriate user based on your OS.
#  * read about installing addons at: https://github.com/kubernetes/kops/blob/master/docs/addons.md.
```
We set the KOPS_STATE_STORE to a valid S3 url for kops, and then created the cluster, this will set kubectl context to our new cluster, we might need to wait a few minutes before being able to use it, but before doing anything let's validate that's up and ready.
<br />

```elixir
kops validate cluster ${NAME}
# OUTPUT:
# Using cluster from kubectl context: k8s.techsquad.rocks
#
# Validating cluster k8s.techsquad.rocks
#
# INSTANCE GROUPS
# NAME                    ROLE    MACHINETYPE     MIN     MAX     SUBNETS
# master-us-east-1a       Master  m3.medium       1       1       us-east-1a
# nodes                   Node    t2.medium       2       2       us-east-1a
#
# NODE STATUS
# NAME                            ROLE    READY
# ip-172-20-39-123.ec2.internal   node    True
# ip-172-20-52-65.ec2.internal    node    True
# ip-172-20-61-51.ec2.internal    master  True
#
# Your cluster k8s.techsquad.rocks is ready
```
The validation passed and we can see that our cluster is ready, it can take several minutes until the cluster is up and functional, in this case it took about 3-5 minutes.
<br />

We will create an additional subnet to satisfy our ALB:
```elixir
aws ec2 create-subnet --vpc-id vpc-06e2e104ad785474c --cidr-block 172.20.64.0/19 --availability-zone us-east-1b
# OUTPUT:
# {
#     "Subnet": {
#         "AvailabilityZone": "us-east-1b",
#         "AvailableIpAddressCount": 8187,
#         "CidrBlock": "172.20.64.0/19",
#         "DefaultForAz": false,
#         "MapPublicIpOnLaunch": false,
#         "State": "pending",
#         "SubnetId": "subnet-017a5609ce6104e1b",
#         "VpcId": "vpc-06e2e104ad785474c",
#         "AssignIpv6AddressOnCreation": false,
#         "Ipv6CidrBlockAssociationSet": []
#     }
# }

aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=KubernetesCluster,Value=k8s.techsquad.rocks
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=Name,Value=us-east-1b.k8s.techsquad.rocks
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=SubnetType,Value=Public
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=kubernetes.io/cluster/k8s.techsquad.rocks,Value=owned
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=kubernetes.io/role/elb,Value=1
```
Note that we applied some required tags for the controller, and created an extra subnet, in a HA setup this would not be necessary since kops would create it for us but this is a small testing/dev cluster, so we will need to do it manually.
<br />

And lastly a security group for our ALB:
```elixir
aws ec2 create-security-group --group-name WebApps --description "Default web security group"  --vpc-id vpc-06e2e104ad785474c
# OUTPUT:
# {
#     "GroupId": "sg-09f0b1233696e65ef"
# }

aws ec2 authorize-security-group-ingress --group-id sg-09f0b1233696e65ef --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-057d2b0f6e288aa70 --protocol all --port 0 --source-group sg-09f0b1233696e65ef
```
Note that this rule will open the port 80 to the world, you can add your ip or your VPN ips there if you want to restrict it, the second rule will allow the traffic from the load balancer to reach the nodes where our app is running.
<br />

### **Aws-alb-ingress-controller**
We will use [Aws ALB Ingress Controller](https://aws.amazon.com/blogs/opensource/kubernetes-ingress-aws-alb-ingress-controller/), to serve our web traffic, this will create an manage an ALB based in our ingress rules.

```elixir
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/rbac-role.yaml

clusterrole.rbac.authorization.k8s.io "alb-ingress-controller" created
clusterrolebinding.rbac.authorization.k8s.io "alb-ingress-controller" created
serviceaccount "alb-ingress" created
```
<br />

Download the manifest and then modify the cluster-name to `k8s.techsquad.rocks` and a few other parameters, you can list the vpcs with `aws ec2 describe-vpcs` it will have some kops tags, so it's easy to identify.
```elixir
curl -sS "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/alb-ingress-controller.yaml" > alb-ingress-controller.yaml
```
<br />

Or copy and paste the following lines:
```elixir
cat << EOF > alb-ingress-controller.yaml
# Application Load Balancer (ALB) Ingress Controller Deployment Manifest.
# This manifest details sensible defaults for deploying an ALB Ingress Controller.
# GitHub: https://github.com/kubernetes-sigs/aws-alb-ingress-controller
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: alb-ingress-controller
  name: alb-ingress-controller
  # Namespace the ALB Ingress Controller should run in. Does not impact which
  # namespaces it's able to resolve ingress resource for. For limiting ingress
  # namespace scope, see --watch-namespace.
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alb-ingress-controller
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: alb-ingress-controller
    spec:
      containers:
        - args:
            - -v=1
            # Limit the namespace where this ALB Ingress Controller deployment will
            # resolve ingress resources. If left commented, all namespaces are used.
            # - --watch-namespace=your-k8s-namespace
            - --feature-gates=waf=false

            # Setting the ingress-class flag below ensures that only ingress resources with the
            # annotation kubernetes.io/ingress.class: "alb" are respected by the controller. You may
            # choose any class you'd like for this controller to respect.
            - --ingress-class=alb

            # Name of your cluster. Used when naming resources created
            # by the ALB Ingress Controller, providing distinction between
            # clusters.
            - --cluster-name=k8s.techsquad.rocks

            # AWS VPC ID this ingress controller will use to create AWS resources.
            # If unspecified, it will be discovered from ec2metadata.
            - --aws-vpc-id=vpc-06e2e104ad785474c

            # AWS region this ingress controller will operate in.
            # If unspecified, it will be discovered from ec2metadata.
            # List of regions: http://docs.aws.amazon.com/general/latest/gr/rande.html#vpc_region
            - --aws-region=us-east-1

            # Enables logging on all outbound requests sent to the AWS API.
            # If logging is desired, set to true.
            # - ---aws-api-debug
            # Maximum number of times to retry the aws calls.
            # defaults to 10.
            # - --aws-max-retries=10
          env:
            # AWS key id for authenticating with the AWS API.
            # This is only here for examples. It's recommended you instead use
            # a project like kube2iam for granting access.
            #- name: AWS_ACCESS_KEY_ID
            #  value: KEYVALUE

            # AWS key secret for authenticating with the AWS API.
            # This is only here for examples. It's recommended you instead use
            # a project like kube2iam for granting access.
            #- name: AWS_SECRET_ACCESS_KEY
            #  value: SECRETVALUE
          # Repository location of the ALB Ingress Controller.
          image: 894847497797.dkr.ecr.us-west-2.amazonaws.com/aws-alb-ingress-controller:v1.0.0
          imagePullPolicy: Always
          name: server
          resources: {}
          terminationMessagePath: /dev/termination-log
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      securityContext: {}
      terminationGracePeriodSeconds: 30
      serviceAccountName: alb-ingress
      serviceAccount: alb-ingress
EOF
```
Note that I only modified the args section if you want to compare it with the original.
<br />

Then finally apply it.
```elixir
kubectl apply -f alb-ingress-controller.yaml
# OUTPUT:
# deployment.apps "alb-ingress-controller" created
```

### **External-dns**
[External DNS](https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/aws.md) will update our zone in Route53 based in the ingress rules as well, so everything will be done automatically for us once we add an ingress resource.
<br />

But first let's attach those policies that we created before:
```elixir
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name nodes.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name masters.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name nodes.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name masters.k8s.techsquad.rocks
```
Note that we just used the policies that we created before but we needed the cluster running because kops creates the roles nodes.k8s.techsquad.rocks and masters.k8s.techsquad.rocks, and this is needed for the aws-alb-ingress-controller and external-dns so these are able to do their job.
<br />

We need to download the manifests and modify a few parameters to match our deployment, the parameters are domain-filter and txt-owner-id, the rest is as is:
```elixir
curl -Ss https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.0/docs/examples/external-dns.yaml > external-dns.yaml
```
This configuration will only update records, that's the default policy (upsert), and it will only look for public hosted zones.
<br />

Or copy and paste the following lines:
```elixir
cat << EOF > external-dns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.opensource.zalan.do/teapot/external-dns:v0.5.9
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=k8s.techsquad.rocks # will make ExternalDNS see only the hosted zones matching provided domain, omit to process all available hosted zones
        - --provider=aws
        - --policy=upsert-only # would prevent ExternalDNS from deleting any records, omit to enable full synchronization
        - --aws-zone-type=public # only look at public hosted zones (valid values are public, private or no value for both)
        - --registry=txt
        - --txt-owner-id=k8s.techsquad.rocks
EOF
```
<br />

And apply it:
```elixir
kubectl apply -f external-dns.yaml
# OUTPUT:
# serviceaccount "external-dns" unchanged
# clusterrole.rbac.authorization.k8s.io "external-dns" configured
# clusterrolebinding.rbac.authorization.k8s.io "external-dns-viewer" configured
# deployment.extensions "external-dns" created
```
<br />

Validate that we have everything that we installed up and running:
```elixir
kubectl get pods
# OUTPUT:
# NAME                            READY     STATUS    RESTARTS   AGE
# external-dns-7d7998f7bb-lb5kq   1/1       Running   0          2m

kubectl get pods -n kube-system
# OUTPUT:
# NAME                                                   READY     STATUS    RESTARTS   AGE
# alb-ingress-controller-5885ddd5f9-9rsc8                1/1       Running   0          12m
# calico-kube-controllers-f6bc47f75-n99tl                1/1       Running   0          27m
# calico-node-4ps9c                                      2/2       Running   0          25m
# calico-node-kjztv                                      2/2       Running   0          27m
# calico-node-zs4fg                                      2/2       Running   0          25m
# dns-controller-67f5c6b7bd-r67pl                        1/1       Running   0          27m
# etcd-server-events-ip-172-20-42-37.ec2.internal        1/1       Running   0          26m
# etcd-server-ip-172-20-42-37.ec2.internal               1/1       Running   0          26m
# kube-apiserver-ip-172-20-42-37.ec2.internal            1/1       Running   0          27m
# kube-controller-manager-ip-172-20-42-37.ec2.internal   1/1       Running   0          26m
# kube-dns-756bfc7fdf-2kzjs                              3/3       Running   0          24m
# kube-dns-756bfc7fdf-rq5nd                              3/3       Running   0          27m
# kube-dns-autoscaler-787d59df8f-c2d52                   1/1       Running   0          27m
# kube-proxy-ip-172-20-42-109.ec2.internal               1/1       Running   0          25m
# kube-proxy-ip-172-20-42-37.ec2.internal                1/1       Running   0          26m
# kube-proxy-ip-172-20-54-175.ec2.internal               1/1       Running   0          25m
# kube-scheduler-ip-172-20-42-37.ec2.internal            1/1       Running   0          26m
```
We can see that alb-ingress-controller is running, also external-dns, and everything looks good and healthy, time to test it with a deployment.
<br />

### **Testing everything**
```elixir
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-service.yaml
# OUTPUT:
# namespace "2048-game" created
# deployment.extensions "2048-deployment" created
# service "service-2048" created
```
<br />

We need to download and edit the ingress resource to make it use our domain so we can then see the record pointing to the ALB.
```elixir
curl -Ss https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-ingress.yaml > 2048-ingress.yaml
```
<br />

Or just copy and paste the next snippet.
```elixir
cat << EOF > 2048-ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: "2048-ingress"
  namespace: "2048-game"
  annotations:
    kubernetes.io/ingress.class:                alb
    alb.ingress.kubernetes.io/scheme:           internet-facing
    alb.ingress.kubernetes.io/target-type:      instance
    alb.ingress.kubernetes.io/subnets:          subnet-017a5609ce6104e1b, subnet-060e6d3c3d3c2b34a
    alb.ingress.kubernetes.io/security-groups:  sg-09f0b1233696e65ef
    # You can check all the alternatives here:
    # https://github.com/riccardofreixo/alb-ingress-controller/blob/master/docs/ingress-resources.md
  labels:
    app: 2048-ingress
spec:
  rules:
  - host: 2048.k8s.techsquad.rocks
    http:
      paths:
      - backend:
          serviceName: "service-2048"
          servicePort: 80
        path: /*
EOF
```
You can use `aws ec2 describe-subnets`, to find the first subnet id, this subnet already has some tags that we need in order to make it work, for example: `kubernetes.io/role/elb: 1`, and the second subnet is the one that we created manually and applied the same tags.
<br />

And finally apply it:
```elixir
kubectl apply -f 2048-ingress.yaml
# OUTPUT:
# ingress.extensions "2048-ingress" created
```
Wait a few moments and verify.
<br />

### **Results**

**The ALB**
![img](/images/aws-alb-listeners.png){:class="mx-auto"}
<br />

**The DNS records**
![image](/images/aws-alb-route53-records.png){:class="mx-auto"}
<br />

**And the app**
![img](/images/aws-alb-result.png){:class="mx-auto"}
<br />

### **Clean up**
Remember this is not free, and if you don't want to get charged after you're done testing just shutdown and delete everything.
```elixir
kubectl delete -f 2048-ingress.yaml
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name nodes.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name masters.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name nodes.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name masters.k8s.techsquad.rocks

kops delete cluster ${NAME} --yes
# OUTPUT:
# ...
# Deleted kubectl config for k8s.techsquad.rocks
#
# Deleted cluster: "k8s.techsquad.rocks"
```
This command is really verbose, so I skipped it to the end, be aware that in order to delete the cluster with kops you first need to detach the additionally attached privileges. Also be careful to delete first the ingress resources so the ALB gets removed before you delete the cluster, or you will have an ALB laying around afterwards. You can re-run it if it gets stuck and cannot delete any resource.
<br />

### **Notes**
* I was going to use helm and deploy a more complex application here, but the article was already too long, so I decided to go with the aws alb ingress controller example.
* If something doesn't go well or things aren't happening you can always check the logs for external-dns and aws-alb-ingress-controller, the messages are usually very descriptive and easy to understand.
* For an ALB you need two subnets in two different AZs beforehand.
* If you are going to use ALBs, have in mind that it will create an ALB for each deployment, there is a small project that merges everything into one ALB but you need to have a unified or consolidated way to do health checks or or some of the apps will fail and the ALB will return a 502, the project can be found [here](https://github.com/jakubkulhan/ingress-merge).
* Documenting what you do and how you do it (Also keeping the documentation updated is really important), not only will help the future you (Yes, you can thank your past self when reading and old doc), but also it will make it easier to share the knowledge and purpose of whatever you are implementing with your team.
* I spent 3 bucks with all the instances and dns zones, etc during this tutorial in case you are interested :).
* Notes I also removed all $ from the code blocks and added the output of the commands with # OUTPUT:, let me know if this is clear and easy to read, or if you have any suggestion.
<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

Also, you can check the source code and changes in the [generated code](https://github.com/kainlite/kainlite.github.io) and the [sources here](https://github.com/kainlite/blog)

<br />
---lang---
%{
  title: "Kops desde 0, nuestro cluster de kubernetes en AWS",
  author: "Gabriel Garrido",
  description: "Kops es una herramienta muy buena para creacion y mantenimiento de clusters diseñado principalmente para
  AWS...",
  tags: ~w(kubernetes kops aws),
  published: true,
  image: "kubernetes-aws.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![kubernetes](/images/kubernetes-aws.png){:class="mx-auto"}

### **Introducción**

En este artículo crearemos un clúster desde cero con [kops](https://github.com/kubernetes/kops) (instalación, actualizaciones y gestión de K8s) en [AWS](https://aws.amazon.com/). Configuraremos [aws-alb-ingress-controller](https://github.com/kubernetes-sigs/aws-alb-ingress-controller) (tráfico externo hacia nuestros servicios/pods) y [external dns](https://github.com/kubernetes-incubator/external-dns) (actualizar los registros basados en las reglas de ingreso) y también aprenderemos un poco sobre awscli en el proceso.
<br />

Básicamente, tendremos un clúster completamente funcional que podrá manejar tráfico público en minutos. Primero instalaremos el clúster con kops, luego habilitaremos el controlador de ingreso y finalmente external-dns. Después, implementaremos una aplicación básica para probar que todo funcione correctamente. SSL/TLS está fuera del alcance, pero es bastante fácil de implementar si estás usando ACM.
<br />

Por si no lo sabías, esta configuración no será gratuita; será económica seguro porque usaremos instancias pequeñas, etc., pero no completamente gratis. Así que antes de comenzar, asegúrate de que puedes gastar unos cuantos dólares probándolo.
<br />

### **Kops**

Esta es una herramienta increíble para configurar y mantener tus clústeres, actualmente solo compatible con AWS y GCE. Se planean otras plataformas y algunas también son compatibles en alfa. Usaremos AWS en este ejemplo; requiere kubectl, así que asegúrate de tenerlo instalado:

```elixir
curl -LO https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x kops-linux-amd64
sudo mv kops-linux-amd64 /usr/local/bin/kops
```
<br />

**Exporta las credenciales que usaremos para crear el usuario y las políticas de kops**

```elixir
export AWS_ACCESS_KEY_ID=XXXX && export AWS_SECRET_ACCESS_KEY=XXXXX
```

Puedes hacerlo de esta manera o simplemente usar `aws configure` y configurar un perfil.
<br />

Lo siguiente que necesitamos son credenciales IAM para que kops funcione. Necesitarás awscli configurado y funcionando con tu cuenta de tipo administrador de AWS antes de continuar:
```elixir
# Create iam group
aws iam create-group --group-name kops
# OUTPUT:
# {
#     "Group": {
#         "Path": "/",
#         "GroupName": "kops",
#         "GroupId": "AGPAIABI3O4WYM46AIX44",
#         "Arn": "arn:aws:iam::894527626897:group/kops",
#         "CreateDate": "2019-01-18T01:04:23Z"
#     }
# }

aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonEC2FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonRoute53FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess --group-name kops
aws iam attach-group-policy --policy-arn arn:aws:iam::aws:policy/IAMFullAccess --group-name kops

# Attach policies
aws iam create-user --user-name kops
aws iam add-user-to-group --user-name kops --group-name kops
# OUTPUT:
# {
#     "Group": {
#         "Path": "/",
#         "GroupName": "kops",
#         "GroupId": "AGPAIABI3O4WYM46AIX44",
#         "Arn": "arn:aws:iam::894527626897:group/kops",
#         "CreateDate": "2019-01-18T01:04:23Z"
#     }
# }

# Create access key - save the output of this command.
aws iam create-access-key --user-name kops
# OUTPUT:
# {
#     "AccessKey": {
#         "UserName": "kops",
#         "AccessKeyId": "AKIAJE*********",
#         "Status": "Active",
#         "SecretAccessKey": "zWJhfemER**************************",
#         "CreateDate": "2019-01-18T01:05:44Z"
#     }
# }
```
El último comando generará la clave de acceso y la clave secreta para el usuario _kops_, guarda esa información porque la utilizaremos de ahora en adelante. Ten en cuenta que le dimos mucho poder a kops con ese usuario, así que ten cuidado con las claves.
<br />

**Permisos adicionales para poder crear ALBs**
```elixir
cat << EOF > kops-alb-policy.json
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "ec2:Describe*",
       "iam:CreateServiceLinkedRole",
       "tag:GetResources",
       "elasticloadbalancing:*"
     ],
     "Resource": [
       "*"
     ]
   }
 ]
}
EOF

aws iam create-policy --policy-name kops-alb-policy --policy-document file://kops-alb-policy.json
# OUTPUT:
# {
#     "Policy": {
#         "PolicyName": "kops-alb-policy",
#         "PolicyId": "ANPAIRIYZZZTCPJGNZZXS",
#         "Arn": "arn:aws:iam::894527626897:policy/kops-alb-policy",
#         "Path": "/",
#         "DefaultVersionId": "v1",
#         "AttachmentCount": 0,
#         "PermissionsBoundaryUsageCount": 0,
#         "IsAttachable": true,
#         "CreateDate": "2019-01-18T03:50:00Z",
#         "UpdateDate": "2019-01-18T03:50:00Z"
#     }
# }

cat << EOF > kops-route53-policy.json
{
 "Version": "2012-10-17",
 "Statement": [
   {
     "Effect": "Allow",
     "Action": [
       "route53:ChangeResourceRecordSets"
     ],
     "Resource": [
       "arn:aws:route53:::hostedzone/*"
     ]
   },
   {
     "Effect": "Allow",
     "Action": [
       "route53:ListHostedZones",
       "route53:ListResourceRecordSets"
     ],
     "Resource": [
       "*"
     ]
   }
 ]
}
EOF

aws iam create-policy --policy-name kops-route53-policy --policy-document file://kops-route53-policy.json
# OUTPUT:
# {
#     "Policy": {
#         "PolicyName": "kops-route53-policy",
#         "PolicyId": "ANPAIEWAGN62HBYC7QOS2",
#         "Arn": "arn:aws:iam::894527626897:policy/kops-route53-policy",
#         "Path": "/",
#         "DefaultVersionId": "v1",
#         "AttachmentCount": 0,
#         "PermissionsBoundaryUsageCount": 0,
#         "IsAttachable": true,
#         "CreateDate": "2019-01-18T03:15:37Z",
#         "UpdateDate": "2019-01-18T03:15:37Z"
#     }
# }
```
Ten en cuenta que, aunque acabamos de crear estas políticas de kops para alb y route53, no podemos agregarlas ahora mismo. Primero necesitamos crear el clúster. Puedes omitir este paso si no planeas usar estos recursos.
<br />

**Ahora también exportaremos o configuraremos el nombre del clúster y el almacén de estado de kops como variables de entorno**
```elixir
export NAME=k8s.techsquad.rocks
export KOPS_STATE_STORE=techsquad-cluster-state-store
```
Usaremos estas variables en varios lugares, así que para no repetirnos es mejor tenerlas como variables de entorno.
<br />

**Crear la zona para el subdominio en Route53**
```elixir
ID=$(uuidgen) && aws route53 create-hosted-zone --name ${NAME} --caller-reference $ID | jq .DelegationSet.NameServers
# OUTPUT:
# [
#   "ns-848.awsdns-42.net",
#   "ns-12.awsdns-01.com",
#   "ns-1047.awsdns-02.org",
#   "ns-1862.awsdns-40.co.uk"
# ]
```
Como ya estoy utilizando este dominio para el blog con GitHub, podemos crear un subdominio y añadir algunos registros NS en nuestra zona raíz para ese subdominio, en este caso k8s.techsquad.rocks. Para que sea más fácil, te mostraré cómo debería verse:
![img](/images/kops-dns-subdomain.png){:class="mx-auto"}
Con este cambio y nuestra nueva zona en Route53 para el subdominio, podemos gestionarlo libremente como si fuera otro dominio. Esto significa que todo lo que vaya a \*.k8s.techsquad.rocks será manejado por nuestra zona en Route53.
<br />

**Crear un bucket para almacenar el estado del clúster**
```elixir
aws s3api create-bucket \
    --bucket ${KOPS_STATE_STORE} \
    --region us-east-1
# OUTPUT:
# {
#     "Location": "/techsquad-cluster-state-store"
# }
```
Ten en cuenta que los nombres de los buckets son únicos, por lo que siempre es una buena idea prefijarlos con tu nombre de dominio o algo similar.
<br />

**Habilitar el versionado, en caso de que necesitemos revertir algún cambio**
```elixir
aws s3api put-bucket-versioning --bucket ${KOPS_STATE_STORE}  --versioning-configuration Status=Enabled
```
<br />

**Habilitar la encriptación para el bucket**
```elixir
aws s3api put-bucket-encryption --bucket ${KOPS_STATE_STORE} --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
```
<br />

**Y finalmente, vamos a crear nuestro clúster**
```elixir
export KOPS_STATE_STORE="s3://${KOPS_STATE_STORE}"

kops create cluster \
    --zones us-east-1a \
    --networking calico \
    ${NAME} \
    --yes
# OUTPUT:
# I0117 23:14:06.449479   10314 create_cluster.go:1318] Using SSH public key: /home/kainlite/.ssh/id_rsa.pub
# I0117 23:14:08.367862   10314 create_cluster.go:472] Inferred --cloud=aws from zone "us-east-1a"
# I0117 23:14:09.736030   10314 subnets.go:184] Assigned CIDR 172.20.32.0/19 to subnet us-east-1a
# W0117 23:14:18.049687   10314 firewall.go:249] Opening etcd port on masters for access from the nodes, for calico.  This is unsafe in untrusted environments.
# I0117 23:14:19.385541   10314 executor.go:91] Tasks: 0 done / 77 total; 34 can run
# I0117 23:14:21.779681   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-aggregator-ca"
# I0117 23:14:21.940026   10314 vfs_castore.go:731] Issuing new certificate: "ca"
# I0117 23:14:24.404810   10314 executor.go:91] Tasks: 34 done / 77 total; 24 can run
# I0117 23:14:26.548234   10314 vfs_castore.go:731] Issuing new certificate: "master"
# I0117 23:14:26.689470   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-aggregator"
# I0117 23:14:26.766563   10314 vfs_castore.go:731] Issuing new certificate: "kube-scheduler"
# I0117 23:14:26.863562   10314 vfs_castore.go:731] Issuing new certificate: "kube-controller-manager"
# I0117 23:14:26.955776   10314 vfs_castore.go:731] Issuing new certificate: "kubecfg"
# I0117 23:14:26.972837   10314 vfs_castore.go:731] Issuing new certificate: "apiserver-proxy-client"
# I0117 23:14:26.973239   10314 vfs_castore.go:731] Issuing new certificate: "kops"
# I0117 23:14:27.055466   10314 vfs_castore.go:731] Issuing new certificate: "kubelet"
# I0117 23:14:27.127778   10314 vfs_castore.go:731] Issuing new certificate: "kubelet-api"
# I0117 23:14:27.570516   10314 vfs_castore.go:731] Issuing new certificate: "kube-proxy"
# I0117 23:14:29.503168   10314 executor.go:91] Tasks: 58 done / 77 total; 17 can run
# I0117 23:14:31.594404   10314 executor.go:91] Tasks: 75 done / 77 total; 2 can run
# I0117 23:14:33.297131   10314 executor.go:91] Tasks: 77 done / 77 total; 0 can run
# I0117 23:14:33.297168   10314 dns.go:153] Pre-creating DNS records
# I0117 23:14:34.947302   10314 update_cluster.go:291] Exporting kubecfg for cluster
# kops has set your kubectl context to k8s.techsquad.rocks
#
# Cluster is starting.  It should be ready in a few minutes.
#
# Suggestions:
#  * validate cluster: kops validate cluster
#  * list nodes: kubectl get nodes --show-labels
#  * ssh to the master: ssh -i ~/.ssh/id_rsa admin@api.k8s.techsquad.rocks
#  * the admin user is specific to Debian. If not using Debian please use the appropriate user based on your OS.
#  * read about installing addons at: https://github.com/kubernetes/kops/blob/master/docs/addons.md.
```
Hemos configurado `KOPS_STATE_STORE` con una URL válida de S3 para kops, y luego creamos el clúster. Esto también configurará el contexto de `kubectl` para nuestro nuevo clúster. Es posible que necesitemos esperar unos minutos antes de poder usarlo, pero antes de hacer cualquier cosa, validemos que esté listo y en funcionamiento.
<br />

```elixir
kops validate cluster ${NAME}
# OUTPUT:
# Using cluster from kubectl context: k8s.techsquad.rocks
#
# Validating cluster k8s.techsquad.rocks
#
# INSTANCE GROUPS
# NAME                    ROLE    MACHINETYPE     MIN     MAX     SUBNETS
# master-us-east-1a       Master  m3.medium       1       1       us-east-1a
# nodes                   Node    t2.medium       2       2       us-east-1a
#
# NODE STATUS
# NAME                            ROLE    READY
# ip-172-20-39-123.ec2.internal   node    True
# ip-172-20-52-65.ec2.internal    node    True
# ip-172-20-61-51.ec2.internal    master  True
#
# Your cluster k8s.techsquad.rocks is ready
```
La validación fue exitosa y podemos ver que nuestro clúster está listo. Puede tomar varios minutos hasta que el clúster esté completamente funcional; en este caso, tomó aproximadamente de 3 a 5 minutos.
<br />

Crearemos una subred adicional para satisfacer los requisitos de nuestro ALB:
```elixir
aws ec2 create-subnet --vpc-id vpc-06e2e104ad785474c --cidr-block 172.20.64.0/19 --availability-zone us-east-1b
# OUTPUT:
# {
#     "Subnet": {
#         "AvailabilityZone": "us-east-1b",
#         "AvailableIpAddressCount": 8187,
#         "CidrBlock": "172.20.64.0/19",
#         "DefaultForAz": false,
#         "MapPublicIpOnLaunch": false,
#         "State": "pending",
#         "SubnetId": "subnet-017a5609ce6104e1b",
#         "VpcId": "vpc-06e2e104ad785474c",
#         "AssignIpv6AddressOnCreation": false,
#         "Ipv6CidrBlockAssociationSet": []
#     }
# }

aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=KubernetesCluster,Value=k8s.techsquad.rocks
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=Name,Value=us-east-1b.k8s.techsquad.rocks
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=SubnetType,Value=Public
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=kubernetes.io/cluster/k8s.techsquad.rocks,Value=owned
aws ec2 create-tags --resources subnet-017a5609ce6104e1b --tags Key=kubernetes.io/role/elb,Value=1
```
Tenga en cuenta que aplicamos algunas etiquetas necesarias para el controlador y creamos una subred adicional. En una configuración HA, esto no sería necesario, ya que **kops** lo crearía por nosotros, pero como se trata de un clúster pequeño para pruebas/desarrollo, debemos hacerlo manualmente.
<br />

Y por último, un grupo de seguridad para nuestro ALB:
```elixir
aws ec2 create-security-group --group-name WebApps --description "Default web security group"  --vpc-id vpc-06e2e104ad785474c
# OUTPUT:
# {
#     "GroupId": "sg-09f0b1233696e65ef"
# }

aws ec2 authorize-security-group-ingress --group-id sg-09f0b1233696e65ef --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id sg-057d2b0f6e288aa70 --protocol all --port 0 --source-group sg-09f0b1233696e65ef
```
Tenga en cuenta que esta regla abrirá el puerto 80 al mundo. Puede agregar su IP o las IPs de su VPN si desea restringir el acceso. La segunda regla permitirá que el tráfico proveniente del balanceador de carga llegue a los nodos donde nuestra aplicación está funcionando.
<br />

### **Aws-alb-ingress-controller**
Usaremos [Aws ALB Ingress Controller](https://aws.amazon.com/blogs/opensource/kubernetes-ingress-aws-alb-ingress-controller/) para servir nuestro tráfico web. Este controlador creará y gestionará un ALB basado en nuestras reglas de **ingress**.

```elixir
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/rbac-role.yaml

clusterrole.rbac.authorization.k8s.io "alb-ingress-controller" created
clusterrolebinding.rbac.authorization.k8s.io "alb-ingress-controller" created
serviceaccount "alb-ingress" created
```
<br />

Descargue el manifiesto y luego modifique el nombre del clúster a `k8s.techsquad.rocks` y algunos otros parámetros. Puede listar las VPCs con `aws ec2 describe-vpcs`, tendrán algunas etiquetas de **kops**, por lo que es fácil identificarlas.
```elixir
curl -sS "https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/alb-ingress-controller.yaml" > alb-ingress-controller.yaml
```
<br />

O copie y pegue las siguientes líneas:
```elixir
cat << EOF > alb-ingress-controller.yaml
# Application Load Balancer (ALB) Ingress Controller Deployment Manifest.
# This manifest details sensible defaults for deploying an ALB Ingress Controller.
# GitHub: https://github.com/kubernetes-sigs/aws-alb-ingress-controller
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: alb-ingress-controller
  name: alb-ingress-controller
  # Namespace the ALB Ingress Controller should run in. Does not impact which
  # namespaces it's able to resolve ingress resource for. For limiting ingress
  # namespace scope, see --watch-namespace.
  namespace: kube-system
spec:
  replicas: 1
  selector:
    matchLabels:
      app: alb-ingress-controller
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 1
    type: RollingUpdate
  template:
    metadata:
      creationTimestamp: null
      labels:
        app: alb-ingress-controller
    spec:
      containers:
        - args:
            - -v=1
            # Limit the namespace where this ALB Ingress Controller deployment will
            # resolve ingress resources. If left commented, all namespaces are used.
            # - --watch-namespace=your-k8s-namespace
            - --feature-gates=waf=false

            # Setting the ingress-class flag below ensures that only ingress resources with the
            # annotation kubernetes.io/ingress.class: "alb" are respected by the controller. You may
            # choose any class you'd like for this controller to respect.
            - --ingress-class=alb

            # Name of your cluster. Used when naming resources created
            # by the ALB Ingress Controller, providing distinction between
            # clusters.
            - --cluster-name=k8s.techsquad.rocks

            # AWS VPC ID this ingress controller will use to create AWS resources.
            # If unspecified, it will be discovered from ec2metadata.
            - --aws-vpc-id=vpc-06e2e104ad785474c

            # AWS region this ingress controller will operate in.
            # If unspecified, it will be discovered from ec2metadata.
            # List of regions: http://docs.aws.amazon.com/general/latest/gr/rande.html#vpc_region
            - --aws-region=us-east-1

            # Enables logging on all outbound requests sent to the AWS API.
            # If logging is desired, set to true.
            # - ---aws-api-debug
            # Maximum number of times to retry the aws calls.
            # defaults to 10.
            # - --aws-max-retries=10
          env:
            # AWS key id for authenticating with the AWS API.
            # This is only here for examples. It's recommended you instead use
            # a project like kube2iam for granting access.
            #- name: AWS_ACCESS_KEY_ID
            #  value: KEYVALUE

            # AWS key secret for authenticating with the AWS API.
            # This is only here for examples. It's recommended you instead use
            # a project like kube2iam for granting access.
            #- name: AWS_SECRET_ACCESS_KEY
            #  value: SECRETVALUE
          # Repository location of the ALB Ingress Controller.
          image: 894847497797.dkr.ecr.us-west-2.amazonaws.com/aws-alb-ingress-controller:v1.0.0
          imagePullPolicy: Always
          name: server
          resources: {}
          terminationMessagePath: /dev/termination-log
      dnsPolicy: ClusterFirst
      restartPolicy: Always
      securityContext: {}
      terminationGracePeriodSeconds: 30
      serviceAccountName: alb-ingress
      serviceAccount: alb-ingress
EOF
```
Tenga en cuenta que solo modifiqué la sección de argumentos si desea compararla con el original.
<br />

Finalmente, aplíquelo.
```elixir
kubectl apply -f alb-ingress-controller.yaml
# OUTPUT:
# deployment.apps "alb-ingress-controller" created
```

### **External-dns**
[External DNS](https://github.com/kubernetes-incubator/external-dns/blob/master/docs/tutorials/aws.md) actualizará nuestra zona en Route53 basada en las reglas de **ingress**, por lo que todo se hará automáticamente una vez que agreguemos un recurso de **ingress**.
<br />

Pero primero, adjuntemos las políticas que creamos antes:
```elixir
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name nodes.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name masters.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name nodes.k8s.techsquad.rocks
aws iam attach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name masters.k8s.techsquad.rocks
```
Tenga en cuenta que acabamos de utilizar las políticas que creamos anteriormente, pero necesitábamos que el clúster estuviera en funcionamiento porque **kops** crea los roles **nodes.k8s.techsquad.rocks** y **masters.k8s.techsquad.rocks**, y esto es necesario para que **aws-alb-ingress-controller** y **external-dns** puedan hacer su trabajo.
<br />

Necesitamos descargar los manifiestos y modificar algunos parámetros para que coincidan con nuestra implementación. Los parámetros son **domain-filter** y **txt-owner-id**, el resto queda igual:
```elixir
curl -Ss https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.1.0/docs/examples/external-dns.yaml > external-dns.yaml
```
Esta configuración solo actualizará los registros, esa es la política predeterminada (upsert), y solo buscará zonas alojadas públicas.
<br />

O copie y pegue las siguientes líneas:
```elixir
cat << EOF > external-dns.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: external-dns
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  name: external-dns
rules:
- apiGroups: [""]
  resources: ["services"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get","watch","list"]
- apiGroups: ["extensions"]
  resources: ["ingresses"]
  verbs: ["get","watch","list"]
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["list"]
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: external-dns-viewer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: external-dns
subjects:
- kind: ServiceAccount
  name: external-dns
  namespace: default
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: external-dns
spec:
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: external-dns
    spec:
      serviceAccountName: external-dns
      containers:
      - name: external-dns
        image: registry.opensource.zalan.do/teapot/external-dns:v0.5.9
        args:
        - --source=service
        - --source=ingress
        - --domain-filter=k8s.techsquad.rocks # limitará ExternalDNS a ver solo las zonas alojadas que coincidan con el dominio proporcionado, omitir para procesar todas las zonas disponibles
        - --provider=aws
        - --policy=upsert-only # evitaría que ExternalDNS elimine cualquier registro, omitir para habilitar la sincronización completa
        - --aws-zone-type=public # solo buscará zonas alojadas públicas (valores válidos: public, private o sin valor para ambos)
        - --registry=txt
        - --txt-owner-id=k8s.techsquad.rocks
EOF
```
<br />

Y aplíquelo:
```elixir
kubectl apply -f external-dns.yaml
# OUTPUT:
# serviceaccount "external-dns" unchanged
# clusterrole.rbac.authorization.k8s.io "external-dns" configured
# clusterrolebinding.rbac.authorization.k8s.io "external-dns-viewer" configured
# deployment.extensions "external-dns" created
```
<br />

Valide que todo lo que instalamos esté funcionando:
```elixir
kubectl get pods
# OUTPUT:
# NAME                            READY     STATUS    RESTARTS   AGE
# external-dns-7d7998f7bb-lb5kq   1/1       Running   0          2m

kubectl get pods -n kube-system
# OUTPUT:
# NAME                                                   READY     STATUS    RESTARTS   AGE
# alb-ingress-controller-5885ddd5f9-9rsc8                1/1       Running   0          12m
# calico-kube-controllers-f6bc47f75-n99tl                1/1       Running   0          27m
# calico-node-4ps9c                                      2/2       Running   0          25m
# calico-node-kjztv                                      2/2       Running   0          27m
# calico-node-zs4fg                                      2/2       Running   0          25m
# dns-controller-67f5c6b7bd-r67pl                        1/1       Running   0          27m
# etcd-server-events-ip-172-20-42-37.ec2.internal        1/1       Running   0          26m
# etcd-server-ip-172-20-42-37.ec2.internal               1/1       Running   0          26m
# kube-apiserver-ip-172-20-42-37.ec2.internal            1/1       Running   0          27m
# kube-controller-manager-ip-172-20-42-37.ec2.internal   1/1       Running   0          26m
# kube-dns-756bfc7fdf-2kzjs                              3/3       Running   0          24m
# kube-dns-756bfc7fdf-rq5nd                              3/3       Running   0          27m
# kube-dns-autoscaler-787d59df8f-c2d52                   1/1       Running   0          27m
# kube-proxy-ip-172-20-42-109.ec2.internal               1/1       Running   0          25m
# kube-proxy-ip-172-20-42-37.ec2.internal                1/1       Running   0          26m
# kube-proxy-ip-172-20-54-175.ec2.internal               1/1       Running   0          25m
# kube-scheduler-ip-172-20-42-37.ec2.internal            1/1       Running   0          26m
```
Podemos ver que **alb-ingress-controller** está funcionando, al igual que **external-dns**, y todo se ve bien y saludable, es hora de probarlo con una implementación.
<br />

### **Testing everything**
```elixir
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-namespace.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-deployment.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-service.yaml
# OUTPUT:
# namespace "2048-game" created
# deployment.extensions "2048-deployment" created
# service "service-2048" created
```
<br />

Necesitamos descargar y editar el recurso de **ingress** para que utilice nuestro dominio y podamos ver el registro apuntando al ALB.
```elixir
curl -Ss https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v1.0.0/docs/examples/2048/2048-ingress.yaml > 2048-ingress.yaml
```
<br />

O simplemente copie y pegue el siguiente fragmento.
```elixir
cat << EOF > 2048-ingress.yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: "2048-ingress"
  namespace: "2048-game"
  annotations:
    kubernetes.io/ingress.class:                alb
    alb.ingress.kubernetes.io/scheme:           internet

-facing
    alb.ingress.kubernetes.io/target-type:      instance
    alb.ingress.kubernetes.io/subnets:          subnet-017a5609ce6104e1b, subnet-060e6d3c3d3c2b34a
    alb.ingress.kubernetes.io/security-groups:  sg-09f0b1233696e65ef
    # Puede verificar todas las alternativas aquí:
    # https://github.com/riccardofreixo/alb-ingress-controller/blob/master/docs/ingress-resources.md
  labels:
    app: 2048-ingress
spec:
  rules:
  - host: 2048.k8s.techsquad.rocks
    http:
      paths:
      - backend:
          serviceName: "service-2048"
          servicePort: 80
        path: /*
EOF
```
Puede usar `aws ec2 describe-subnets` para encontrar el primer ID de subred. Esta subred ya tiene algunas etiquetas que necesitamos para que funcione, por ejemplo: `kubernetes.io/role/elb: 1`, y la segunda subred es la que creamos manualmente y aplicamos las mismas etiquetas.
<br />

Y finalmente aplíquelo:
```elixir
kubectl apply -f 2048-ingress.yaml
# OUTPUT:
# ingress.extensions "2048-ingress" created
```
Espere unos momentos y verifique.
<br />

### **Resultados**

**El ALB**
![img](/images/aws-alb-listeners.png){:class="mx-auto"}
<br />

**Los registros DNS**
![image](/images/aws-alb-route53-records.png){:class="mx-auto"}
<br />

**Y la aplicación**
![img](/images/aws-alb-result.png){:class="mx-auto"}
<br />

### **Clean up**
Recuerde que esto no es gratis, y si no quiere que se le cobre después de haber terminado las pruebas, simplemente apague y elimine todo.
```elixir
kubectl delete -f 2048-ingress.yaml
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name nodes.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-route53-policy --role-name masters.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name nodes.k8s.techsquad.rocks
aws iam detach-role-policy --policy-arn arn:aws:iam::894527626897:policy/kops-alb-policy --role-name masters.k8s.techsquad.rocks

kops delete cluster ${NAME} --yes
# OUTPUT:
# ...
# Deleted kubectl config for k8s.techsquad.rocks
#
# Deleted cluster: "k8s.techsquad.rocks"
```
Este comando es realmente detallado, así que lo resumí al final. Tenga en cuenta que para eliminar el clúster con **kops**, primero debe desasociar los privilegios adicionales adjuntos. También tenga cuidado de eliminar primero los recursos de **ingress** para que el ALB se elimine antes de que elimine el clúster, o de lo contrario tendrá un ALB pendiente después. Puede volver a ejecutarlo si se queda atascado y no puede eliminar ningún recurso.
<br />

### **Notas**
* Iba a usar **helm** e implementar una aplicación más compleja aquí, pero el artículo ya era demasiado largo, así que decidí ir con el ejemplo del controlador de ingreso de **aws alb**.
* Si algo no sale bien o las cosas no suceden, siempre puede verificar los registros de **external-dns** y **aws-alb-ingress-controller**, los mensajes suelen ser muy descriptivos y fáciles de entender.
* Para un ALB, necesita dos subredes en dos AZ diferentes de antemano.
* Si va a utilizar ALBs, tenga en cuenta que creará un ALB para cada implementación. Hay un pequeño proyecto que combina todo en un solo ALB, pero necesita tener una forma unificada o consolidada de realizar verificaciones de estado o algunas de las aplicaciones fallarán y el ALB devolverá un 502. El proyecto se puede encontrar [aquí](https://github.com/jakubkulhan/ingress-merge).
* Documentar lo que hace y cómo lo hace (y también mantener la documentación actualizada es realmente importante) no solo le ayudará a usted en el futuro (sí, puede agradecer a su yo del pasado cuando lea un documento antiguo), sino que también facilitará compartir el conocimiento y el propósito de lo que sea que esté implementando con su equipo.
* Gasté 3 dólares en todas las instancias y zonas DNS, etc., durante este tutorial, en caso de que le interese :).
* También eliminé todos los **$** de los bloques de código y agregué la salida de los comandos con **# OUTPUT:**. Déjeme saber si esto es claro y fácil de leer, o si tiene alguna sugerencia.
<br />

### **Errata**
Si encuentra algún error o tiene alguna sugerencia, envíeme un mensaje para que se corrija.

<br />
