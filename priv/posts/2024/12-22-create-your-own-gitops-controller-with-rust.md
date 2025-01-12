%{
  title: "Create your own GitOps controller with Rust",
  author: "Gabriel Garrido",
  description: "In this article we will see how to write an MVP/Basic gitops controller to help us automate our
  infrastructure deployments...",
  tags: ~w(rust kubernetes argocd kind linux operator cicd slack),
  published: true,
  image: "gitops-operator.webp",
  sponsored: false,
  video: "",
  lang: "en"
}
---

![gitops-operator](/images/gitops-operator.webp){:class="mx-auto"}

##### **Introduction**
In this article we will see how to use [Kube](https://github.com/kube-rs/kube) and [Kind](https://github.com/kubernetes-sigs/kind) 
to create a local test cluster and a controller using [git2](https://github.com/rust-lang/git2-rs/) (libgit2), then deploy that 
controller in the cluster and test it, the repository with the files can be found [here](https://github.com/kainlite/gitops-operator), 
and also the [manifests](https://github.com/kainlite/gitops-operator-manifests).
<br />

Video coming soon!

###### **High level overview**
The controller simply automates updating our Kubernetes manifest (specifically a deployment manifest) based in some
annotations.

- Fetch app and manifest repos.
- Update the manifest repo with the latest SHA from the App repo
- Push the changes
- Let ArgoCD handle applying the change.

<br />

As you might imagine there are a lot of moving parts here, and different options, this is the "Pull" approach to gitops,
if you want to learn more about that you can go [here](https://gitops.tech).

<br />

On another topic you might be wondering what problem are we trying to solve here? Usually when you are making changes to
your application you need to also have a process to update your manifests so the newest version is released, depending
on the approach that you or your team prefers it can be push or pull, in this case we will explore what it means for it
to be a pull method and also how to run it in Kubernetes as a controller (since it will be watching for annotations in
your deployments), in this particular case it will be overseeing its own app and manifests kind of Inception.

<br />

##### **Prerequisites**
* [kube-rs](https://github.com/kube-rs/kube)
* [git2](https://github.com/rust-lang/git2-rs/)
* [kustomize](https://github.com/kubernetes-sigs/kustomize)
* [Rust](https://www.rust-lang.org)
* [Kind](https://github.com/kubernetes-sigs/kind)
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)

<br />

We need a Kubernetes cluster up and running for that I'm using Kind here, just issue to get going:
```elixir 
kind create cluster
```

<br />

Then install ArgoCD to deploy our controller (not the recommended approach):
```elixir
helm repo add argo https://argoproj.github.io/argo-helm
helm install -n argocd argocd argo/argo-cd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

<br />

About now you should be able to port-forward and login to your ArgoCD instance:
```elixir
kubectl port-forward service/argocd-server 8080:443
```

<br />

Then you should add your key, that would look something like this (hit "Connect repo" and fill the information):
![connect-repo](/images/gitops-operator-1.png){:class="mx-auto"}

<br />

We can create the ArgoCD application and enable Self-healing like so:
![argocd](/images/gitops-operator-4.png){:class="mx-auto"}

Everything should look something like this:
![argocd-2](/images/gitops-operator-5.png){:class="mx-auto"}

<br />

You can generate an RSA key like this:
```elixir
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_demo 
```

<br />

Then in the GitHub repository we need to allow that key (using the public key) to read and write to the manifests
repository (Settings->Deploy Key->Fill the contents and check the box to give it write permissions):
![github-rw](/images/gitops-operator-2.png){:class="mx-auto"}

<br />

That was a lot of preparation, do note that we already have a CI configuration in place to build the images and push 
them to [dockerhub](https://hub.docker.com/r/kainlite/gitops-operator/tags), you might be thinking why not just stick 
to the push method and modify the deployment in place and just push the change to the cluster, well there are several 
differences but some of them are in most cases the CI pipeline doesn't need access to the cluster (practical and 
security concern, yes you can run the CI pipeline from/in the cluster using Tekton for example), the other consideration 
is the flexibility that you can gain to manage your app lifecycle by just having a controller with your logic embedded 
and setting your own configuration to deploy it as it best suit your needs, think of it as a building block of your
platform.

<br />

##### **The code**

While this is an MVP so far or a toy project, it does the minimum that it needs to do, but it might be fragile and many
cases were not contemplated just for the sake of simplicity and because that's usually what you need for your first
software version of anything, it needs to work, then it can be refactored, improved, get more features, tests (or better
tests), etc, etc, etc.

By the way, I'm just learning Rust so don't expect a production grade code or the most efficient code, but somewhat
something that works tm! 

<br />

###### Dockerfile

The Dockerfile is pretty straight-forward, basically we build a production release and copy that and the known_hosts
file to the home path of the user that will be running the image (this is necessary since we are using SSH
authentication).
```elixir
FROM clux/muslrust:stable AS builder

COPY Cargo.* .
COPY *.rs .

RUN --mount=type=cache,target=/volume/target \
    --mount=type=cache,target=/root/.cargo/registry \
    cargo build --release --bin gitops-operator && \
    mv /volume/target/x86_64-unknown-linux-musl/release/gitops-operator .

FROM cgr.dev/chainguard/static

COPY --from=builder --chown=nonroot:nonroot /volume/gitops-operator /app/
COPY files/known_hosts /home/nonroot/.ssh/known_hosts

EXPOSE 8080

ENTRYPOINT ["/app/gitops-operator"]
```

<br />

Next up we can check the known_hosts file, these signatures were taken from [here](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints), but you can also do it with
`ssh-keygen`.

```elixir
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
```

<br />

###### The actual code
This file is the `main.rs` file cargo will look for (as I configured it to), to build our app and in short it will setup an
HTTP Web server on port 8000 with two routes (/health and /reconcile), instead of setting up a proper reconcile method
(usually a recursive function or using a callback) I decided to use the Readiness Probe to trigger a call to the
endpoint /reconcile and making it run every two minutes (we will check that when we get to the manifests). 

```elixir
pub mod files;
pub mod git;

use axum::extract::State;
use axum::{routing, Json, Router};
use futures::{future, StreamExt};
use k8s_openapi::api::apps::v1::Deployment;
use kube::runtime::{reflector, watcher, WatchStreamExt};
use kube::{Api, Client, ResourceExt};
use std::collections::BTreeMap;
use tracing::{debug, warn};

use files::patch_deployment_and_commit;
use git::clone_repo;

#[derive(serde::Serialize, Clone)]
struct Config {
    enabled: bool,
    namespace: String,
    app_repository: String,
    manifest_repository: String,
    image_name: String,
    deployment_path: String,
}

#[derive(serde::Serialize, Clone)]
struct Entry {
    container: String,
    name: String,
    namespace: String,
    annotations: BTreeMap<String, String>,
    version: String,
    config: Config,
}
type Cache = reflector::Store<Deployment>;

fn deployment_to_entry(d: &Deployment) -> Option<Entry> {
    let name = d.name_any();
    let namespace = d.namespace()?;
    let annotations = d.metadata.annotations.as_ref()?;
    let tpl = d.spec.as_ref()?.template.spec.as_ref()?;
    let img = tpl.containers.get(0)?.image.as_ref()?;
    let splits = img.splitn(2, ':').collect::<Vec<_>>();
    let (container, version) = match *splits.as_slice() {
        [c, v] => (c.to_owned(), v.to_owned()),
        [c] => (c.to_owned(), "latest".to_owned()),
        _ => return None,
    };

    let enabled = annotations.get("gitops.operator.enabled")?.trim().parse().unwrap();
    let app_repository = annotations.get("gitops.operator.app_repository")?.to_string();
    let manifest_repository = annotations.get("gitops.operator.manifest_repository")?.to_string();
    let image_name = annotations.get("gitops.operator.image_name")?.to_string();
    let deployment_path = annotations.get("gitops.operator.deployment_path")?.to_string();

    println!("Processing: {}/{}", &namespace, &name);

    Some(Entry {
        name,
        namespace: namespace.clone(),
        annotations: annotations.clone(),
        container,
        version,
        config: Config {
            enabled,
            namespace: namespace.clone(),
            app_repository,
            manifest_repository,
            image_name,
            deployment_path,
        },
    })
}

// - GET /reconcile
async fn reconcile(State(store): State<Cache>) -> Json<Vec<Entry>> {
    let data: Vec<_> = store.state().iter().filter_map(|d| deployment_to_entry(d)).collect();

    for entry in &data {
        if !entry.config.enabled {
            println!("continue");
            continue;
        }

        // Perform reconciliation
        let app_local_path = format!("/tmp/app-{}", &entry.name);
        let manifest_local_path = format!("/tmp/manifest-{}", &entry.name);

        clone_repo(&entry.config.app_repository, &app_local_path);
        clone_repo(&entry.config.manifest_repository, &manifest_local_path);
        let _ = patch_deployment_and_commit(
            format!("/tmp/app-{}", &entry.name).as_ref(),
            format!("/tmp/manifest-{}", &entry.name).as_ref(),
            &entry.config.deployment_path,
            &entry.config.image_name,
        );
    }

    Json(data)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Starting gitops-operator");

    tracing_subscriber::fmt::init();
    let client = Client::try_default().await?;
    let api: Api<Deployment> = Api::all(client);

    let (reader, writer) = reflector::store();
    let watch = reflector(writer, watcher(api, Default::default()))
        .default_backoff()
        .touched_objects()
        .for_each(|r| {
            future::ready(match r {
                Ok(o) => debug!("Saw {} in {}", o.name_any(), o.namespace().unwrap()),
                Err(e) => warn!("watcher error: {e}"),
            })
        });
    tokio::spawn(watch); // poll forever

    let app = Router::new()
        .route("/reconcile", routing::get(reconcile))
        .with_state(reader) // routes can read from the reflector store
        .layer(tower_http::trace::TraceLayer::new_for_http())
        // NB: routes added after TraceLayer are not traced
        .route("/health", routing::get(|| async { "up" }));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000").await?;
    axum::serve(listener, app.into_make_service()).await?;

    Ok(())
}
```

<br />

Then in this file `files.rs` we have some functions that deal with files and actually updating the deployment file.
```elixir
use crate::git::stage_and_push_changes;
use anyhow::Context;
use anyhow::Error;
use git2::Error as GitError;
use git2::Repository;
use k8s_openapi::api::apps::v1::Deployment;
use serde_yaml;
use std::fs;

fn patch_image_tag(file_path: String, image_name: String, new_sha: String) -> Result<(), Error> {
    println!("Patching image tag in deployment file: {}", file_path);
    let yaml_content = fs::read_to_string(&file_path).context("Failed to read deployment YAML file")?;

    println!("before: {:?}", yaml_content);

    // Parse the YAML into a Deployment resource
    let mut deployment: Deployment =
        serde_yaml::from_str(&yaml_content).context("Failed to parse YAML into Kubernetes Deployment")?;

    // Modify deployment specifics
    if let Some(spec) = deployment.spec.as_mut() {
        if let Some(template) = spec.template.spec.as_mut() {
            for container in &mut template.containers {
                if container.image.as_ref().unwrap().contains(&new_sha) {
                    println!("Image tag already updated... Aborting mission!");
                    return Err(anyhow::anyhow!("Image tag {} is already up to date", new_sha));
                }
                if container.image.as_ref().unwrap().contains(&image_name) {
                    container.image = Some(format!("{}:{}", &image_name, &new_sha));
                }
            }
        }
    }

    // Optional: Write modified deployment back to YAML file
    let updated_yaml =
        serde_yaml::to_string(&deployment).context("Failed to serialize updated deployment")?;

    println!("updated yaml: {:?}", updated_yaml);

    fs::write(file_path, updated_yaml).context("Failed to write updated YAML back to file")?;

    Ok(())
}

pub fn patch_deployment_and_commit(
    app_repo_path: &str,
    manifest_repo_path: &str,
    file_name: &str,
    image_name: &str,
) -> Result<(), GitError> {
    println!("Patching deployment and committing changes");
    let commit_message = "chore(refs): gitops-operator updating image tags";
    let app_repo = Repository::open(&app_repo_path)?;
    let manifest_repo = Repository::open(&manifest_repo_path)?;

    // Find the latest remote head
    // While this worked, it failed in some scenarios that were unimplemented
    // let new_sha = app_repo.head()?.peel_to_commit().unwrap().parent(1)?.id().to_string();

    let fetch_head = app_repo.find_reference("FETCH_HEAD")?;
    let remote = app_repo.reference_to_annotated_commit(&fetch_head)?;
    let remote_commit = app_repo.find_commit(remote.id())?;

    let new_sha = remote_commit.id().to_string();

    println!("New application SHA: {}", new_sha);

    // Perform changes
    let patch = patch_image_tag(
        format!("{}/{}", manifest_repo_path, file_name),
        image_name.to_string(),
        new_sha,
    );

    match patch {
        Ok(_) => println!("Image tag updated successfully"),
        Err(e) => {
            println!("We don't need to update image tag: {:?}", e);
            return Err(GitError::from_str(
                "Aborting update image tag, already updated...",
            ));
        }
    }

    // Stage and push changes
    let _ = stage_and_push_changes(&manifest_repo, commit_message)?;

    Ok(())
}
```

<br />

And last but not least `git.rs`, possibly the complex part in this project, git... This file has a few functions to deal with
cloning, fetching and merging remote changes, then to add our local changes, stage them and push them to the repository:
```elixir
use git2::{
    build::RepoBuilder, CertificateCheckStatus, Cred, Error as GitError, FetchOptions, RemoteCallbacks,
    Repository,
};
use std::env;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use git2::Signature;
use std::time::{SystemTime, UNIX_EPOCH};

fn create_signature<'a>() -> Result<Signature<'a>, GitError> {
    let name = "GitOps Operator";
    let email = "gitops-operator+kainlite@gmail.com";

    // Get current timestamp
    let time = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();

    // Create signature with current timestamp
    Signature::new(name, email, &git2::Time::new(time as i64, 0))
}

fn normal_merge(
    repo: &Repository,
    local: &git2::AnnotatedCommit,
    remote: &git2::AnnotatedCommit,
) -> Result<(), git2::Error> {
    let local_tree = repo.find_commit(local.id())?.tree()?;
    let remote_tree = repo.find_commit(remote.id())?.tree()?;
    let ancestor = repo.find_commit(repo.merge_base(local.id(), remote.id())?)?.tree()?;
    let mut idx = repo.merge_trees(&ancestor, &local_tree, &remote_tree, None)?;

    if idx.has_conflicts() {
        println!("Merge conflicts detected...");
        repo.checkout_index(Some(&mut idx), None)?;
        return Ok(());
    }
    let result_tree = repo.find_tree(idx.write_tree_to(repo)?)?;
    // now create the merge commit
    let msg = format!("Merge: {} into {}", remote.id(), local.id());
    let sig = repo.signature()?;
    let local_commit = repo.find_commit(local.id())?;
    let remote_commit = repo.find_commit(remote.id())?;
    // Do our merge commit and set current branch head to that commit.
    let _merge_commit = repo.commit(
        Some("HEAD"),
        &sig,
        &sig,
        &msg,
        &result_tree,
        &[&local_commit, &remote_commit],
    )?;
    // Set working tree to match head.
    repo.checkout_head(None)?;
    Ok(())
}

pub fn clone_or_update_repo(url: &str, repo_path: PathBuf) -> Result<(), GitError> {
    println!("Cloning or updating repository from: {}", &url);

    // Setup SSH key authentication
    let mut callbacks = RemoteCallbacks::new();
    callbacks.credentials(|_url, username_from_url, _allowed_types| {
        // Dynamically find SSH key path
        let ssh_key_path = format!(
            "{}/.ssh/id_rsa_demo",
            env::var("HOME").expect("HOME environment variable not set")
        );

        println!("Using SSH key: {}", &ssh_key_path);
        println!("{}", Path::new(&ssh_key_path).exists());

        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            None,
            Path::new(&ssh_key_path),
            None,
        )
    });

    // TODO: implement certificate check, potentially insecure
    callbacks.certificate_check(|_cert, _host| {
        // Return true to indicate we accept the host
        Ok(CertificateCheckStatus::CertificateOk)
    });

    // Prepare fetch options
    let mut fetch_options = FetchOptions::new();
    fetch_options.remote_callbacks(callbacks);
    fetch_options.download_tags(git2::AutotagOption::All);

    // Check if repository already exists
    if repo_path.exists() {
        println!("Repository already exists, pulling...");

        // Open existing repository
        let repo = Repository::open(&repo_path)?;

        // Fetch changes
        fetch_existing_repo(&repo, &mut fetch_options)?;

        // Pull changes (merge)
        pull_repo(&repo, &fetch_options)?;
    } else {
        println!("Repository does not exist, cloning...");

        // Clone new repository
        clone_new_repo(url, &repo_path, fetch_options)?;
    }

    Ok(())
}

/// Fetch changes for an existing repository
fn fetch_existing_repo(repo: &Repository, fetch_options: &mut FetchOptions) -> Result<(), GitError> {
    println!("Fetching changes for existing repository");

    // Find the origin remote
    let mut remote = repo.find_remote("origin")?;

    // Fetch all branches
    let refs = &["refs/heads/master:refs/remotes/origin/master"];

    remote.fetch(refs, Some(fetch_options), None)?;

    Ok(())
}

/// Clone a new repository
fn clone_new_repo(url: &str, local_path: &Path, fetch_options: FetchOptions) -> Result<Repository, GitError> {
    println!("Cloning repository from: {}", &url);
    // Prepare repository builder
    let mut repo_builder = RepoBuilder::new();
    repo_builder.fetch_options(fetch_options);

    // Clone the repository
    repo_builder.clone(url, local_path)
}

/// Pull (merge) changes into the current branch
fn pull_repo(repo: &Repository, _fetch_options: &FetchOptions) -> Result<(), GitError> {
    println!("Pulling changes into the current branch");

    // Find remote branch
    let remote_branch_name = format!("remotes/origin/master");

    println!("Merging changes from remote branch: {}", &remote_branch_name);

    // Annotated commit for merge
    let fetch_head = repo.find_reference("FETCH_HEAD")?;
    let fetch_commit = repo.reference_to_annotated_commit(&fetch_head)?;

    // Perform merge analysis
    let (merge_analysis, _) = repo.merge_analysis(&[&fetch_commit])?;

    println!("Merge analysis result: {:?}", merge_analysis);

    if merge_analysis.is_fast_forward() {
        let refname = format!("refs/remotes/origin/master");
        let mut reference = repo.find_reference(&refname)?;
        reference.set_target(fetch_commit.id(), "Fast-Forward")?;
        repo.set_head(&refname)?;
        let _ = repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()));

        Ok(())
    } else if merge_analysis.is_normal() {
        let head_commit = repo.reference_to_annotated_commit(&repo.head()?)?;
        normal_merge(&repo, &head_commit, &fetch_commit)?;

        Ok(())
    } else if merge_analysis.is_up_to_date() {
        println!("Repository is up to date");
        Ok(())
    } else {
        Err(GitError::from_str("Unsupported merge analysis case"))
    }
}

pub fn stage_and_push_changes(repo: &Repository, commit_message: &str) -> Result<(), GitError> {
    println!("Staging and pushing changes");

    // Stage all changes (equivalent to git add .)
    let mut index = repo.index()?;
    index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
    index.write()?;

    // Create a tree from the index
    let tree_id = index.write_tree()?;
    let tree = repo.find_tree(tree_id)?;

    // Get the current head commit
    let parent_commit = repo.head()?.peel_to_commit()?;

    println!("Parent commit: {}", parent_commit.id());

    // Prepare signature (author and committer)
    // let signature = repo.signature()?;
    let signature = create_signature()?;

    println!("Author: {}", signature.name().unwrap());

    // Create the commit
    let commit_oid = repo.commit(
        Some("HEAD"),      // Update HEAD reference
        &signature,        // Author
        &signature,        // Committer
        commit_message,    // Commit message
        &tree,             // Tree to commit
        &[&parent_commit], // Parent commit
    )?;

    println!("New commit: {}", commit_oid);

    // Prepare push credentials
    let mut callbacks = RemoteCallbacks::new();
    callbacks.credentials(|_url, username_from_url, _allowed_types| {
        // Dynamically find SSH key path
        let ssh_key_path = format!(
            "{}/.ssh/id_rsa_demo",
            env::var("HOME").expect("HOME environment variable not set")
        );

        println!("Using SSH key: {}", &ssh_key_path);
        println!("{}", Path::new(&ssh_key_path).exists());

        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            None,
            Path::new(&ssh_key_path),
            None,
        )
    });

    // TODO: implement certificate check, potentially insecure
    callbacks.certificate_check(|_cert, _host| {
        // Return true to indicate we accept the host
        Ok(CertificateCheckStatus::CertificateOk)
    });

    // Print out our transfer progress.
    callbacks.transfer_progress(|stats| {
        if stats.received_objects() == stats.total_objects() {
            print!(
                "Resolving deltas {}/{}\r",
                stats.indexed_deltas(),
                stats.total_deltas()
            );
        } else if stats.total_objects() > 0 {
            print!(
                "Received {}/{} objects ({}) in {} bytes\r",
                stats.received_objects(),
                stats.total_objects(),
                stats.indexed_objects(),
                stats.received_bytes()
            );
        }
        io::stdout().flush().unwrap();
        true
    });

    // Prepare push options
    let mut push_options = git2::PushOptions::new();
    push_options.remote_callbacks(callbacks);

    // Find the origin remote
    let mut remote = repo.find_remote("origin")?;

    println!("Pushing to remote: {}", remote.url().unwrap());

    // Determine the current branch name
    let branch_name = repo.head()?;
    let refspec = format!("refs/heads/{}", branch_name.shorthand().unwrap_or("master"));

    println!("Pushing to remote branch: {}", &refspec);

    // Push changes
    remote.push(&[&refspec], Some(&mut push_options))?;

    Ok(())
}

// Example usage in the context of the original code
pub fn clone_repo(url: &str, local_path: &str) {
    let repo_path = PathBuf::from(local_path);

    match clone_or_update_repo(url, repo_path) {
        Ok(_) => println!("Repository successfully updated"),
        Err(e) => eprintln!("Error updating repository: {}", e),
    }
}
```

<br />

Some things that I need to improve in all that code is:
- Error handling
- Standardize all the functions so they behave in a similar fashion
- Standardize logging and remove all the debugging information
- Refactor the functions to be more specific and handle a single things

And a few more things, but remember this is an MVP all it matters so far is that it needs to work.

<br />

###### The pipeline
For the sake of completeness lets add the pipeline, as you can see we have two jobs and one to lint and check that the
code is formatted and the other one to build and push the image to dockerhub, the most interesting bit is probably the
cache dance.

```elixir
name: ci

on:
  pull_request:
  push:
    branches:
      - master
    tags:
      - '*'

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false
      matrix:
        platform:
          - linux/amd64
          #- linux/arm64
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      # Build and push with docker buildx
      - name: Setup docker buildx
        uses: docker/setup-buildx-action@v3
        with:
          config: .github/buildkitd.toml

      - name: Configure tags based on git tags + latest
        uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ github.repository }}
          tags: |
            type=sha,prefix=,suffix=,format=short
            type=sha,prefix=,suffix=,format=long
            type=ref,event=branch
            type=pep440,pattern={{version}}
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=pr

      - name: Rust Build Cache for Docker
        uses: actions/cache@v4
        with:
          path: rust-build-cache
          key: ${{ runner.os }}-build-cache-${{ hashFiles('**/Cargo.toml') }}

      - name: inject rust-build-cache into docker
        uses: overmindtech/buildkit-cache-dance/inject@main
        with:
          cache-source: rust-build-cache

      - name: Docker login
        uses: docker/login-action@v3
        #if: github.event_name != 'pull_request'
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Docker build and push with cache
        uses: docker/build-push-action@v6
        with:
          context: .
          # when not using buildkit cache
          #cache-from: type=registry,ref=ghcr.io/${{ github.repository }}:buildcache
          #cache-to: type=registry,ref=ghcr.io/${{ github.repository }}:buildcache
          # when using buildkit-cache-dance
          cache-from: type=gha
          cache-to: type=gha,mode=max
          #push: ${{ github.ref == 'refs/heads/main' }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          platforms: ${{ matrix.platform }}

      - name: extract rust-build-cache from docker
        uses: overmindtech/buildkit-cache-dance/extract@main
        with:
          cache-source: rust-build-cache

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: stable
          components: rustfmt,clippy
      - run: cargo fmt -- --check

      - uses: giraffate/clippy-action@v1
        with:
          reporter: 'github-pr-review'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

<br />

So whenever we make a change to the application we will automatically see a commit from the controller like this:
![commits](/images/gitops-operator-3.png){:class="mx-auto"}

<br />

###### Manifests
One of the things that we need to do for this to work is to store our SSH key as a secret so we can mount it (we could
have read the secret from the controller using kube-rs, but this was simpler), as you will notice we have a set of
annotations to configure the controller to act on our deployment, and then we mount the ssh key that we generated before
so it can actually fetch and write to the manifests repository.

Also you will notice that we are calling the `/reconcile` path every two minutes from the Readiness Probe, as Kubernetes
will keep calling that endpoint every two minutes to it based in our configuration and since we are not expecting any
external traffic this should do, it should be also relatively safe to run it concurrently so this is good enough for
now.
```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    gitops.operator.app_repository: git@github.com:kainlite/gitops-operator.git
    gitops.operator.deployment_path: app/00-deployment.yaml
    gitops.operator.enabled: 'true'
    gitops.operator.image_name: kainlite/gitops-operator
    gitops.operator.manifest_repository: git@github.com:kainlite/gitops-operator-manifests.git
    gitops.operator.namespace: default
  labels:
    app: gitops-operator
  name: gitops-operator
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitops-operator
  template:
    metadata:
      labels:
        app: gitops-operator
    spec:
      containers:
      - image: kainlite/gitops-operator:ab76bb8f5064a6df5ed54ae68b0f0c6eaa6dcbb6
        imagePullPolicy: Always
        livenessProbe:
          failureThreshold: 5
          httpGet:
            path: /health
            port: http
          periodSeconds: 15
        name: gitops-operator
        ports:
        - containerPort: 8000
          name: http
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /reconcile
            port: http
          initialDelaySeconds: 60
          periodSeconds: 120
          timeoutSeconds: 60
        resources:
          limits:
            cpu: 1000m
            memory: 1024Mi
          requests:
            cpu: 500m
            memory: 100Mi
        volumeMounts:
        - mountPath: /home/nonroot/.ssh/id_rsa_demo
          name: my-ssh-key
          readOnly: true
          subPath: ssh-privatekey
      serviceAccountName: gitops-operator
      volumes:
      - name: my-ssh-key
        secret:
          items:
          - key: ssh-privatekey
            path: ssh-privatekey
          secretName: my-ssh-key
```

<br />

**BONUS!** If you don't recall how to create a key and store it as a secret it is really simple, if you need help or want a
quick reference of the most used ways to create and use secrets in Kubernetes check my [article about it](https://redbeard.team/en/blog/mounting-secrets-in-kubernetes):

<br />

```elixir
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_demo
kubectl create secret generic my-ssh-key --from-file=ssh-privatekey=~/.ssh/id_rsa_demo
```
And that's it! I will be adding a video version soon, follow me on LinkedIn to stay up to date! See you next time! 🚀

<br />

##### **Closing notes**
This was heavily inspired and based in the kube-rs: `version-rs` examples as well as many of the examples in the `git2`
repository, if you liked it follow me and share for more!

---lang---
%{
  title: "Crea tu propio controllador GitOps con Rust",
  author: "Gabriel Garrido",
  description: "En este articulo vamos a ver como escribir un controllador gitops basico o minimo para ayudarnos a
  automatizar los despliegues de nuestra infrastructura...",
  tags: ~w(rust kubernetes argocd kind linux operator cicd slack),
  published: true,
  image: "gitops-operator.webp",
  sponsored: false,
  video: "",
  lang: "es"
}
---

![gitops-operator](/images/gitops-operator.webp){:class="mx-auto"}

##### **Introducción**  
En este artículo veremos cómo utilizar [Kube](https://github.com/kube-rs/kube) y [Kind](https://github.com/kubernetes-sigs/kind) para crear un clúster de prueba local y un controlador usando [git2](https://github.com/rust-lang/git2-rs/) (libgit2). Luego, desplegaremos ese  controlador en el clúster y lo probaremos. El repositorio con los archivos se puede encontrar [aquí](https://github.com/kainlite/gitops-operator), y también los [manifiestos](https://github.com/kainlite/gitops-operator-manifests).  

<br />  

###### **Resumen general**  
El controlador simplemente automatiza la actualización de nuestro manifiesto de Kubernetes (específicamente un manifiesto de despliegue) basado en algunas anotaciones.  

- Obtener los repositorios de la aplicación y el manifiesto.  
- Actualizar el repositorio de manifiestos con el último SHA del repositorio de la aplicación.  
- Empujar los cambios.  
- Dejar que ArgoCD se encargue de aplicar el cambio.  

<br />  

Como puedes imaginar, hay muchas piezas en movimiento aquí y diferentes opciones. Este es el enfoque **Pull** de GitOps. Si deseas aprender más sobre este enfoque, puedes ir [aquí](https://gitops.tech).  

<br />

Por otro lado, podrías preguntarte: ¿qué problema estamos intentando resolver aquí? Generalmente, cuando realizas cambios en tu aplicación,  
también necesitas tener un proceso para actualizar tus manifiestos y así lanzar la última versión. Dependiendo del enfoque que tú o tu equipo prefieran,  
puede ser un método **push** o **pull**. En este caso, exploraremos lo que significa que sea el método pull y también cómo ejecutarlo en Kubernetes como un controlador, 
(ya que estará observando las anotaciones en tus despliegues). En este caso particular, el controlador supervisará su propia aplicación y manifiestos,  
algo así como una especie de **Inception**.  

<br />  

##### **Requisitos previos**  
* [kube-rs](https://github.com/kube-rs/kube)  
* [git2](https://github.com/rust-lang/git2-rs/)  
* [kustomize](https://github.com/kubernetes-sigs/kustomize)  
* [Rust](https://www.rust-lang.org)  
* [Kind](https://github.com/kubernetes-sigs/kind)  
* [ArgoCD](https://argo-cd.readthedocs.io/en/stable/)  

<br />  

Necesitamos un clúster de Kubernetes en funcionamiento. En este caso, usaremos **Kind**. Ejecuta el siguiente comando para iniciar:  
```elixir 
kind create cluster
```

<br />  

Luego, instala **ArgoCD** para desplegar nuestro controlador (no es el enfoque recomendado):  
```elixir
helm repo add argo https://argoproj.github.io/argo-helm
helm install -n argocd argocd argo/argo-cd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

<br />  

En este punto, deberías poder realizar un port-forward y acceder a tu instancia de **ArgoCD**:  
```elixir
kubectl port-forward service/argocd-server 8080:443
```

<br />

Luego, debes agregar tu clave. Se verá algo así (haz clic en **"Connect repo"** y completa la información):  
![connect-repo](/images/gitops-operator-1.png){:class="mx-auto"}  

<br />  

Podemos crear la aplicación de **ArgoCD** y habilitar la **autocuración** de la siguiente manera:  
![argocd](/images/gitops-operator-4.png){:class="mx-auto"}  

Todo debería verse algo así:  
![argocd-2](/images/gitops-operator-5.png){:class="mx-auto"}  

<br />  

Puedes generar una clave RSA de la siguiente manera:  
```elixir
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_demo 
```

<br />  

Luego, en el repositorio de **GitHub**, necesitamos permitir que esa clave (usando la clave pública) tenga permisos de lectura y escritura 
en el repositorio de manifiestos (**Settings → Deploy Key → Rellena el contenido y marca la casilla para otorgar permisos de escritura**): 
![github-rw](/images/gitops-operator-2.png){:class="mx-auto"} 

<br />  

Eso fue mucha preparación. Ten en cuenta que ya tenemos una configuración de **CI** en su lugar para construir las imágenes y enviarlas
a [DockerHub](https://hub.docker.com/r/kainlite/gitops-operator/tags). Tal vez te preguntes: **¿Por qué no simplemente quedarse con el método push 
y modificar el despliegue directamente en el clúster?** Bueno, hay varias diferencias, pero algunas de ellas son: en la mayoría de los casos, el pipeline de **CI** no necesita acceso al clúster 
(un aspecto práctico y de seguridad; sí, puedes ejecutar el pipeline de CI desde/en el clúster usando, por ejemplo, **Tekton**).
Otra consideración es la flexibilidad que puedes ganar para administrar el ciclo de vida de tu aplicación con solo tener un controlador 
con tu lógica embebida y configurar tu propio despliegue de la forma que mejor se adapte a tus necesidades. Piénsalo como un bloque 
de construcción de tu plataforma. 

<br />  

###### El código

Aunque esto es, por ahora, un **MVP** (Producto Mínimo Viable) o un proyecto experimental, hace lo mínimo necesario para cumplir su propósito. 
Sin embargo, podría ser frágil y no se contemplaron muchos casos por el bien de la simplicidad y porque, por lo general, eso es lo que necesitas 
en la primera versión de cualquier software: **que funcione**. Luego puede ser refactorizado, mejorado, añadir más características, 
pruebas (o mejores pruebas), etc., etc., etc. 

Por cierto, estoy aprendiendo **Rust**, así que no esperes un código listo para producción ni el código más eficiente, 
¡pero sí algo que funcione™! 

<br />  

###### Dockerfile

El Dockerfile es bastante sencillo. Básicamente, construimos una versión de producción, copiamos ese binario y el archivo **known_hosts** 
a la ruta home del usuario que ejecutará la imagen (esto es necesario ya que estamos utilizando autenticación SSH).
```elixir
FROM clux/muslrust:stable AS builder

COPY Cargo.* .
COPY *.rs .

RUN --mount=type=cache,target=/volume/target \
    --mount=type=cache,target=/root/.cargo/registry \
    cargo build --release --bin gitops-operator && \
    mv /volume/target/x86_64-unknown-linux-musl/release/gitops-operator .

FROM cgr.dev/chainguard/static

COPY --from=builder --chown=nonroot:nonroot /volume/gitops-operator /app/
COPY files/known_hosts /home/nonroot/.ssh/known_hosts

EXPOSE 8080

ENTRYPOINT ["/app/gitops-operator"]
```

<br />

A continuación, podemos revisar el archivo **known_hosts**. Estas firmas fueron tomadas de [aquí](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/githubs-ssh-key-fingerprints),  
pero también puedes hacerlo usando el comando `ssh-keygen`. 

```elixir
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
```

<br />  

###### El código principal

Este archivo es el `main.rs`, el cual **Cargo** buscará (ya que lo configuré de esa manera) para construir nuestra aplicación. 
En resumen, configurará un servidor **HTTP** en el puerto **8000** con dos rutas: `/health` y `/reconcile`. En lugar de configurar un método adecuado de reconciliación (que normalmente sería una función recursiva o utilizando un **callback**), 
decidí usar la **Readiness Probe** para desencadenar una llamada al endpoint `/reconcile` y hacer que se ejecute cada dos minutos 
(lo revisaremos cuando lleguemos a los **manifiestos**).

```elixir
pub mod files;
pub mod git;

use axum::extract::State;
use axum::{routing, Json, Router};
use futures::{future, StreamExt};
use k8s_openapi::api::apps::v1::Deployment;
use kube::runtime::{reflector, watcher, WatchStreamExt};
use kube::{Api, Client, ResourceExt};
use std::collections::BTreeMap;
use tracing::{debug, warn};

use files::patch_deployment_and_commit;
use git::clone_repo;

#[derive(serde::Serialize, Clone)]
struct Config {
    enabled: bool,
    namespace: String,
    app_repository: String,
    manifest_repository: String,
    image_name: String,
    deployment_path: String,
}

#[derive(serde::Serialize, Clone)]
struct Entry {
    container: String,
    name: String,
    namespace: String,
    annotations: BTreeMap<String, String>,
    version: String,
    config: Config,
}
type Cache = reflector::Store<Deployment>;

fn deployment_to_entry(d: &Deployment) -> Option<Entry> {
    let name = d.name_any();
    let namespace = d.namespace()?;
    let annotations = d.metadata.annotations.as_ref()?;
    let tpl = d.spec.as_ref()?.template.spec.as_ref()?;
    let img = tpl.containers.get(0)?.image.as_ref()?;
    let splits = img.splitn(2, ':').collect::<Vec<_>>();
    let (container, version) = match *splits.as_slice() {
        [c, v] => (c.to_owned(), v.to_owned()),
        [c] => (c.to_owned(), "latest".to_owned()),
        _ => return None,
    };

    let enabled = annotations.get("gitops.operator.enabled")?.trim().parse().unwrap();
    let app_repository = annotations.get("gitops.operator.app_repository")?.to_string();
    let manifest_repository = annotations.get("gitops.operator.manifest_repository")?.to_string();
    let image_name = annotations.get("gitops.operator.image_name")?.to_string();
    let deployment_path = annotations.get("gitops.operator.deployment_path")?.to_string();

    println!("Processing: {}/{}", &namespace, &name);

    Some(Entry {
        name,
        namespace: namespace.clone(),
        annotations: annotations.clone(),
        container,
        version,
        config: Config {
            enabled,
            namespace: namespace.clone(),
            app_repository,
            manifest_repository,
            image_name,
            deployment_path,
        },
    })
}

// - GET /reconcile
async fn reconcile(State(store): State<Cache>) -> Json<Vec<Entry>> {
    let data: Vec<_> = store.state().iter().filter_map(|d| deployment_to_entry(d)).collect();

    for entry in &data {
        if !entry.config.enabled {
            println!("continue");
            continue;
        }

        // Perform reconciliation
        let app_local_path = format!("/tmp/app-{}", &entry.name);
        let manifest_local_path = format!("/tmp/manifest-{}", &entry.name);

        clone_repo(&entry.config.app_repository, &app_local_path);
        clone_repo(&entry.config.manifest_repository, &manifest_local_path);
        let _ = patch_deployment_and_commit(
            format!("/tmp/app-{}", &entry.name).as_ref(),
            format!("/tmp/manifest-{}", &entry.name).as_ref(),
            &entry.config.deployment_path,
            &entry.config.image_name,
        );
    }

    Json(data)
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    println!("Starting gitops-operator");

    tracing_subscriber::fmt::init();
    let client = Client::try_default().await?;
    let api: Api<Deployment> = Api::all(client);

    let (reader, writer) = reflector::store();
    let watch = reflector(writer, watcher(api, Default::default()))
        .default_backoff()
        .touched_objects()
        .for_each(|r| {
            future::ready(match r {
                Ok(o) => debug!("Saw {} in {}", o.name_any(), o.namespace().unwrap()),
                Err(e) => warn!("watcher error: {e}"),
            })
        });
    tokio::spawn(watch); // poll forever

    let app = Router::new()
        .route("/reconcile", routing::get(reconcile))
        .with_state(reader) // routes can read from the reflector store
        .layer(tower_http::trace::TraceLayer::new_for_http())
        // NB: routes added after TraceLayer are not traced
        .route("/health", routing::get(|| async { "up" }));

    let listener = tokio::net::TcpListener::bind("0.0.0.0:8000").await?;
    axum::serve(listener, app.into_make_service()).await?;

    Ok(())
}
```

<br />

En este archivo `files.rs` tenemos las funciones relevantes a cambios en archivos, mas especificamente el archivo de
deployment.
```elixir
use crate::git::stage_and_push_changes;
use anyhow::Context;
use anyhow::Error;
use git2::Error as GitError;
use git2::Repository;
use k8s_openapi::api::apps::v1::Deployment;
use serde_yaml;
use std::fs;

fn patch_image_tag(file_path: String, image_name: String, new_sha: String) -> Result<(), Error> {
    println!("Patching image tag in deployment file: {}", file_path);
    let yaml_content = fs::read_to_string(&file_path).context("Failed to read deployment YAML file")?;

    println!("before: {:?}", yaml_content);

    // Parse the YAML into a Deployment resource
    let mut deployment: Deployment =
        serde_yaml::from_str(&yaml_content).context("Failed to parse YAML into Kubernetes Deployment")?;

    // Modify deployment specifics
    if let Some(spec) = deployment.spec.as_mut() {
        if let Some(template) = spec.template.spec.as_mut() {
            for container in &mut template.containers {
                if container.image.as_ref().unwrap().contains(&new_sha) {
                    println!("Image tag already updated... Aborting mission!");
                    return Err(anyhow::anyhow!("Image tag {} is already up to date", new_sha));
                }
                if container.image.as_ref().unwrap().contains(&image_name) {
                    container.image = Some(format!("{}:{}", &image_name, &new_sha));
                }
            }
        }
    }

    // Optional: Write modified deployment back to YAML file
    let updated_yaml =
        serde_yaml::to_string(&deployment).context("Failed to serialize updated deployment")?;

    println!("updated yaml: {:?}", updated_yaml);

    fs::write(file_path, updated_yaml).context("Failed to write updated YAML back to file")?;

    Ok(())
}

pub fn patch_deployment_and_commit(
    app_repo_path: &str,
    manifest_repo_path: &str,
    file_name: &str,
    image_name: &str,
) -> Result<(), GitError> {
    println!("Patching deployment and committing changes");
    let commit_message = "chore(refs): gitops-operator updating image tags";
    let app_repo = Repository::open(&app_repo_path)?;
    let manifest_repo = Repository::open(&manifest_repo_path)?;

    // Find the latest remote head
    // While this worked, it failed in some scenarios that were unimplemented
    // let new_sha = app_repo.head()?.peel_to_commit().unwrap().parent(1)?.id().to_string();

    let fetch_head = app_repo.find_reference("FETCH_HEAD")?;
    let remote = app_repo.reference_to_annotated_commit(&fetch_head)?;
    let remote_commit = app_repo.find_commit(remote.id())?;

    let new_sha = remote_commit.id().to_string();

    println!("New application SHA: {}", new_sha);

    // Perform changes
    let patch = patch_image_tag(
        format!("{}/{}", manifest_repo_path, file_name),
        image_name.to_string(),
        new_sha,
    );

    match patch {
        Ok(_) => println!("Image tag updated successfully"),
        Err(e) => {
            println!("We don't need to update image tag: {:?}", e);
            return Err(GitError::from_str(
                "Aborting update image tag, already updated...",
            ));
        }
    }

    // Stage and push changes
    let _ = stage_and_push_changes(&manifest_repo, commit_message)?;

    Ok(())
}
```

<br />

Y por ultimo pero no menos importante `git.rs`, posiblemente la parte mas compleja de este proyecto, git... Este archivo
tiene algunas funciones que se encargan de clonar, traer cambios remotos y fusionarlos, tambien para agregar los cambios
locales y enviarlos al repositorio remoto.
```elixir
use git2::{
    build::RepoBuilder, CertificateCheckStatus, Cred, Error as GitError, FetchOptions, RemoteCallbacks,
    Repository,
};
use std::env;
use std::io::{self, Write};
use std::path::{Path, PathBuf};

use git2::Signature;
use std::time::{SystemTime, UNIX_EPOCH};

fn create_signature<'a>() -> Result<Signature<'a>, GitError> {
    let name = "GitOps Operator";
    let email = "gitops-operator+kainlite@gmail.com";

    // Get current timestamp
    let time = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_secs();

    // Create signature with current timestamp
    Signature::new(name, email, &git2::Time::new(time as i64, 0))
}

fn normal_merge(
    repo: &Repository,
    local: &git2::AnnotatedCommit,
    remote: &git2::AnnotatedCommit,
) -> Result<(), git2::Error> {
    let local_tree = repo.find_commit(local.id())?.tree()?;
    let remote_tree = repo.find_commit(remote.id())?.tree()?;
    let ancestor = repo.find_commit(repo.merge_base(local.id(), remote.id())?)?.tree()?;
    let mut idx = repo.merge_trees(&ancestor, &local_tree, &remote_tree, None)?;

    if idx.has_conflicts() {
        println!("Merge conflicts detected...");
        repo.checkout_index(Some(&mut idx), None)?;
        return Ok(());
    }
    let result_tree = repo.find_tree(idx.write_tree_to(repo)?)?;
    // now create the merge commit
    let msg = format!("Merge: {} into {}", remote.id(), local.id());
    let sig = repo.signature()?;
    let local_commit = repo.find_commit(local.id())?;
    let remote_commit = repo.find_commit(remote.id())?;
    // Do our merge commit and set current branch head to that commit.
    let _merge_commit = repo.commit(
        Some("HEAD"),
        &sig,
        &sig,
        &msg,
        &result_tree,
        &[&local_commit, &remote_commit],
    )?;
    // Set working tree to match head.
    repo.checkout_head(None)?;
    Ok(())
}

pub fn clone_or_update_repo(url: &str, repo_path: PathBuf) -> Result<(), GitError> {
    println!("Cloning or updating repository from: {}", &url);

    // Setup SSH key authentication
    let mut callbacks = RemoteCallbacks::new();
    callbacks.credentials(|_url, username_from_url, _allowed_types| {
        // Dynamically find SSH key path
        let ssh_key_path = format!(
            "{}/.ssh/id_rsa_demo",
            env::var("HOME").expect("HOME environment variable not set")
        );

        println!("Using SSH key: {}", &ssh_key_path);
        println!("{}", Path::new(&ssh_key_path).exists());

        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            None,
            Path::new(&ssh_key_path),
            None,
        )
    });

    // TODO: implement certificate check, potentially insecure
    callbacks.certificate_check(|_cert, _host| {
        // Return true to indicate we accept the host
        Ok(CertificateCheckStatus::CertificateOk)
    });

    // Prepare fetch options
    let mut fetch_options = FetchOptions::new();
    fetch_options.remote_callbacks(callbacks);
    fetch_options.download_tags(git2::AutotagOption::All);

    // Check if repository already exists
    if repo_path.exists() {
        println!("Repository already exists, pulling...");

        // Open existing repository
        let repo = Repository::open(&repo_path)?;

        // Fetch changes
        fetch_existing_repo(&repo, &mut fetch_options)?;

        // Pull changes (merge)
        pull_repo(&repo, &fetch_options)?;
    } else {
        println!("Repository does not exist, cloning...");

        // Clone new repository
        clone_new_repo(url, &repo_path, fetch_options)?;
    }

    Ok(())
}

/// Fetch changes for an existing repository
fn fetch_existing_repo(repo: &Repository, fetch_options: &mut FetchOptions) -> Result<(), GitError> {
    println!("Fetching changes for existing repository");

    // Find the origin remote
    let mut remote = repo.find_remote("origin")?;

    // Fetch all branches
    let refs = &["refs/heads/master:refs/remotes/origin/master"];

    remote.fetch(refs, Some(fetch_options), None)?;

    Ok(())
}

/// Clone a new repository
fn clone_new_repo(url: &str, local_path: &Path, fetch_options: FetchOptions) -> Result<Repository, GitError> {
    println!("Cloning repository from: {}", &url);
    // Prepare repository builder
    let mut repo_builder = RepoBuilder::new();
    repo_builder.fetch_options(fetch_options);

    // Clone the repository
    repo_builder.clone(url, local_path)
}

/// Pull (merge) changes into the current branch
fn pull_repo(repo: &Repository, _fetch_options: &FetchOptions) -> Result<(), GitError> {
    println!("Pulling changes into the current branch");

    // Find remote branch
    let remote_branch_name = format!("remotes/origin/master");

    println!("Merging changes from remote branch: {}", &remote_branch_name);

    // Annotated commit for merge
    let fetch_head = repo.find_reference("FETCH_HEAD")?;
    let fetch_commit = repo.reference_to_annotated_commit(&fetch_head)?;

    // Perform merge analysis
    let (merge_analysis, _) = repo.merge_analysis(&[&fetch_commit])?;

    println!("Merge analysis result: {:?}", merge_analysis);

    if merge_analysis.is_fast_forward() {
        let refname = format!("refs/remotes/origin/master");
        let mut reference = repo.find_reference(&refname)?;
        reference.set_target(fetch_commit.id(), "Fast-Forward")?;
        repo.set_head(&refname)?;
        let _ = repo.checkout_head(Some(git2::build::CheckoutBuilder::default().force()));

        Ok(())
    } else if merge_analysis.is_normal() {
        let head_commit = repo.reference_to_annotated_commit(&repo.head()?)?;
        normal_merge(&repo, &head_commit, &fetch_commit)?;

        Ok(())
    } else if merge_analysis.is_up_to_date() {
        println!("Repository is up to date");
        Ok(())
    } else {
        Err(GitError::from_str("Unsupported merge analysis case"))
    }
}

pub fn stage_and_push_changes(repo: &Repository, commit_message: &str) -> Result<(), GitError> {
    println!("Staging and pushing changes");

    // Stage all changes (equivalent to git add .)
    let mut index = repo.index()?;
    index.add_all(["*"].iter(), git2::IndexAddOption::DEFAULT, None)?;
    index.write()?;

    // Create a tree from the index
    let tree_id = index.write_tree()?;
    let tree = repo.find_tree(tree_id)?;

    // Get the current head commit
    let parent_commit = repo.head()?.peel_to_commit()?;

    println!("Parent commit: {}", parent_commit.id());

    // Prepare signature (author and committer)
    // let signature = repo.signature()?;
    let signature = create_signature()?;

    println!("Author: {}", signature.name().unwrap());

    // Create the commit
    let commit_oid = repo.commit(
        Some("HEAD"),      // Update HEAD reference
        &signature,        // Author
        &signature,        // Committer
        commit_message,    // Commit message
        &tree,             // Tree to commit
        &[&parent_commit], // Parent commit
    )?;

    println!("New commit: {}", commit_oid);

    // Prepare push credentials
    let mut callbacks = RemoteCallbacks::new();
    callbacks.credentials(|_url, username_from_url, _allowed_types| {
        // Dynamically find SSH key path
        let ssh_key_path = format!(
            "{}/.ssh/id_rsa_demo",
            env::var("HOME").expect("HOME environment variable not set")
        );

        println!("Using SSH key: {}", &ssh_key_path);
        println!("{}", Path::new(&ssh_key_path).exists());

        Cred::ssh_key(
            username_from_url.unwrap_or("git"),
            None,
            Path::new(&ssh_key_path),
            None,
        )
    });

    // TODO: implement certificate check, potentially insecure
    callbacks.certificate_check(|_cert, _host| {
        // Return true to indicate we accept the host
        Ok(CertificateCheckStatus::CertificateOk)
    });

    // Print out our transfer progress.
    callbacks.transfer_progress(|stats| {
        if stats.received_objects() == stats.total_objects() {
            print!(
                "Resolving deltas {}/{}\r",
                stats.indexed_deltas(),
                stats.total_deltas()
            );
        } else if stats.total_objects() > 0 {
            print!(
                "Received {}/{} objects ({}) in {} bytes\r",
                stats.received_objects(),
                stats.total_objects(),
                stats.indexed_objects(),
                stats.received_bytes()
            );
        }
        io::stdout().flush().unwrap();
        true
    });

    // Prepare push options
    let mut push_options = git2::PushOptions::new();
    push_options.remote_callbacks(callbacks);

    // Find the origin remote
    let mut remote = repo.find_remote("origin")?;

    println!("Pushing to remote: {}", remote.url().unwrap());

    // Determine the current branch name
    let branch_name = repo.head()?;
    let refspec = format!("refs/heads/{}", branch_name.shorthand().unwrap_or("master"));

    println!("Pushing to remote branch: {}", &refspec);

    // Push changes
    remote.push(&[&refspec], Some(&mut push_options))?;

    Ok(())
}

// Example usage in the context of the original code
pub fn clone_repo(url: &str, local_path: &str) {
    let repo_path = PathBuf::from(local_path);

    match clone_or_update_repo(url, repo_path) {
        Ok(_) => println!("Repository successfully updated"),
        Err(e) => eprintln!("Error updating repository: {}", e),
    }
}
```

<br />

Algunas cosas que necesito mejorar en todo ese código son: 
- Manejo de errores 
- Estandarizar todas las funciones para que se comporten de manera similar 
- Estandarizar los logs y eliminar toda la información de depuración 
- Refactorizar las funciones para que sean más específicas y manejen una sola responsabilidad 

Y algunas cosas más, pero recordá que esto es un MVP; por ahora, lo único que importa es que funcione.

<br />

###### El pipeline
Para completar el panorama, agreguemos la pipeline. Como podés ver, tenemos dos jobs: uno para **lint** y validar que el código esté correctamente formateado, y otro para **compilar y publicar la imagen en DockerHub**. Lo más interesante probablemente sea el "baile del caché".

```elixir
name: ci

on:
  pull_request:
  push:
    branches:
      - master
    tags:
      - '*'

jobs:
  docker:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    strategy:
      fail-fast: false
      matrix:
        platform:
          - linux/amd64
          #- linux/arm64
    steps:
      - uses: actions/checkout@v4

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      # Build and push with docker buildx
      - name: Setup docker buildx
        uses: docker/setup-buildx-action@v3
        with:
          config: .github/buildkitd.toml

      - name: Configure tags based on git tags + latest
        uses: docker/metadata-action@v5
        id: meta
        with:
          images: ${{ github.repository }}
          tags: |
            type=sha,prefix=,suffix=,format=short
            type=sha,prefix=,suffix=,format=long
            type=ref,event=branch
            type=pep440,pattern={{version}}
            type=raw,value=latest,enable={{is_default_branch}}
            type=ref,event=pr

      - name: Rust Build Cache for Docker
        uses: actions/cache@v4
        with:
          path: rust-build-cache
          key: ${{ runner.os }}-build-cache-${{ hashFiles('**/Cargo.toml') }}

      - name: inject rust-build-cache into docker
        uses: overmindtech/buildkit-cache-dance/inject@main
        with:
          cache-source: rust-build-cache

      - name: Docker login
        uses: docker/login-action@v3
        #if: github.event_name != 'pull_request'
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Docker build and push with cache
        uses: docker/build-push-action@v6
        with:
          context: .
          # when not using buildkit cache
          #cache-from: type=registry,ref=ghcr.io/${{ github.repository }}:buildcache
          #cache-to: type=registry,ref=ghcr.io/${{ github.repository }}:buildcache
          # when using buildkit-cache-dance
          cache-from: type=gha
          cache-to: type=gha,mode=max
          #push: ${{ github.ref == 'refs/heads/main' }}
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          platforms: ${{ matrix.platform }}

      - name: extract rust-build-cache from docker
        uses: overmindtech/buildkit-cache-dance/extract@main
        with:
          cache-source: rust-build-cache

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: dtolnay/rust-toolchain@stable
        with:
          toolchain: stable
          components: rustfmt,clippy
      - run: cargo fmt -- --check

      - uses: giraffate/clippy-action@v1
        with:
          reporter: 'github-pr-review'
          github_token: ${{ secrets.GITHUB_TOKEN }}
```

<br />

Cada vez que realicemos un cambio en la aplicación, veremos automáticamente un commit del controlador, algo así: 
![commits](/images/gitops-operator-3.png){:class="mx-auto"}

<br />

###### Manifiestos
Una de las cosas que necesitamos hacer para que esto funcione es almacenar nuestra **clave SSH como un secreto** para poder montarla (podríamos haber leído el secreto directamente desde el controlador usando **kube-rs**, pero este enfoque era más sencillo). Como notarás, tenemos un conjunto de **anotaciones** para configurar el controlador y que actúe sobre nuestro **Deployment**, y luego montamos la clave SSH que generamos previamente para que pueda **obtener y escribir en el repositorio de manifiestos**.

Además, verás que estamos llamando a la ruta `/reconcile` cada dos minutos desde el **Readiness Probe**. Kubernetes seguirá llamando a ese endpoint cada dos minutos basándose en nuestra configuración. Como no esperamos tráfico externo, esto debería ser suficiente. Además, debería ser relativamente seguro ejecutarlo de forma concurrente, por lo que es una solución adecuada por ahora.

```elixir
apiVersion: apps/v1
kind: Deployment
metadata:
  annotations:
    gitops.operator.app_repository: git@github.com:kainlite/gitops-operator.git
    gitops.operator.deployment_path: app/00-deployment.yaml
    gitops.operator.enabled: 'true'
    gitops.operator.image_name: kainlite/gitops-operator
    gitops.operator.manifest_repository: git@github.com:kainlite/gitops-operator-manifests.git
    gitops.operator.namespace: default
  labels:
    app: gitops-operator
  name: gitops-operator
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: gitops-operator
  template:
    metadata:
      labels:
        app: gitops-operator
    spec:
      containers:
      - image: kainlite/gitops-operator:ab76bb8f5064a6df5ed54ae68b0f0c6eaa6dcbb6
        imagePullPolicy: Always
        livenessProbe:
          failureThreshold: 5
          httpGet:
            path: /health
            port: http
          periodSeconds: 15
        name: gitops-operator
        ports:
        - containerPort: 8000
          name: http
          protocol: TCP
        readinessProbe:
          httpGet:
            path: /reconcile
            port: http
          initialDelaySeconds: 60
          periodSeconds: 120
          timeoutSeconds: 60
        resources:
          limits:
            cpu: 1000m
            memory: 1024Mi
          requests:
            cpu: 500m
            memory: 100Mi
        volumeMounts:
        - mountPath: /home/nonroot/.ssh/id_rsa_demo
          name: my-ssh-key
          readOnly: true
          subPath: ssh-privatekey
      serviceAccountName: gitops-operator
      volumes:
      - name: my-ssh-key
        secret:
          items:
          - key: ssh-privatekey
            path: ssh-privatekey
          secretName: my-ssh-key
```

<br />

**¡BONUS!** 
Si no recordás cómo crear una clave y almacenarla como un **secreto** en Kubernetes, es realmente simple. Si necesitás ayuda o querés una referencia rápida sobre las formas más comunes de crear y usar secretos en Kubernetes, te recomiendo mi [artículo al respecto](https://redbeard.team/en/blog/mounting-secrets-in-kubernetes): 

<br />

```elixir
ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa_demo
kubectl create secret generic my-ssh-key --from-file=ssh-privatekey=~/.ssh/id_rsa_demo
```

¡Y listo! Pronto estaré subiendo una versión en video, seguime en **LinkedIn** para mantenerte al tanto de las novedades.

##### **Notas finales**  
Esto estuvo fuertemente inspirado y basado en los ejemplos de **kube-rs: `version-rs`**, así como en muchos ejemplos del repositorio de **`git2`**. 
Si te gustó, seguime y compartilo para más contenido como este. ¡Nos vemos en la próxima! 🚀
