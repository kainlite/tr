%{
  title: "Kubernetes authentication and authorization",
  author: "Gabriel Garrido",
  description: "In this article we will explore how authentication and authorization works in kubernetes. But first what's the difference?",
  tags: ~w(kubernetes linux security networking),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![kubernetes](/images/kubernetes.webp){:class="mx-auto"}

#### Introduction
In this article we will explore how authentication and authorization works in kubernetes. But first what's the difference?

<br />

**Authentication**:

When you validate your identity against a service or system you are authenticated meaning that the system recognizes you 
as a valid user. In kubernetes when you are creating the clusters you basically create a CA (Certificate Authority) that 
then you use to generate certificates for all components and users.

<br />

**Authorization**:

After you are authenticated the system needs to know if you have enough privileges to do whatever you might want to do. 
In kubernetes this is known as RBAC (Role based access control) and it translates to Roles as entities with permissions 
and are associated to service accounts via role bindings when things are scoped to a given namespace, otherwise you can 
have a cluster role and cluster role binding.

<br />

So we are going to create a namespace, a serviceaccount, a role and a role binding and then generate a kubeconfig for it and then test it.

<br />

The sources for this article can be found at: [RBAC Example](https://github.com/kainlite/rbac-example)

<br />

#### Let's get to it
Let's start, I will use these generators but I'm saving these to a file and then applying.

<br />

**Namespace**:

The namespace resource is like a container for other resources and it's often useful when deploying many apps to the same cluster or there are multiple users:
```elixir
kubectl create namespace mynamespace -o yaml --dry-run=client
```

<br />

The output should look something like this:
```elixir
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: mynamespace
spec: {}
status: {}
```

You can read more [here](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)

<br />

**Service account**:

The service account is your identity as part of the system, there are some important distinctions in user accounts vs service accounts, for example:
* User accounts are for humans. Service accounts are for processes, which run in pods.
* User accounts are intended to be global. Names must be unique across all namespaces of a cluster. Service accounts are namespaced.
For this example we are generating a serviceaccount for a pod and a user account for us to use with kubectl (if we wanted a global user we should have used clusterrole and clusterrolebinding).
```elixir
kubectl create serviceaccount myuser -o yaml --dry-run=client
```

<br />

The output should look something like this:
```elixir
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: null
  name: myuser
```

You can read more [here](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)

<br />

**Role**:

This role has admin-like privileges, the allowed verbs are, we are using \* which means all:
* list
* get
* watch
* create
* patch
* update
* delete

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: null
  name: myrole
rules:
- apiGroups:
  - ""
  resources:
  - '*'
  verbs:
  - '*'
```

You can read more [here](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#determine-the-request-verb)
and [here](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#clusterrole-example)

<br />

**Role binding**:

This is the glue that gives the permissions in the role to the service account that we created.
```elixir
kubectl create rolebinding myuser-myrole --role=myrole --serviceaccount=mynamespace:myuser --user=myotheruser -o yaml --dry-run=client
```

<br />

The output should look something like this:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  creationTimestamp: null
  name: myuser-myrole
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: myrole
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: myotheruser
- kind: ServiceAccount
  name: myuser
  namespace: mynamespace
```

You can read more [here](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#clusterrolebinding-example)

<br />

#### Example from a pod

Here we create a sample pod with curl and give it the service account with `--serviceaccount=`
```elixir
kubectl run mypod --image=curlimages/curl:latest --serviceaccount=myuser --dry-run=client -o yaml --command -- sh -c "sleep 3d"
apiVersion: v1
```

<br />

The output should look something like this:
```elixir
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: mypod
  name: mypod
spec:
  containers:
  - image: curlimages/curl:latest
    name: mypod
    resources: {}
    command:
    - sh
    - -c
    - sleep 3d
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  serviceAccountName: myuser
status: {}
```

<br />

**Applying**

Here we create all resources, this will set the namespace for the config so we don't have to worry about specifing it in the manifests or during the apply
```elixir
kubectl config set-context --current --namespace=mynamespace
```

<br />

The output should look something like this:
```elixir
Context "kind-kind" modified.
```

<br />

Applying everything:
```elixir
kubectl apply -f .
```

<br />

The output should look something like this:
```elixir
namespace/mynamespace configured
serviceaccount/myuser created
role.rbac.authorization.k8s.io/myrole created
rolebinding.rbac.authorization.k8s.io/myuser-myrole created
pod/mypod created
```

<br />

#### Validating from the pod 
Here we will jump into the pod and export the token for our service account and query the kubernetes API.
```elixir
kubectl exec -ti mypod -- sh
export TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
```

<br />

First test: 
```elixir
curl -k  https://kubernetes.default:443
```

<br />

Without using the token we get an authentication error for "system:anonymous"
```elixir
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {

  },
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/\"",
  "reason": "Forbidden",
  "details": {

  },
  "code": 403
} 
```

Note that I didn't put the whole info for our pods in our namespace because it is too verbose, but you get the idea, you can
see everything that happened there, note that we are using the namespace because we cannot list pods for all namespaces 
with this serviceaccount you can try /apis and /api/v1/ to find out more.

<br />

```elixir
curl -k  https://kubernetes.default:443/api/v1/namespaces/mynamespace/pods -H "Authorization: Bearer ${TOKEN}"
```

<br />

The output should look something like this:
```elixir
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "selfLink": "/api/v1/namespaces/mynamespace/pods",
    "resourceVersion": "10915"
  },
  "items": [
    {
      "metadata": {
        "name": "mypod",
        "namespace": "mynamespace",
        "selfLink": "/api/v1/namespaces/mynamespace/pods/mypod",
        "uid": "835e894e-c4f0-4182-b601-ff086b53fba3",
        "resourceVersion": "9824",
        "creationTimestamp": "2020-11-29T21:45:24Z",
        "labels": {
          "run": "mypod"
        },
        "managedFields": [
          {
          ....
          ....
          ....
            "lastState": {

            },
            "ready": true,
            "restartCount": 0,
            "image": "docker.io/curlimages/curl:latest",
            "imageID": "docker.io/curlimages/curl@sha256:5329ee280d3d91f3e48885f18c884af5907b68c6aa80f411927a5a28c4f5df07",
            "containerID": "containerd://cdc729aacdc5ce3b1b81ff443ea7c6554ff85a4187e7af2ecda700e28a96fa51",
            "started": true
          }
        ],
        "qosClass": "BestEffort"
      }
    }
  ]
}
```
Notice that to be able to reach the kubernetes service since it's in a different namespace we need to specify it with `.default` (because it's in the default namespace) try: `kubectl get svc -A` to see all services.

<br />

Everything went well from our pod and we can communicate to the API from our pod, let's see if it works for kubectl as well.

<br />

#### Generate kubectl config

Fetch the token (as you can see it's saved as a kubernetes secret, so it's mounted to pods as any other secret but automatically thanks to the service account)
```elixir
kubectl describe serviceAccounts myuser
```

<br />

The output should look something like this:
```elixir
Name:                myuser
Namespace:           mynamespace
Labels:              <none>
Annotations:         <none>
Image pull secrets:  <none>
Mountable secrets:   myuser-token-mckzz
Tokens:              myuser-token-mckzz
Events:              <none>
```

<br />

The next step is to retrieve the secret (token):
```elixir
kubectl get secrets myuser-token-mckzz -o yaml
```

<br />

The output should look something like this:
```elixir
apiVersion: v1
data:
  ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJd01URXlPVEl3TkRjME5Wb1hEVE13TVRFeU56SXdORGMwTlZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTVBZCkdMR2s1QlZ0V091dGhJcldranFIRStlOW5VeDk1cDcydFREa2JnR2JCa2RZZm12dzFadUYrNGx4dnhDOU9CMUIKdTVyUDZsSlNHeW9NbDRGLzlQQ0s0OVovMXFyRm5qMFQzQkorZ2RTMm11YzZVM0QzbkFOV1FUMjJKcERlQ2lpMQorQ2xNbTBwMzVLbXJlS1NyRTlHOC9ISW9YaGRHZk1qWEVLSkxpdmlFUWxCcUVLcWw3dzlsZnlmZFpEV3pVZEN0CmU5ZW9QNlBhV21waVNUS2dYcExvdFFGb2VMWWJGQTlDU2l1YllmUk85eVJLb25GeDB4dHlSaW5kaWtRaHF2ejUKQXVhbVZTdm1xNk5mUXlBL3JWbzN3b3ptazRjWVBab215QlBHMHZreGczcE1TaFVKaHVSVEthN0xNdFBvMS9GNAowMlFtdUdIb1dCUTVPYjQ0VlVjQ0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFDNTZFS1g0T0JSa09xYkpDeVBlaUFVQm9yUUMKajQ3aktld3FkUHREVk01VkZ1MGNtV3lYd1phM2pGbGt0YnRCd1J6SS82R2FpdmhCaEZhak5lUEZaazlQVkV2MQpVekt1bkIxMDBvU0xIL3VscmVsekxYc0FoQXFJKzV3VTVhemhPK2t4UDZlejBmOGh6d3lDSjBuWlB4c2kvZmhWClBwOUt3ek11cnBtb3ArWmhjUEQ3aXIxbWxuTTd1aDNRczRxNk92ZzZpWjdabjQ4OUwyR1ZhczRUUk1QWDFhc1MKYkhzbmR2b2IvOEJLalExaVE0UWI3cHRoK1MzTUZzb25WUzd4VE9XZWlqM3hSUEM4RzlYYUdKWUVxNGczNDBYZgprWE1FZUVKTXI4eWlRUjNWMy83VmlTOFhtSm9EbzJjeVJhbnV2SGpsVXVWaGtpNTB2SDYvbXdIZ2sxbz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  namespace: bXluYW1lc3BhY2U=
  token: ZXlKaGJHY2lPaUpTVXpJMU5pSXNJbXRwWkNJNkltUnRiRUUwZGtSaFZWVkdRblpZUzBaTkxUVnhjSFZGZWw4MVpIWkJRVlZ5V1ZSTVJWTkJWMDVTWVdNaWZRLmV5SnBjM01pT2lKcmRXSmxjbTVsZEdWekwzTmxjblpwWTJWaFkyTnZkVzUwSWl3aWEzVmlaWEp1WlhSbGN5NXBieTl6WlhKMmFXTmxZV05qYjNWdWRDOXVZVzFsYzNCaFkyVWlPaUp0ZVc1aGJXVnpjR0ZqWlNJc0ltdDFZbVZ5Ym1WMFpYTXVhVzh2YzJWeWRtbGpaV0ZqWTI5MWJuUXZjMlZqY21WMExtNWhiV1VpT2lKdGVYVnpaWEl0ZEc5clpXNHRiV05yZW5vaUxDSnJkV0psY201bGRHVnpMbWx2TDNObGNuWnBZMlZoWTJOdmRXNTBMM05sY25acFkyVXRZV05qYjNWdWRDNXVZVzFsSWpvaWJYbDFjMlZ5SWl3aWEzVmlaWEp1WlhSbGN5NXBieTl6WlhKMmFXTmxZV05qYjNWdWRDOXpaWEoyYVdObExXRmpZMjkxYm5RdWRXbGtJam9pWXprME9UVXpNekl0TW1GaU1DMDBNbVZsTFRrd1pEQXROVEEwWVROak56VXlaakEzSWl3aWMzVmlJam9pYzNsemRHVnRPbk5sY25acFkyVmhZMk52ZFc1ME9tMTVibUZ0WlhOd1lXTmxPbTE1ZFhObGNpSjkuaVA2UU9YMGFfVHNaVWVLXzlhN0doellxQm13NkVKd3RqUVFTRUFlN0Z1VDRRNjA3MmJWZ3dlVnNXaXJFVW9yOTRpd2VfamhrX1NRWmpRMk5CS2EtWU1qX1N3U21uaDZRQ3lGY2JXcWlpZjFScmZyUWtHb011Q19PLVd3VWtRS0hTVVhZRUUtZlh3Nk1UYVZhZXlpVE5wMVNWQUFYSHVrbV9xZ0J0WTE1OUZ5Vm15anBNRXVSRUYwamJockQxNjBSS0JaLUFoTVc4cWFQSmlGaE1Ia0Z1RHZmMlM2OVFRVGpmVXJhVmdlMThJNzFNUmtmWGRsdHN4dlgzcjRXMmp6Vk1jdFFrR1MzZmRYeWRRRFFlYjlaeURrWlpIRFlhcmx2aUE3djZFMzhrMTctY2k0MV9XalJCNHRFTWxTLUZzbHc1VV9nN0owX1dITmEzVEJibE9rdjF3
kind: Secret
metadata:
  annotations:
    kubernetes.io/service-account.name: myuser
    kubernetes.io/service-account.uid: c9495332-2ab0-42ee-90d0-504a3c752f07
  creationTimestamp: "2020-11-29T21:42:30Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:data:
        .: {}
        f:ca.crt: {}
        f:namespace: {}
        f:token: {}
      f:metadata:
        f:annotations:
          .: {}
          f:kubernetes.io/service-account.name: {}
          f:kubernetes.io/service-account.uid: {}
      f:type: {}
    manager: kube-controller-manager
    operation: Update
    time: "2020-11-29T21:42:30Z"
  name: myuser-token-mckzz
  namespace: mynamespace
  resourceVersion: "9294"
  selfLink: /api/v1/namespaces/mynamespace/secrets/myuser-token-mckzz
  uid: 99eb2685-4c08-40b8-97cc-94973dcafb5b
type: kubernetes.io/service-account-token
```

<br />

Use this sample kubeconfig and replace the values
```elixir
apiVersion: v1
kind: Config
users:
- name: svcs-acct-dply
  user:
    token: <replace this with token info>
clusters:
- cluster:
    certificate-authority-data: <replace this with certificate-authority-data info>
    server: <replace this with server info>
  name: self-hosted-cluster
contexts:
- context:
    cluster: self-hosted-cluster
    user: svcs-acct-dply
  name: svcs-acct-context
current-context: svcs-acct-context
```

<br />

Your config with the updated values should look something like this:
```elixir
apiVersion: v1
kind: Config
users:
- name: myotheruser
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI6ImRtbEE0dkRhVVVGQnZYS0ZNLTVxcHVFel81ZHZBQVVyWVRMRVNBV05SYWMifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJteW5hbWVzcGFjZSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJteXVzZXItdG9rZW4tbWNrenoiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoibXl1c2VyIiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiYzk0OTUzMzItMmFiMC00MmVlLTkwZDAtNTA0YTNjNzUyZjA3Iiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50Om15bmFtZXNwYWNlOm15dXNlciJ9.iP6QOX0a_TsZUeK_9a7GhzYqBmw6EJwtjQQSEAe7FuT4Q6072bVgweVsWirEUor94iwe_jhk_SQZjQ2NBKa-YMj_SwSmnh6QCyFcbWqiif1RrfrQkGoMuC_O-WwUkQKHSUXYEE-fXw6MTaVaeyiTNp1SVAAXHukm_qgBtY159FyVmyjpMEuREF0jbhrD160RKBZ-AhMW8qaPJiFhMHkFuDvf2S69QQTjfUraVge18I71MRkfXdltsxvX3r4W2jzVMctQkGS3fdXydQDQeb9ZyDkZZHDYarlviA7v6E38k17-ci41_WjRB4tEMlS-Fslw5U_g7J0_WHNa3TBblOkv1w
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJd01URXlPVEl3TkRjME5Wb1hEVE13TVRFeU56SXdORGMwTlZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTVBZCkdMR2s1QlZ0V091dGhJcldranFIRStlOW5VeDk1cDcydFREa2JnR2JCa2RZZm12dzFadUYrNGx4dnhDOU9CMUIKdTVyUDZsSlNHeW9NbDRGLzlQQ0s0OVovMXFyRm5qMFQzQkorZ2RTMm11YzZVM0QzbkFOV1FUMjJKcERlQ2lpMQorQ2xNbTBwMzVLbXJlS1NyRTlHOC9ISW9YaGRHZk1qWEVLSkxpdmlFUWxCcUVLcWw3dzlsZnlmZFpEV3pVZEN0CmU5ZW9QNlBhV21waVNUS2dYcExvdFFGb2VMWWJGQTlDU2l1YllmUk85eVJLb25GeDB4dHlSaW5kaWtRaHF2ejUKQXVhbVZTdm1xNk5mUXlBL3JWbzN3b3ptazRjWVBab215QlBHMHZreGczcE1TaFVKaHVSVEthN0xNdFBvMS9GNAowMlFtdUdIb1dCUTVPYjQ0VlVjQ0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFDNTZFS1g0T0JSa09xYkpDeVBlaUFVQm9yUUMKajQ3aktld3FkUHREVk01VkZ1MGNtV3lYd1phM2pGbGt0YnRCd1J6SS82R2FpdmhCaEZhak5lUEZaazlQVkV2MQpVekt1bkIxMDBvU0xIL3VscmVsekxYc0FoQXFJKzV3VTVhemhPK2t4UDZlejBmOGh6d3lDSjBuWlB4c2kvZmhWClBwOUt3ek11cnBtb3ArWmhjUEQ3aXIxbWxuTTd1aDNRczRxNk92ZzZpWjdabjQ4OUwyR1ZhczRUUk1QWDFhc1MKYkhzbmR2b2IvOEJLalExaVE0UWI3cHRoK1MzTUZzb25WUzd4VE9XZWlqM3hSUEM4RzlYYUdKWUVxNGczNDBYZgprWE1FZUVKTXI4eWlRUjNWMy83VmlTOFhtSm9EbzJjeVJhbnV2SGpsVXVWaGtpNTB2SDYvbXdIZ2sxbz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
    server: https://127.0.0.1:35617
  name: kind
contexts:
- context:
    cluster: kind
    user: myotheruser
  name: kind
current-context: kind
```

<br />

#### Then we can test it by doing
```elixir
export KUBECONFIG=$(pwd)/kubeconfig-myotheruser
kubectl get all
```

<br />

The output should look something like this:
```elixir
NAME              READY   STATUS    RESTARTS   AGE
pod/task-pv-pod   1/1     Running   0          96m

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   97m
Error from server (Forbidden): daemonsets.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "daemonsets" in API group "apps" in the namespace "default"
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "deployments" in API group "apps" in the namespace "default"
Error from server (Forbidden): replicasets.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "replicasets" in API group "apps" in the namespace "default"
Error from server (Forbidden): statefulsets.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "statefulsets" in API group "apps" in the namespace "default"
Error from server (Forbidden): horizontalpodautoscalers.autoscaling is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "horizontalpodautoscalers" in API group "autoscaling" in the namespace "default"
Error from server (Forbidden): jobs.batch is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "jobs" in API group "batch" in the namespace "default"
Error from server (Forbidden): cronjobs.batch is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "cronjobs" in API group "batch" in the namespace "default"
```
Note: I used `kubectl config view` to discover the kind endpoint which is `server: https://127.0.0.1:35617` in my case, 
then replaced the values from the secret for the CA and the service account token/secret, also note that you need to decode 
from base64 when using `kubectl get -o yaml`, also note that we will get errors when trying to do things outside of our 
namespace because we simply don't have permissions, this is a really powerful way to give permissions to users and this 
works because we created the role binding for our extra user and for the pod service account (be careful when wiring things up).

<br />

You can read more [here](http://docs.shippable.com/deploy/tutorial/create-kubeconfig-for-self-hosted-kubernetes-cluster/)
and [here](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)

<br />

#### Clean up
Always remember to clean up your local machine / cluster / etc, in my case `kind delete cluster` will do it.

<br />

### Errata
If you spot any error or have any suggestion, please send me a message so it gets fixed.

<br />
---lang---
%{
  title: "Kubernetes: autenticacion y autorizacion",
  author: "Gabriel Garrido",
  description: "En este articulo exploramos que son y como funcionan en kubernetes...",
  tags: ~w(kubernetes linux security networking),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![kubernetes](/images/kubernetes.webp){:class="mx-auto"}

#### **Introducción**
En este artículo vamos a explorar cómo funciona la autenticación y la autorización en Kubernetes. Pero primero, ¿cuál es la diferencia?

<br />

**Autenticación**:

Cuando validás tu identidad contra un servicio o sistema, estás autenticado, lo que significa que el sistema te reconoce 
como un usuario válido. En Kubernetes, cuando creás los clusters, básicamente creás una CA (Autoridad Certificadora) que luego 
usás para generar certificados para todos los componentes y usuarios.

<br />

**Autorización**:

Una vez que estás autenticado, el sistema necesita saber si tenés suficientes privilegios para hacer lo que quieras. 
En Kubernetes, esto se conoce como RBAC (Control de Acceso Basado en Roles), y se traduce en roles como entidades con 
permisos que están asociados a cuentas de servicio a través de vinculaciones de roles (role bindings) cuando las cosas están 
delimitadas a un namespace específico. De lo contrario, podés tener un cluster role y un cluster role binding.

<br />

Así que vamos a crear un namespace, una serviceaccount, un role y una role binding, luego generamos un kubeconfig para probar todo.

<br />

Los recursos para este artículo los podés encontrar aquí: [RBAC Example](https://github.com/kainlite/rbac-example)

<br />

#### Vamos al grano
Empecemos. Voy a usar estos generadores, pero estoy guardando los resultados en un archivo y luego aplicándolos.

<br />

**Namespace**:

El recurso de namespace es como un contenedor para otros recursos y es muy útil cuando estás desplegando muchas apps en el mismo cluster o hay varios usuarios:
```elixir
kubectl create namespace mynamespace -o yaml --dry-run=client
```

<br />

La salida deberia verse asi:
```elixir
apiVersion: v1
kind: Namespace
metadata:
  creationTimestamp: null
  name: mynamespace
spec: {}
status: {}
```

Podés ver más información [aquí](https://kubernetes.io/docs/concepts/overview/working-with-objects/namespaces/)

<br />

**Service account**:

La service account es tu identidad dentro del sistema. Hay algunas diferencias importantes entre cuentas de usuario y cuentas de servicio. Por ejemplo:
* Las cuentas de usuario son para humanos. Las cuentas de servicio son para procesos que se ejecutan en pods.
* Las cuentas de usuario están pensadas para ser globales. Los nombres deben ser únicos en todos los namespaces de un cluster. Las cuentas de servicio están delimitadas por namespaces.
Para este ejemplo, estamos generando una service account para un pod y una cuenta de usuario para nosotros para usar con kubectl (si quisiéramos un usuario global, deberíamos haber usado clusterrole y clusterrolebinding).
```elixir
kubectl create serviceaccount myuser -o yaml --dry-run=client
```

<br>

La salida deberia verse asi:
```elixir
apiVersion: v1
kind: ServiceAccount
metadata:
  creationTimestamp: null
  name: myuser
```

Podés ver más información [aquí](https://kubernetes.io/docs/reference/access-authn-authz/authentication/)

<br />

**Role**:

Este role tiene privilegios similares a los de un admin. Los verbos permitidos son los siguientes, estamos usando \* que significa "todos":
* list
* get
* watch
* create
* patch
* update
* delete

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  creationTimestamp: null
  name: myrole
rules:
- apiGroups:
  - ""
  resources:
  - '*'
  verbs:
  - '*'
```

<br>

Podés ver más información [aquí](https://kubernetes.io/docs/reference/access-authn-authz/authorization/#determine-the-request-verb)
y [aquí](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#clusterrole-example)

<br />

**Role binding**:

Esto es lo que une los permisos del role a la service account que creamos.
```elixir
kubectl create rolebinding myuser-myrole --role=myrole --serviceaccount=mynamespace:myuser --user=myotheruser -o yaml --dry-run=client
```

<br />

La salida deberia verse asi:
```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  creationTimestamp: null
  name: myuser-myrole
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: myrole
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: myotheruser
- kind: ServiceAccount
  name: myuser
  namespace: mynamespace
```

Podés ver más información [aquí](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#clusterrolebinding-example)

<br />

#### Ejemplo desde un pod
Aquí creamos un pod de ejemplo con curl y le asignamos la service account con `--serviceaccount=`
```elixir
kubectl run mypod --image=curlimages/curl:latest --serviceaccount=myuser --dry-run=client -o yaml --command -- sh -c "sleep 3d"
```

<br />

La salida deberia verse asi:
```elixir
apiVersion: v1
kind: Pod
metadata:
  creationTimestamp: null
  labels:
    run: mypod
  name: mypod
spec:
  containers:
  - image: curlimages/curl:latest
    name: mypod
    resources: {}
    command:
    - sh
    - -c
    - sleep 3d
  dnsPolicy: ClusterFirst
  restartPolicy: Always
  serviceAccountName: myuser
status: {}
```

<br />

**Aplicando**

Aquí creamos todos los recursos, esto establecerá el namespace en la configuración para que no tengamos que preocuparnos 
por especificarlo en los manifiestos o durante el apply
```elixir
kubectl config set-context --current --namespace=mynamespace
```

<br />

La salida deberia verse asi:
```elixir
Context "kind-kind" modified.
```

<br />

```elixir
kubectl apply -f .
```

<br />

La salida deberia verse asi:
```elixir
namespace/mynamespace configured
serviceaccount/myuser created
role.rbac.authorization.k8s.io/myrole created
rolebinding.rbac.authorization.k8s.io/myuser-myrole created
pod/mypod created
```

<br />

#### Validando desde el pod

Aquí exportamos el token para nuestra service account y hacemos una consulta a la API de Kubernetes.
```elixir
kubectl exec -ti mypod -- sh
export TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
```

<br />

Primer test: sin usar el token obtenemos un error de autenticación para "system:anonymous"
```elixir
curl -k  https://kubernetes.default:443
```

<br />

La salida deberia verse asi:
```elixir
{
  "kind": "Status",
  "apiVersion": "v1",
  "metadata": {

  },
  "status": "Failure",
  "message": "forbidden: User \"system:anonymous\" cannot get path \"/\"",
  "reason": "Forbidden",
  "details": {

  },
  "code": 403
} 
```

Nota: no puse toda la info para nuestros pods en nuestro namespace porque es demasiado, pero entendés la idea, podés
ver todo lo que pasó ahí, notá que estamos usando el namespace porque no podemos listar pods de todos los namespaces
con esta serviceaccount. Podés probar /apis y /api/v1/ para investigar más.

<br />

```elixir
curl -k  https://kubernetes.default:443/api/v1/namespaces/mynamespace/pods -H "Authorization: Bearer ${TOKEN}"
```

<br />

La salida deberia verse asi:
```elixir
{
  "kind": "PodList",
  "apiVersion": "v1",
  "metadata": {
    "selfLink": "/api/v1/namespaces/mynamespace/pods",
    "resourceVersion": "10915"
  },
  "items": [
    {
      "metadata": {
        "name": "mypod",
        "namespace": "mynamespace",
        "selfLink": "/api/v1/namespaces/mynamespace/pods/mypod",
        "uid": "835e894e-c4f0-4182-b601-ff086b53fba3",
        "resourceVersion": "9824",
        "creationTimestamp": "2020-11-29T21:45:24Z",
        "labels": {
          "run": "mypod"
        },
        "managedFields": [
          {
          ....
          ....
          ....
            "lastState": {

            },
            "ready": true,
            "restartCount": 0,
            "image": "docker.io/curlimages/curl:latest",
            "imageID": "docker.io/curlimages/curl@sha256:5329ee280d3d91f3e48885f18c884af5907b68c6aa80f411927a5a28c4f5df07",
            "containerID": "containerd://cdc729aacdc5ce3b1b81ff443ea7c6554ff85a4187e7af2ecda700e28a96fa51",
            "started": true
          }
        ],
        "qosClass": "BestEffort"
      }
    }
  ]
}
```

Notá que para poder llegar al servicio de Kubernetes, ya que está en un namespace diferente, necesitamos especificarlo 
con `.default` (porque está en el namespace default). Probá: `kubectl get svc -A` para ver todos los servicios.

<br />

Todo funcionó bien desde nuestro pod y podemos comunicarnos con la API desde allí. Veamos si también funciona con kubectl.

<br />

#### Generar config para kubectl

Obtené el token (como podés ver,

Está guardado como un secreto de Kubernetes, por lo que se monta en los pods como cualquier otro secreto, pero automáticamente gracias a la service account)
```elixir
kubectl describe serviceAccounts myuser
```

<br />

La salida deberia verse asi:
```elixir
Name:                myuser
Namespace:           mynamespace
Labels:              <none>
Annotations:         <none>
Image pull secrets:  <none>
Mountable secrets:   myuser-token-mckzz
Tokens:              myuser-token-mckzz
Events:              <none>
```

<br />

```elixir
kubectl get secrets myuser-token-mckzz -o yaml
```

<br />

La salida deberia verse asi:
```elixir
apiVersion: v1
data:
  ca.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJd01URXlPVEl3TkRjME5Wb1hEVE13TVRFeU56SXdORGMwTlZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTVBZCkdMR2s1QlZ0V091dGhJcldranFIRStlOW5VeDk1cDcydFREa2JnR2JCa2RZZm12dzFadUYrNGx4dnhDOU9CMUIKdTVyUDZsSlNHeW9NbDRGLzlQQ0s0OVovMXFyRm5qMFQzQkorZ2RTMm11YzZVM0QzbkFOV1FUMjJKcERlQ2lpMQorQ2xNbTBwMzVLbXJlS1NyRTlHOC9ISW9YaGRHZk1qWEVLSkxpdmlFUWxCcUVLcWw3dzlsZnlmZFpEV3pVZEN0CmU5ZW9QNlBhV21waVNUS2dYcExvdFFGb2VMWWJGQTlDU2l1YllmUk85eVJLb25GeDB4dHlSaW5kaWtRaHF2ejUKQXVhbVZTdm1xNk5mUXlBL3JWbzN3b3ptazRjWVBab215QlBHMHZreGczcE1TaFVKaHVSVEthN0xNdFBvMS9GNAowMlFtdUdIb1dCUTVPYjQ0VlVjQ0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFDNTZFS1g0T0JSa09xYkpDeVBlaUFVQm9yUUMKajQ3aktld3FkUHREVk01VkZ1MGNtV3lYd1phM2pGbGt0YnRCd1J6SS82R2FpdmhCaEZhak5lUEZaazlQVkV2MQpVekt1bkIxMDBvU0xIL3VscmVsekxYc0FoQXFJKzV3VTVhemhPK2t4UDZlejBmOGh6d3lDSjBuWlB4c2kvZmhWClBwOUt3ek11cnBtb3ArWmhjUEQ3aXIxbWxuTTd1aDNRczRxNk92ZzZpWjdabjQ4OUwyR1ZhczRUUk1QWDFhc1MKYkhzbmR2b2IvOEJLalExaVE0UWI3cHRoK1MzTUZzb25WUzd4VE9XZWlqM3hSUEM4RzlYYUdKWUVxNGczNDBYZgprWE1FZUVKTXI4eWlRUjNWMy83VmlTOFhtSm9EbzJjeVJhbnV2SGpsVXVWaGtpNTB2SDYvbXdIZ2sxbz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
  namespace: bXluYW1lc3BhY2U=
  token: ZXlKaGJHY2lPaUpTVXpJMU5pSXNJbXRwWkNJNkltUnRiRUUwZGtSaFZWVkdRblpZUzBaTkxUVnhjSFZGZWw4MVpIWkJRVlZ5V1ZSTVJWTkJWMDVTWVdNaWZRLmV5SnBjM01pT2lKcmRXSmxjbTVsZEdWekwzTmxjblpwWTJWaFkyTnZkVzUwSWl3aWEzVmlaWEp1WlhSbGN5NXBieTl6WlhKMmFXTmxZV05qYjNWdWRDOXVZVzFsYzNCaFkyVWlPaUp0ZVc1aGJXVnpjR0ZqWlNJc0ltdDFZbVZ5Ym1WMFpYTXVhVzh2YzJWeWRtbGpaV0ZqWTI5MWJuUXZjMlZqY21WMExtNWhiV1VpT2lKdGVYVnpaWEl0ZEc5clpXNHRiV05yZW5vaUxDSnJkV0psY201bGRHVnpMbWx2TDNObGNuWnBZMlZoWTJOdmRXNTBMM05sY25acFkyVXRZV05qYjNWdWRDNXVZVzFsSWpvaWJYbDFjMlZ5SWl3aWEzVmlaWEp1WlhSbGN5NXBieTl6WlhKMmFXTmxZV05qYjNWdWRDOXpaWEoyYVdObExXRmpZMjkxYm5RdWRXbGtJam9pWXprME9UVXpNekl0TW1GaU1DMDBNbVZsTFRrd1pEQXROVEEwWVROak56VXlaakEzSWl3aWMzVmlJam9pYzNsemRHVnRPbk5sY25acFkyVmhZMk52ZFc1ME9tMTVibUZ0WlhOd1lXTmxPbTE1ZFhObGNpSjkuaVA2UU9YMGFfVHNaVWVLXzlhN0doellxQm13NkVKd3RqUVFTRUFlN0Z1VDRRNjA3MmJWZ3dlVnNXaXJFVW9yOTRpd2VfamhrX1NRWmpRMk5CS2EtWU1qX1N3U21uaDZRQ3lGY2JXcWlpZjFScmZyUWtHb011Q19PLVd3VWtRS0hTVVhZRUUtZlh3Nk1UYVZhZXlpVE5wMVNWQUFYSHVrbV9xZ0J0WTE1OUZ5Vm15anBNRXVSRUYwamJockQxNjBSS0JaLUFoTVc4cWFQSmlGaE1Ia0Z1RHZmMlM2OVFRVGpmVXJhVmdlMThJNzFNUmtmWGRsdHN4dlgzcjRXMmp6Vk1jdFFrR1MzZmRYeWRRRFFlYjlaeURrWlpIRFlhcmx2aUE3djZFMzhrMTctY2k0MV9XalJCNHRFTWxTLUZzbHc1VV9nN0owX1dITmEzVEJibE9rdjF3
kind: Secret
metadata:
  annotations:
    kubernetes.io/service-account.name: myuser
    kubernetes.io/service-account.uid: c9495332-2ab0-42ee-90d0-504a3c752f07
  creationTimestamp: "2020-11-29T21:42:30Z"
  managedFields:
  - apiVersion: v1
    fieldsType: FieldsV1
    fieldsV1:
      f:data:
        .: {}
        f:ca.crt: {}
        f:namespace: {}
        f:token: {}
      f:metadata:
        f:annotations:
          .: {}
          f:kubernetes.io/service-account.name: {}
          f:kubernetes.io/service-account.uid: {}
      f:type: {}
    manager: kube-controller-manager
    operation: Update
    time: "2020-11-29T21:42:30Z"
  name: myuser-token-mckzz
  namespace: mynamespace
  resourceVersion: "9294"
  selfLink: /api/v1/namespaces/mynamespace/secrets/myuser-token-mckzz
  uid: 99eb2685-4c08-40b8-97cc-94973dcafb5b
type: kubernetes.io/service-account-token
```

<br />

Usá este ejemplo de kubeconfig y reemplazá los valores
```elixir
apiVersion: v1
kind: Config
users:
- name: svcs-acct-dply
  user:
    token: <reemplazá esto con la info del token>
clusters:
- cluster:
    certificate-authority-data: <reemplazá esto con la info del certificado>
    server: <reemplazá esto con la info del servidor>
  name: self-hosted-cluster
contexts:
- context:
    cluster: self-hosted-cluster
    user: svcs-acct-dply
  name: svcs-acct-context
current-context: svcs-acct-context
```

<br />

El resultado sería algo como esto:
```elixir
apiVersion: v1
kind: Config
users:
- name: myotheruser
  user:
    token: eyJhbGciOiJSUzI1NiIsImtpZCI6ImRtbEE0dkRhVVVGQnZYS0ZNLTVxcHVFel81ZHZBQVVyWVRMRVNBV05SYWMifQ.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJteW5hbWVzcGFjZSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJteXVzZXItdG9rZW4tbWNrenoiLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC5uYW1lIjoibXl1c2VyIiwia3ViZXJuZXRzLmlvL3NlcnZpY2VhY2NvdW50L3NlcnZpY2UtYWNjb3VudC51aWQiOiJjOTQ5NTMzMi0yYWIwLTQyZWUtOTBkMC01MDRhM2M3NTJmMDciLCJzdWIiOiJzeXN0ZW06c2VydmljZWFjY291bnQ6bXluYW1lc3BhY2U6bXl1c2VyIn0.iP6QOX0a_TsZUeK_9a7GhzYqBmw6EJwtjQQSEAe7FuT4Q6072bVgweVsWirEUor94iwe_jhk_SQZjQ2NBKa-YMj_SwSmnh6QCyFcbWqiif1RrfrQkGoMuC_O-WwUkQKHSUXYEE-fXw6MTaVaeyiTNp1SVAAXHukm_qgBtY159FyVmyjpMEuREF0jbhrD160RKBZ-AhMW8qaPJiFhMHkFuDvf2S69QQTjfUraVge18I71MRkfXdltsxvX3r4W2jzVMctQkGS3fdXydQDQeb9ZyDkZZHDYarlviA7v6E38k17-ci41_WjRB4tEMlS-Fslw5U_g7J0_WHNa3TBblOkv1w
clusters:
- cluster:
    certificate-authority-data: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUN5RENDQWJDZ0F3SUJBZ0lCQURBTkJna3Foa2lHOXcwQkFRc0ZBREFWTVJNd0VRWURWUVFERXdwcmRXSmwKY201bGRHVnpNQjRYRFRJd01URXlPVEl3TkRjME5Wb1hEVE13TVRFeU56SXdORGMwTlZvd0ZURVRNQkVHQTFVRQpBeE1LYTNWaVpYSnVaWFJsY3pDQ0FTSXdEUVlKS29aSWh2Y05BUUVCQlFBRGdnRVBBRENDQVFvQ2dnRUJBTVBZCkdMR2s1QlZ0V091dGhJcldranFIRStlOW5VeDk1cDcydFREa2JnR2JCa2RZZm12dzFadUYrNGx4dnhDOU9CMUIKdTVyUDZsSlNHeW9NbDRGLzlQQ0s0OVovMXFyRm5qMFQzQkorZ2RTMm11YzZVM0QzbkFOV1FUMjJKcERlQ2lpMQorQ2xNbTBwMzVLbXJlS1NyRTlHOC9ISW9YaGRHZk1qWEVLSkxpdmlFUWxCcUVLcWw3dzlsZnlmZFpEV3pVZEN0CmU5ZW9QNlBhV21waVNUS2dYcExvdFFGb2VMWWJGQTlDU2l1YllmUk85eVJLb25GeDB4dHlSaW5kaWtRaHF2ejUKQXVhbVZTdm1xNk5mUXlBL3JWbzN3b3ptazRjWVBab215QlBHMHZreGczcE1TaFVKaHVSVEthN0xNdFBvMS9GNAowMlFtdUdIb1dCUTVPYjQ0VlVjQ0F3RUFBYU1qTUNFd0RnWURWUjBQQVFIL0JBUURBZ0trTUE4R0ExVWRFd0VCCi93UUZNQU1CQWY4d0RRWUpLb1pJaHZjTkFRRUxCUUFEZ2dFQkFDNTZFS1g0T0JSa09xYkpDeVBlaUFVQm9yUUMKajQ3aktld3FkUHREVk01VkZ1MGNtV3lYd1phM2pGbGt0YnRCd1J6SS82R2FpdmhCaEZhak5lUEZaazlQVkV2MQpVekt1bkIxMDBvU0xIL3VscmVsekxYc0FoQXFJKzV3VTVhemhPK2t4UDZlejBmOGh6d3lDSjBuWlB4c2kvZmhWClBwOUt3ek11cnBtb3ArWmhjUEQ3aXIxbWxuTTd1aDNRczRxNk92ZzZpWjdabjQ4OUwyR1ZhczRUUk1QWDFhc1MKYkhzbmR2b2IvOEJLalExaVE0UWI3cHRoK1MzTUZzb25WUzd4VE9XZWlqM3hSUEM4RzlYYUdKWUVxNGczNDBYZgprWE1FZUVKTXI4eWlRUjNWMy83VmlTOFhtSm9EbzJjeVJhbnV2SGpsVXVWaGtpNTB2SDYvbXdIZ2sxbz0KLS0tLS1FTkQgQ0VSVElGSUNBVEUtLS0tLQo=
    server: https://127.0.0.1:35617
  name: kind
contexts:
- context:
    cluster: kind
    user: myotheruser
  name: kind
current-context: kind
```

<br />

#### Luego podemos probarlo haciendo
```elixir
export KUBECONFIG=$(pwd)/kubeconfig-myotheruser
kubectl get all
```

<br />

La salida deberia verse asi:
```elixir
NAME              READY   STATUS    RESTARTS   AGE
pod/task-pv-pod   1/1     Running   0          96m

NAME                 TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)   AGE
service/kubernetes   ClusterIP   10.96.0.1    <none>        443/TCP   97m
Error from server (Forbidden): daemonsets.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "daemonsets" in API group "apps" in the namespace "default"
Error from server (Forbidden): deployments.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "deployments" in API group "apps" in the namespace "default"
Error from server (Forbidden): replicasets.apps

 is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "replicasets" in API group "apps" in the namespace "default"
Error from server (Forbidden): statefulsets.apps is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "statefulsets" in API group "apps" in the namespace "default"
Error from server (Forbidden): horizontalpodautoscalers.autoscaling is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "horizontalpodautoscalers" in API group "autoscaling" in the namespace "default"
Error from server (Forbidden): jobs.batch is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "jobs" in API group "batch" in the namespace "default"
Error from server (Forbidden): cronjobs.batch is forbidden: User "system:serviceaccount:mynamespace:myuser" cannot list resource "cronjobs" in API group "batch" in the namespace "default"
```

<br />

Notas: Usé `kubectl config view` para descubrir el endpoint de kind que es `server: https://127.0.0.1:35617` en mi caso. 
Luego reemplacé los valores del secreto para el CA y el token/secreto de la service account. También notá que necesitás 
decodificar desde base64 cuando usás `kubectl get -o yaml`. Además, verás errores cuando intentes hacer cosas fuera de 
nuestro namespace porque simplemente no tenemos permisos. Este es un método muy poderoso para otorgar permisos a los usuarios,
y esto funciona porque creamos el role binding para nuestro usuario adicional y para la service account del pod (tené cuidado al configurar todo).

<br />

Podés ver más [aquí](http://docs.shippable.com/deploy/tutorial/create-kubeconfig-for-self-hosted-kubernetes-cluster/)
y [aquí](https://kubernetes.io/docs/tasks/access-application-cluster/configure-access-multiple-clusters/)

<br />

#### Clean up
Siempre recordá limpiar tu máquina local / cluster / etc. En mi caso, `kind delete cluster` lo hará.

<br />

### Errata
Si encontrás algún error o tenés alguna sugerencia, mandame un mensaje para corregirlo.

<br />
