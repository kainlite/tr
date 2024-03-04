# Install 

```
kubectl apply -f https://storage.googleapis.com/tekton-releases/pipeline/previous/v0.39.0/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.21.0/release.yaml
kubectl apply -f https://storage.googleapis.com/tekton-releases/triggers/previous/v0.21.0/interceptors.yaml
```

After configuring `kubectl` locally and `tkn`:
```
tkn -n tekton-pipelines hub install task git-clone
tkn -n tekton-pipelines hub install task kaniko
tkn -n tekton-pipelines hub install task kubernetes-actions
```

To run migrations manually, jump into any app pod and run:
```
/app/bin/tr eval "Tr.Release.migrate()"
```

Useful links:
https://github.com/tektoncd/triggers/blob/main/docs/getting-started/README.md
https://tekton.dev/docs/how-to-guides/kaniko-build-push/#full-code-samples
https://www.arthurkoziel.com/tutorial-tekton-triggers-with-github-integration/

There are some issues running on ARM, on other architectures it just works, see more:
https://github.com/tektoncd/pipeline/issues/5233
https://github.com/tektoncd/pipeline/issues/4247
