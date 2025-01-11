%{
  title: "Kubernetes permanent port-forward (or close to that...)",
  author: "Gabriel Garrido",
  description: "We will see how to craft and use a tool to manage our Kubernetes port-forward...",
  tags: ~w(kubernetes rust),
  published: true,
  image: "kube-forward.png",
  sponsored: false,
  video: "",
  lang: "en"
}
---

##### **Introduction**
In this article we will explore how to create and use a Kubernetes port-forward tool, the main objective is to
declaratively configure the port-forwards that we need and have them going by firing a single command.

If you want to try it, it is called `kube-forward` and you can find it [here](https://github.com/kainlite/kube-forward),
check the releases page as there are already binaries pre-compiled via github actions, I have only tested on x86_64, but
let me know if you try the others and they work!

A few notes, be sure that the ports you are using are free, also have the right Kubernetes configuration exported as the
client will auto-detect the default context.

<br />

##### **Configuration**
First, lets check the configuration to see what it looks like and declare what we want to connect to...
```elixir
- name: "argocd-ui"                                 # identifier for the logs
  target: "argocd-server.argocd"                    # deployment_name.namespace
  ports:
    local: 8080                                     # custom local port
    remote: 8080                                    # remote port
  options:
    retry_interval: 5s                              # if the connection fails, retry automatically in x seconds
    max_retries: 30                                 # max amount of retries
    health_check_interval: 10s                      # check every x seconds if everything is still working
  pod_selector:
    label: "app.kubernetes.io/name=argocd-server"   # use labels to select your pods

- name: "postgres"
  target: "postgres.tr"
  ports:
    local: 5434 
    remote: 5432   
  options:
    retry_interval: 5s
    max_retries: 30
    health_check_interval: 10s
  pod_selector:
    label: "app=postgres"
``` 
I added some comments to make the config easier to understand, the config might get a bit simpler over time, but for now
that's what the cli tool needs.

<br />

##### **Test it**
What would it look to run it?
```elixir
❯ RUST_LOG=info kube-forward -c config.yaml -e
2025-01-10T23:53:38.711212Z  INFO kube_forward: Setting up port-forward for argocd-ui
2025-01-10T23:53:39.346540Z  INFO kube_forward: Setting up port-forward for postgres
2025-01-10T23:53:39.464369Z  INFO kube_forward::forward: Port-forward established for argocd-ui
2025-01-10T23:53:39.465744Z  INFO kube_forward::forward: New connection for argocd-ui peer_addr=127.0.0.1:37494
2025-01-10T23:53:39.793116Z  INFO kube_forward::forward: Port-forward established for postgres
2025-01-10T23:53:39.794432Z  INFO kube_forward::forward: New connection for postgres peer_addr=127.0.0.1:57104
```
With `RUST_LOG` we can influence the amount of feedback we get, without it we will see some random connection errors
(which are safe to ignore, that's the whole point of the tool), with `-e` we can expose prometheus metrics if you are an
observability fan, and well, `-c` is pretty self-explanatory.

<br />

That would look something like this:
```elixir
❯ curl localhost:9292/metrics
# TYPE port_forward_connection_successes_total counter
port_forward_connection_successes_total{service="kube-forward",forward="postgres"} 21
port_forward_connection_successes_total{service="kube-forward",forward="argocd-ui"} 21

# TYPE port_forward_connection_attempts_total counter
port_forward_connection_attempts_total{service="kube-forward",forward="argocd-ui"} 21
port_forward_connection_attempts_total{service="kube-forward",forward="postgres"} 21

# TYPE port_forward_connected gauge
port_forward_connected{service="kube-forward",forward="argocd-ui"} 1
port_forward_connected{service="kube-forward",forward="postgres"} 1
```

<br />

##### **The code**
At the moment of this writing the code looks something like this (I will put only 2 files, there are more types, etc
but with these you will get the idea of what the code is doing and how), this is the `main.rs` file.
```elixir
use anyhow::Result;
use clap::Parser;
use kube::Client;
use metrics_exporter_prometheus::PrometheusBuilder;
use std::path::PathBuf;
use tracing::{error, info};

use kube_forward::{config::ForwardConfig, forward::PortForwardManager, util::resolve_service};

#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[arg(short, long, default_value = "config.yaml")]
    config: PathBuf,

    #[arg(short, long)]
    expose_metrics: bool,

    #[arg(short, long, default_value = "9292")]
    metrics_port: u16,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Parse command line arguments
    let cli = Cli::parse();

    // Initialize metrics
    if cli.expose_metrics {
        let builder = PrometheusBuilder::new();
        builder
            .with_http_listener(([0, 0, 0, 0], cli.metrics_port))
            .add_global_label("service", "kube-forward")
            .install()?;
    }

    // Load configuration
    let config_content = tokio::fs::read_to_string(&cli.config).await?;
    let config: Vec<ForwardConfig> = serde_yaml::from_str(&config_content)?;

    // Initialize Kubernetes client
    let client = Client::try_default().await?;

    // Create port-forward manager
    let manager = PortForwardManager::new(client.clone());

    // Set up signal handling
    let (shutdown_tx, mut shutdown_rx) = tokio::sync::broadcast::channel(1);
    let shutdown_tx_clone = shutdown_tx.clone();

    ctrlc::set_handler(move || {
        let _ = shutdown_tx_clone.send(());
    })?;

    // Start port-forwards
    for forward_config in config {
        info!("Setting up port-forward for {}", forward_config.name);

        match resolve_service(client.clone(), &forward_config.target).await {
            Ok(service_info) => {
                if let Err(e) = manager
                    .add_forward(forward_config.clone(), service_info)
                    .await
                {
                    error!(
                        "Failed to set up port-forward {}: {}",
                        forward_config.name, e
                    );
                }
            }
            Err(e) => {
                error!(
                    "Failed to resolve service for {}: {}",
                    forward_config.name, e
                );
            }
        }
    }

    // Wait for shutdown signal
    shutdown_rx.recv().await?;
    info!("Shutting down...");

    // Stop all port-forwards
    manager.stop_all().await;

    Ok(())
}
```
Which basically sets everything up and start the process of set up the port-forwards, then the most critical file is
`forward.rs`, which looks something like this:

<br />
In this file we have all the functions that do the heavy-lifting to setup and maintain the port-forwards thanks to
`kube-rs`:
```elixir
use socket2::{SockRef, TcpKeepalive};

use kube::{
    api::{Api, DeleteParams, PostParams},
    runtime::wait::{await_condition, conditions::is_pod_running},
    Client, ResourceExt,
};

use crate::{
    config::ForwardConfig,
    config::PodSelector,
    error::{PortForwardError, Result},
    metrics::ForwardMetrics,
    util::ServiceInfo,
};
use anyhow;
use chrono::DateTime;
use chrono::Utc;
use k8s_openapi::api::core::v1::Pod;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use tracing::{debug, error, info, warn};

use futures::TryStreamExt;

use std::net::SocketAddr;
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::TcpListener,
};
use tokio_stream::wrappers::TcpListenerStream;

#[derive(Debug)]
pub struct HealthCheck {
    pub last_check: Arc<RwLock<Option<DateTime<Utc>>>>,
    pub failures: Arc<RwLock<u32>>,
}

impl HealthCheck {
    pub fn new() -> Self {
        Self {
            last_check: Arc::new(RwLock::new(None)),
            failures: Arc::new(RwLock::new(0)),
        }
    }

    pub async fn check_connection(&self, local_port: u16) -> bool {
        use tokio::net::TcpStream;

        match TcpStream::connect(format!("127.0.0.1:{}", local_port)).await {
            Ok(_) => {
                *self.failures.write().await = 0;
                *self.last_check.write().await = Some(Utc::now());
                true
            }
            Err(_) => {
                let mut failures = self.failures.write().await;
                *failures += 1;
                false
            }
        }
    }
}

// Represents the state of a port-forward
#[derive(Debug, Clone, PartialEq)]
pub enum ForwardState {
    Starting,
    Connected,
    Disconnected,
    Failed(String),
    Stopping,
}

#[derive(Debug, Clone)]
pub struct PortForward {
    pub config: ForwardConfig,
    pub service_info: ServiceInfo,
    pub state: Arc<RwLock<ForwardState>>,
    pub shutdown: broadcast::Sender<()>,
    pub metrics: ForwardMetrics,
}

impl PortForward {
    pub fn new(config: ForwardConfig, service_info: ServiceInfo) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);
        Self {
            metrics: ForwardMetrics::new(config.name.clone()),
            config,
            service_info,
            state: Arc::new(RwLock::new(ForwardState::Starting)),
            shutdown: shutdown_tx,
        }
    }

    pub async fn start(&self, client: Client) -> Result<()> {
        let mut retry_count = 0;
        let mut shutdown_rx = self.shutdown.subscribe();

        loop {
            if retry_count >= self.config.options.max_retries {
                let err_msg = "Max retry attempts reached".to_string();
                *self.state.write().await = ForwardState::Failed(err_msg.clone());
                return Err(PortForwardError::ConnectionError(err_msg));
            }

            self.metrics.record_connection_attempt();

            match self.establish_forward(&client).await {
                Ok(()) => {
                    *self.state.write().await = ForwardState::Connected;
                    self.metrics.record_connection_success();
                    self.metrics.set_connection_status(true);
                    info!("Port-forward established for {}", self.config.name);

                    // Monitor the connection
                    tokio::select! {
                        _ = shutdown_rx.recv() => {
                            info!("Received shutdown signal for {}", self.config.name);
                            break;
                        }
                        _ = self.monitor_connection(&client) => {
                            warn!("Connection lost for {}, attempting to reconnect", self.config.name);
                            *self.state.write().await = ForwardState::Disconnected;
                        }
                    }
                }
                Err(e) => {
                    warn!(
                        "Failed to establish port-forward for {}: {}",
                        self.config.name, e
                    );
                    self.metrics.record_connection_failure();
                    self.metrics.set_connection_status(false);
                    retry_count += 1;
                    tokio::time::sleep(self.config.options.retry_interval).await;
                    continue;
                }
            }
        }

        Ok(())
    }

    async fn monitor_connection(&self, client: &Client) -> Result<()> {
        let health_check = HealthCheck::new();
        let mut interval = tokio::time::interval(self.config.options.health_check_interval);

        loop {
            interval.tick().await;

            // Check TCP connection
            if !health_check.check_connection(self.config.ports.local).await {
                return Err(PortForwardError::ConnectionError(
                    "Connection health check failed".to_string(),
                ));
            }

            // Check pod status
            if let Ok(pod) = self.get_pod(client).await {
                if let Some(status) = &pod.status {
                    if let Some(phase) = &status.phase {
                        if phase != "Running" {
                            return Err(PortForwardError::ConnectionError(
                                "Pod is no longer running".to_string(),
                            ));
                        }
                    }
                }
            } else {
                return Err(PortForwardError::ConnectionError(
                    "Pod not found".to_string(),
                ));
            }
        }
    }

    async fn establish_forward(&self, client: &Client) -> Result<()> {
        self.metrics.record_connection_attempt();
        // Get pod for the service
        let pod = self.get_pod(client).await?;
        // Clone the name to avoid lifetime issues
        let pod_name = pod.metadata.name.clone().ok_or_else(|| {
            self.metrics.record_connection_failure();
            PortForwardError::ConnectionError("Pod name not found".to_string())
        })?;

        // Create Api instance for the namespace
        let pods: Api<Pod> = Api::namespaced(client.clone(), &self.service_info.namespace);

        // Create TCP listener for the local port
        debug!(
            "Creating TCP listener for the local port: {}",
            self.config.ports.local
        );
        let addr = SocketAddr::from(([127, 0, 0, 1], self.config.ports.local));
        let listener = TcpListener::bind(addr).await.map_err(|e| {
            self.metrics.record_connection_failure();
            match e.kind() {
                std::io::ErrorKind::AddrInUse => PortForwardError::ConnectionError(format!(
                    "Port {} is already in use. Please choose a different local port",
                    self.config.ports.local
                )),
                _ => PortForwardError::ConnectionError(format!("Failed to bind to port: {}", e)),
            }
        })?;

        // Set TCP keepalive
        // let tcp = TcpStream::connect(&addr).await?;
        let ka = TcpKeepalive::new().with_time(std::time::Duration::from_secs(30));
        let sf = SockRef::from(&listener);
        let _ = sf.set_tcp_keepalive(&ka);

        // Set state to connected
        *self.state.write().await = ForwardState::Connected;
        self.metrics.record_connection_success();
        self.metrics.set_connection_status(true);

        // Clone values needed for the async task
        let state = self.state.clone();
        let name = self.config.name.clone();
        let remote_port = self.config.ports.remote;
        let mut shutdown = self.shutdown.subscribe();
        let metrics = self.metrics.clone(); // Clone metrics for the task

        // Spawn the main forwarding task
        tokio::spawn(async move {
            let mut listener_stream = TcpListenerStream::new(listener);
            let name = name.as_str(); // Use as_str() to get a &str we can copy

            loop {
                tokio::select! {
                    // Handle new connections
                    Ok(Some(client_conn)) = listener_stream.try_next() => {
                        if let Ok(peer_addr) = client_conn.peer_addr() {
                            info!(%peer_addr, "New connection for {}", name);
                            metrics.record_connection_attempt();
                        }
                        let pods = pods.clone();
                        let pod_name = pod_name.clone();
                        let metrics = metrics.clone(); // Clone metrics for the connection task

                        tokio::spawn(async move {
                            if let Err(e) = Self::forward_connection(&pods, pod_name, remote_port, client_conn).await {
                                error!("Failed to forward connection: {}", e);
                                metrics.record_connection_failure();
                            } else {
                                metrics.record_connection_success();
                            }
                        });
                    }

                    // Handle shutdown signal
                    _ = shutdown.recv() => {
                        info!("Received shutdown signal for {}", name);
                        *state.write().await = ForwardState::Disconnected;
                        metrics.set_connection_status(false);
                        break;
                    }

                    else => {
                        error!("Port forward {} listener closed", name);
                        *state.write().await = ForwardState::Failed("Listener closed unexpectedly".to_string());
                        metrics.set_connection_status(false);
                        metrics.record_connection_failure();
                        break;
                    }
                }
            }
        });

        Ok(())
    }

    async fn forward_connection(
        pods: &Api<Pod>,
        pod_name: String,
        port: u16,
        mut client_conn: impl AsyncRead + AsyncWrite + Unpin,
    ) -> anyhow::Result<()> {
        debug!("Starting port forward for port {}", port);

        // Create port forward
        let mut pf = pods
            .portforward(&pod_name, &[port])
            .await
            .map_err(|e| anyhow::anyhow!("Failed to create portforward: {}", e))?;

        // Get the stream for our port
        let mut upstream_conn = pf
            .take_stream(port) // Use port instead of 0
            .ok_or_else(|| {
                anyhow::anyhow!("Failed to get port forward stream for port {}", port)
            })?;

        debug!("Port forward stream established for port {}", port);

        // Copy data bidirectionally with timeout
        match tokio::time::timeout(
            std::time::Duration::from_secs(30), // 30 second timeout
            tokio::io::copy_bidirectional(&mut client_conn, &mut upstream_conn),
        )
        .await
        {
            Ok(Ok(_)) => {
                debug!("Connection closed normally for port {}", port);
            }
            Ok(Err(e)) => {
                warn!("Error during data transfer for port {}: {}", port, e);
                return Err(anyhow::anyhow!("Data transfer error: {}", e));
            }
            Err(_) => {
                warn!("Connection timeout for port {}", port);
                return Err(anyhow::anyhow!("Connection timeout"));
            }
        }

        // Clean up
        drop(upstream_conn);

        // Wait for the port forwarder to finish
        if let Err(e) = pf.join().await {
            warn!("Port forwarder join error: {}", e);
        }

        Ok(())
    }

    async fn get_pod(&self, client: &Client) -> Result<Pod> {
        let pods: Api<Pod> = Api::namespaced(client.clone(), &self.service_info.namespace);

        // Get all pods in the namespace
        let pod_list = pods
            .list(&kube::api::ListParams::default())
            .await
            .map_err(|e| PortForwardError::KubeError(e))?;

        for pod in pod_list.items {
            if self
                .clone()
                .matches_pod_selector(&pod, &self.config.pod_selector)
            {
                if let Some(status) = &pod.status {
                    if let Some(phase) = &status.phase {
                        if phase == "Running" {
                            return Ok(pod);
                        }
                    }
                }
            }
        }

        Err(PortForwardError::ConnectionError(format!(
            "No ready pods found matching selector for service {}",
            self.service_info.name
        )))
    }

    pub fn matches_pod_selector(self, pod: &Pod, selector: &PodSelector) -> bool {
        // If no selector is specified, fall back to checking if service name is in any label
        if selector.label.is_none() && selector.annotation.is_none() {
            return pod.metadata.labels.as_ref().map_or(false, |labels| {
                labels.values().any(|v| v == &self.service_info.name)
            });
        }

        // Check label if specified
        if let Some(label_selector) = &selector.label {
            let (key, value) = self.clone().parse_selector(label_selector);
            if !pod.metadata.labels.as_ref().map_or(false, |labels| {
                labels.get(key).map_or(false, |v| v == value)
            }) {
                return false;
            }
        }

        // Check annotation if specified
        if let Some(annotation_selector) = &selector.annotation {
            let (key, value) = self.clone().parse_selector(annotation_selector);
            if !pod
                .metadata
                .annotations
                .as_ref()
                .map_or(false, |annotations| {
                    annotations.get(key).map_or(false, |v| v == value)
                })
            {
                return false;
            }
        }

        true
    }

    pub fn parse_selector(self, selector: &str) -> (&str, &str) {
        let parts: Vec<&str> = selector.split('=').collect();
        match parts.as_slice() {
            [key, value] => (*key, *value),
            _ => ("", ""), // Return empty strings if format is invalid
        }
    }
}

// Manager to handle multiple port-forwards
pub struct PortForwardManager {
    forwards: Arc<RwLock<Vec<Arc<PortForward>>>>,
    client: Client,
}

impl PortForwardManager {
    pub fn new(client: Client) -> Self {
        Self {
            forwards: Arc::new(RwLock::new(Vec::new())),
            client,
        }
    }

    pub async fn add_forward(
        &self,
        config: ForwardConfig,
        service_info: ServiceInfo,
    ) -> Result<()> {
        let forward = Arc::new(PortForward::new(config, service_info));
        self.forwards.write().await.push(forward.clone());

        // Start the port-forward in a separate task
        let client = self.client.clone();
        tokio::spawn(async move {
            if let Err(e) = forward.start(client).await {
                error!("Port-forward failed: {}", e);
            }
        });

        Ok(())
    }

    pub async fn stop_all(&self) {
        for forward in self.forwards.read().await.iter() {
            // forward.stop().await;
            forward.shutdown.send(()).unwrap();
        }
    }
}
```

<br />

As you can see there is a lot going on, but to simplify things over:
- Iterate over the config.
- Find the pods that matches the selector.
- Try to establish a connection.
- Keep the connection up and reconnect automatically if it fails for any reason.
- On drop or close, send a shutdown signal.

I will probably do a video soon about it to explain it in a bit more detail and show the basic usage, give it a try and
let me know how it goes! Until next time!

---lang---
%{
  title: "Kubernetes redireccionamiento de puertos permanente (o cerca...) ",
  author: "Gabriel Garrido",
  description: "Vamos a ver como crear e usar una pequeña herramienta para manejar varios puertos redirigidos... ",
  tags: ~w(kubernetes rust),
  published: true,
  image: "kube-forward.png",
  sponsored: false,
  video: "",
  lang: "es"
}
---

##### **Introducción**
En este artículo, vamos a ver cómo armar y usar una herramienta para hacer port-forwarding en Kubernetes. La idea principal es configurar de forma declarativa los port-forwards que necesitamos y tenerlos andando con un solo comando.

Si lo querés probar, se llama `kube-forward` y la encontrás [acá](https://github.com/kainlite/kube-forward). Fijate en la página de releases, ya que hay binarios precompilados a través de Github Actions. Solo la probé en x86_64, ¡pero chiflame si probás las otras y andan!

Un par de cosas: asegurate de que los puertos que estás usando estén libres y de tener la configuración piola de Kubernetes exportada, porque el cliente va a autodetectar el contexto por defecto.

<br />

##### **Configuración**
Primero, vamos a chusmear la configuración para ver cómo es y declarar a qué nos queremos conectar...
```elixir
- name: "argocd-ui"                                 # identificador para los logs
  target: "argocd-server.argocd"                    # nombre_deploy.namespace
  ports:
    local: 8080                                     # puerto local
    remote: 8080                                    # puerto remoto
  options:
    retry_interval: 5s                              # reintentar cada x segundos
    max_retries: 30                                 # dejar de intentar despues de x reconneciones
    health_check_interval: 10s                      # verifica cada x segundos si la conexion sigue funcionando
  pod_selector:
    label: "app.kubernetes.io/name=argocd-server"   # usa labels para seleccionar tu pod

- name: "postgres"
  target: "postgres.tr"
  ports:
    local: 5434 
    remote: 5432   
  options:
    retry_interval: 5s
    max_retries: 30
    health_check_interval: 10s
  pod_selector:
    label: "app=postgres"
``` 
Agregue algunos comentarios para que sea mas facil de entender, seguro la configuracion se va a simplificar un poco en
el tiempo, pero por ahora asi es como funciona.

<br />

##### **Probando**
Que deberiamos ver?
```elixir
❯ RUST_LOG=info kube-forward -c config.yaml -e
2025-01-10T23:53:38.711212Z  INFO kube_forward: Setting up port-forward for argocd-ui
2025-01-10T23:53:39.346540Z  INFO kube_forward: Setting up port-forward for postgres
2025-01-10T23:53:39.464369Z  INFO kube_forward::forward: Port-forward established for argocd-ui
2025-01-10T23:53:39.465744Z  INFO kube_forward::forward: New connection for argocd-ui peer_addr=127.0.0.1:37494
2025-01-10T23:53:39.793116Z  INFO kube_forward::forward: Port-forward established for postgres
2025-01-10T23:53:39.794432Z  INFO kube_forward::forward: New connection for postgres peer_addr=127.0.0.1:57104
```
Con `RUST_LOG` podemos definir cuanta informacion nos devuelve la herramienta, estando en blanco solo veriamos errores
eventuales (que se pueden ignorar en general), con `-e` podes exponer metricas de prometheus en el puerto 9292, y `-c`
es bastante intuitivo.

<br />

Las metricas se verian algo asi (completamente innecesario):
```elixir
❯ curl localhost:9292/metrics
# TYPE port_forward_connection_successes_total counter
port_forward_connection_successes_total{service="kube-forward",forward="postgres"} 21
port_forward_connection_successes_total{service="kube-forward",forward="argocd-ui"} 21

# TYPE port_forward_connection_attempts_total counter
port_forward_connection_attempts_total{service="kube-forward",forward="argocd-ui"} 21
port_forward_connection_attempts_total{service="kube-forward",forward="postgres"} 21

# TYPE port_forward_connected gauge
port_forward_connected{service="kube-forward",forward="argocd-ui"} 1
port_forward_connected{service="kube-forward",forward="postgres"} 1
```

<br />

##### **El codigo**
Al momento de escribir esto asi es como se ve, solo voy a poner los 2 archivos principales `main.rs` y `forward.rs`, hay
mas archivos con tipos y otras cosas, pero toda la logica y lo principal esta aca.
```elixir
use anyhow::Result;
use clap::Parser;
use kube::Client;
use metrics_exporter_prometheus::PrometheusBuilder;
use std::path::PathBuf;
use tracing::{error, info};

use kube_forward::{config::ForwardConfig, forward::PortForwardManager, util::resolve_service};

#[derive(Parser)]
#[command(author, version, about)]
struct Cli {
    #[arg(short, long, default_value = "config.yaml")]
    config: PathBuf,

    #[arg(short, long)]
    expose_metrics: bool,

    #[arg(short, long, default_value = "9292")]
    metrics_port: u16,
}

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Parse command line arguments
    let cli = Cli::parse();

    // Initialize metrics
    if cli.expose_metrics {
        let builder = PrometheusBuilder::new();
        builder
            .with_http_listener(([0, 0, 0, 0], cli.metrics_port))
            .add_global_label("service", "kube-forward")
            .install()?;
    }

    // Load configuration
    let config_content = tokio::fs::read_to_string(&cli.config).await?;
    let config: Vec<ForwardConfig> = serde_yaml::from_str(&config_content)?;

    // Initialize Kubernetes client
    let client = Client::try_default().await?;

    // Create port-forward manager
    let manager = PortForwardManager::new(client.clone());

    // Set up signal handling
    let (shutdown_tx, mut shutdown_rx) = tokio::sync::broadcast::channel(1);
    let shutdown_tx_clone = shutdown_tx.clone();

    ctrlc::set_handler(move || {
        let _ = shutdown_tx_clone.send(());
    })?;

    // Start port-forwards
    for forward_config in config {
        info!("Setting up port-forward for {}", forward_config.name);

        match resolve_service(client.clone(), &forward_config.target).await {
            Ok(service_info) => {
                if let Err(e) = manager
                    .add_forward(forward_config.clone(), service_info)
                    .await
                {
                    error!(
                        "Failed to set up port-forward {}: {}",
                        forward_config.name, e
                    );
                }
            }
            Err(e) => {
                error!(
                    "Failed to resolve service for {}: {}",
                    forward_config.name, e
                );
            }
        }
    }

    // Wait for shutdown signal
    shutdown_rx.recv().await?;
    info!("Shutting down...");

    // Stop all port-forwards
    manager.stop_all().await;

    Ok(())
}
```
Basicamente configura todo e inicia el proceso para configurar los port-forwards.

<br />

El archivo mas critico es `forward.rs` que se ve algo asi, en este arhivo es donde se configura todo gracias a `kube-rs`:
```elixir
use socket2::{SockRef, TcpKeepalive};

use kube::{
    api::{Api, DeleteParams, PostParams},
    runtime::wait::{await_condition, conditions::is_pod_running},
    Client, ResourceExt,
};

use crate::{
    config::ForwardConfig,
    config::PodSelector,
    error::{PortForwardError, Result},
    metrics::ForwardMetrics,
    util::ServiceInfo,
};
use anyhow;
use chrono::DateTime;
use chrono::Utc;
use k8s_openapi::api::core::v1::Pod;
use std::sync::Arc;
use tokio::sync::{broadcast, RwLock};

use tracing::{debug, error, info, warn};

use futures::TryStreamExt;

use std::net::SocketAddr;
use tokio::{
    io::{AsyncRead, AsyncWrite},
    net::TcpListener,
};
use tokio_stream::wrappers::TcpListenerStream;

#[derive(Debug)]
pub struct HealthCheck {
    pub last_check: Arc<RwLock<Option<DateTime<Utc>>>>,
    pub failures: Arc<RwLock<u32>>,
}

impl HealthCheck {
    pub fn new() -> Self {
        Self {
            last_check: Arc::new(RwLock::new(None)),
            failures: Arc::new(RwLock::new(0)),
        }
    }

    pub async fn check_connection(&self, local_port: u16) -> bool {
        use tokio::net::TcpStream;

        match TcpStream::connect(format!("127.0.0.1:{}", local_port)).await {
            Ok(_) => {
                *self.failures.write().await = 0;
                *self.last_check.write().await = Some(Utc::now());
                true
            }
            Err(_) => {
                let mut failures = self.failures.write().await;
                *failures += 1;
                false
            }
        }
    }
}

// Represents the state of a port-forward
#[derive(Debug, Clone, PartialEq)]
pub enum ForwardState {
    Starting,
    Connected,
    Disconnected,
    Failed(String),
    Stopping,
}

#[derive(Debug, Clone)]
pub struct PortForward {
    pub config: ForwardConfig,
    pub service_info: ServiceInfo,
    pub state: Arc<RwLock<ForwardState>>,
    pub shutdown: broadcast::Sender<()>,
    pub metrics: ForwardMetrics,
}

impl PortForward {
    pub fn new(config: ForwardConfig, service_info: ServiceInfo) -> Self {
        let (shutdown_tx, _) = broadcast::channel(1);
        Self {
            metrics: ForwardMetrics::new(config.name.clone()),
            config,
            service_info,
            state: Arc::new(RwLock::new(ForwardState::Starting)),
            shutdown: shutdown_tx,
        }
    }

    pub async fn start(&self, client: Client) -> Result<()> {
        let mut retry_count = 0;
        let mut shutdown_rx = self.shutdown.subscribe();

        loop {
            if retry_count >= self.config.options.max_retries {
                let err_msg = "Max retry attempts reached".to_string();
                *self.state.write().await = ForwardState::Failed(err_msg.clone());
                return Err(PortForwardError::ConnectionError(err_msg));
            }

            self.metrics.record_connection_attempt();

            match self.establish_forward(&client).await {
                Ok(()) => {
                    *self.state.write().await = ForwardState::Connected;
                    self.metrics.record_connection_success();
                    self.metrics.set_connection_status(true);
                    info!("Port-forward established for {}", self.config.name);

                    // Monitor the connection
                    tokio::select! {
                        _ = shutdown_rx.recv() => {
                            info!("Received shutdown signal for {}", self.config.name);
                            break;
                        }
                        _ = self.monitor_connection(&client) => {
                            warn!("Connection lost for {}, attempting to reconnect", self.config.name);
                            *self.state.write().await = ForwardState::Disconnected;
                        }
                    }
                }
                Err(e) => {
                    warn!(
                        "Failed to establish port-forward for {}: {}",
                        self.config.name, e
                    );
                    self.metrics.record_connection_failure();
                    self.metrics.set_connection_status(false);
                    retry_count += 1;
                    tokio::time::sleep(self.config.options.retry_interval).await;
                    continue;
                }
            }
        }

        Ok(())
    }

    async fn monitor_connection(&self, client: &Client) -> Result<()> {
        let health_check = HealthCheck::new();
        let mut interval = tokio::time::interval(self.config.options.health_check_interval);

        loop {
            interval.tick().await;

            // Check TCP connection
            if !health_check.check_connection(self.config.ports.local).await {
                return Err(PortForwardError::ConnectionError(
                    "Connection health check failed".to_string(),
                ));
            }

            // Check pod status
            if let Ok(pod) = self.get_pod(client).await {
                if let Some(status) = &pod.status {
                    if let Some(phase) = &status.phase {
                        if phase != "Running" {
                            return Err(PortForwardError::ConnectionError(
                                "Pod is no longer running".to_string(),
                            ));
                        }
                    }
                }
            } else {
                return Err(PortForwardError::ConnectionError(
                    "Pod not found".to_string(),
                ));
            }
        }
    }

    async fn establish_forward(&self, client: &Client) -> Result<()> {
        self.metrics.record_connection_attempt();
        // Get pod for the service
        let pod = self.get_pod(client).await?;
        // Clone the name to avoid lifetime issues
        let pod_name = pod.metadata.name.clone().ok_or_else(|| {
            self.metrics.record_connection_failure();
            PortForwardError::ConnectionError("Pod name not found".to_string())
        })?;

        // Create Api instance for the namespace
        let pods: Api<Pod> = Api::namespaced(client.clone(), &self.service_info.namespace);

        // Create TCP listener for the local port
        debug!(
            "Creating TCP listener for the local port: {}",
            self.config.ports.local
        );
        let addr = SocketAddr::from(([127, 0, 0, 1], self.config.ports.local));
        let listener = TcpListener::bind(addr).await.map_err(|e| {
            self.metrics.record_connection_failure();
            match e.kind() {
                std::io::ErrorKind::AddrInUse => PortForwardError::ConnectionError(format!(
                    "Port {} is already in use. Please choose a different local port",
                    self.config.ports.local
                )),
                _ => PortForwardError::ConnectionError(format!("Failed to bind to port: {}", e)),
            }
        })?;

        // Set TCP keepalive
        // let tcp = TcpStream::connect(&addr).await?;
        let ka = TcpKeepalive::new().with_time(std::time::Duration::from_secs(30));
        let sf = SockRef::from(&listener);
        let _ = sf.set_tcp_keepalive(&ka);

        // Set state to connected
        *self.state.write().await = ForwardState::Connected;
        self.metrics.record_connection_success();
        self.metrics.set_connection_status(true);

        // Clone values needed for the async task
        let state = self.state.clone();
        let name = self.config.name.clone();
        let remote_port = self.config.ports.remote;
        let mut shutdown = self.shutdown.subscribe();
        let metrics = self.metrics.clone(); // Clone metrics for the task

        // Spawn the main forwarding task
        tokio::spawn(async move {
            let mut listener_stream = TcpListenerStream::new(listener);
            let name = name.as_str(); // Use as_str() to get a &str we can copy

            loop {
                tokio::select! {
                    // Handle new connections
                    Ok(Some(client_conn)) = listener_stream.try_next() => {
                        if let Ok(peer_addr) = client_conn.peer_addr() {
                            info!(%peer_addr, "New connection for {}", name);
                            metrics.record_connection_attempt();
                        }
                        let pods = pods.clone();
                        let pod_name = pod_name.clone();
                        let metrics = metrics.clone(); // Clone metrics for the connection task

                        tokio::spawn(async move {
                            if let Err(e) = Self::forward_connection(&pods, pod_name, remote_port, client_conn).await {
                                error!("Failed to forward connection: {}", e);
                                metrics.record_connection_failure();
                            } else {
                                metrics.record_connection_success();
                            }
                        });
                    }

                    // Handle shutdown signal
                    _ = shutdown.recv() => {
                        info!("Received shutdown signal for {}", name);
                        *state.write().await = ForwardState::Disconnected;
                        metrics.set_connection_status(false);
                        break;
                    }

                    else => {
                        error!("Port forward {} listener closed", name);
                        *state.write().await = ForwardState::Failed("Listener closed unexpectedly".to_string());
                        metrics.set_connection_status(false);
                        metrics.record_connection_failure();
                        break;
                    }
                }
            }
        });

        Ok(())
    }

    async fn forward_connection(
        pods: &Api<Pod>,
        pod_name: String,
        port: u16,
        mut client_conn: impl AsyncRead + AsyncWrite + Unpin,
    ) -> anyhow::Result<()> {
        debug!("Starting port forward for port {}", port);

        // Create port forward
        let mut pf = pods
            .portforward(&pod_name, &[port])
            .await
            .map_err(|e| anyhow::anyhow!("Failed to create portforward: {}", e))?;

        // Get the stream for our port
        let mut upstream_conn = pf
            .take_stream(port) // Use port instead of 0
            .ok_or_else(|| {
                anyhow::anyhow!("Failed to get port forward stream for port {}", port)
            })?;

        debug!("Port forward stream established for port {}", port);

        // Copy data bidirectionally with timeout
        match tokio::time::timeout(
            std::time::Duration::from_secs(30), // 30 second timeout
            tokio::io::copy_bidirectional(&mut client_conn, &mut upstream_conn),
        )
        .await
        {
            Ok(Ok(_)) => {
                debug!("Connection closed normally for port {}", port);
            }
            Ok(Err(e)) => {
                warn!("Error during data transfer for port {}: {}", port, e);
                return Err(anyhow::anyhow!("Data transfer error: {}", e));
            }
            Err(_) => {
                warn!("Connection timeout for port {}", port);
                return Err(anyhow::anyhow!("Connection timeout"));
            }
        }

        // Clean up
        drop(upstream_conn);

        // Wait for the port forwarder to finish
        if let Err(e) = pf.join().await {
            warn!("Port forwarder join error: {}", e);
        }

        Ok(())
    }

    async fn get_pod(&self, client: &Client) -> Result<Pod> {
        let pods: Api<Pod> = Api::namespaced(client.clone(), &self.service_info.namespace);

        // Get all pods in the namespace
        let pod_list = pods
            .list(&kube::api::ListParams::default())
            .await
            .map_err(|e| PortForwardError::KubeError(e))?;

        for pod in pod_list.items {
            if self
                .clone()
                .matches_pod_selector(&pod, &self.config.pod_selector)
            {
                if let Some(status) = &pod.status {
                    if let Some(phase) = &status.phase {
                        if phase == "Running" {
                            return Ok(pod);
                        }
                    }
                }
            }
        }

        Err(PortForwardError::ConnectionError(format!(
            "No ready pods found matching selector for service {}",
            self.service_info.name
        )))
    }

    pub fn matches_pod_selector(self, pod: &Pod, selector: &PodSelector) -> bool {
        // If no selector is specified, fall back to checking if service name is in any label
        if selector.label.is_none() && selector.annotation.is_none() {
            return pod.metadata.labels.as_ref().map_or(false, |labels| {
                labels.values().any(|v| v == &self.service_info.name)
            });
        }

        // Check label if specified
        if let Some(label_selector) = &selector.label {
            let (key, value) = self.clone().parse_selector(label_selector);
            if !pod.metadata.labels.as_ref().map_or(false, |labels| {
                labels.get(key).map_or(false, |v| v == value)
            }) {
                return false;
            }
        }

        // Check annotation if specified
        if let Some(annotation_selector) = &selector.annotation {
            let (key, value) = self.clone().parse_selector(annotation_selector);
            if !pod
                .metadata
                .annotations
                .as_ref()
                .map_or(false, |annotations| {
                    annotations.get(key).map_or(false, |v| v == value)
                })
            {
                return false;
            }
        }

        true
    }

    pub fn parse_selector(self, selector: &str) -> (&str, &str) {
        let parts: Vec<&str> = selector.split('=').collect();
        match parts.as_slice() {
            [key, value] => (*key, *value),
            _ => ("", ""), // Return empty strings if format is invalid
        }
    }
}

// Manager to handle multiple port-forwards
pub struct PortForwardManager {
    forwards: Arc<RwLock<Vec<Arc<PortForward>>>>,
    client: Client,
}

impl PortForwardManager {
    pub fn new(client: Client) -> Self {
        Self {
            forwards: Arc::new(RwLock::new(Vec::new())),
            client,
        }
    }

    pub async fn add_forward(
        &self,
        config: ForwardConfig,
        service_info: ServiceInfo,
    ) -> Result<()> {
        let forward = Arc::new(PortForward::new(config, service_info));
        self.forwards.write().await.push(forward.clone());

        // Start the port-forward in a separate task
        let client = self.client.clone();
        tokio::spawn(async move {
            if let Err(e) = forward.start(client).await {
                error!("Port-forward failed: {}", e);
            }
        });

        Ok(())
    }

    pub async fn stop_all(&self) {
        for forward in self.forwards.read().await.iter() {
            // forward.stop().await;
            forward.shutdown.send(()).unwrap();
        }
    }
}
```

<br />

Como podés ver, hay mucha tela para cortar, pero para simplificar las cosas:

- Itera sobre la configuración.
- Encuentra los pods que coinciden con el selector.
- Intenta establecer una conexión.
- Mantiene la conexión activa y se reconecta automáticamente si falla por cualquier motivo.
- Al cerrar o interrumpir la conexión, envía una señal de apagado.

Probablemente haga un video pronto para explicarlo con un poco más de detalle y mostrar el uso básico, ¡probalo y contame cómo te va! ¡Hasta la próxima!
