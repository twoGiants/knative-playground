# Knative Playground

## Knative Serving Concepts

Core resources:

- **Services**: *top-level container for managing Route and Configuration.*
- **Routes**: *provides a named endpoint that is backed by one or more Revisions.*
- **Configurations**: *describes the desired state of a Revision, update triggers a new Revision.*
- **Revisions**: *immutable snapshot of code and configuration.*

![serving architecture](docs/serving_arch.png)

A few more words about Revisions:

- Support [auto scaling](https://knative.dev/docs/serving/autoscaling/).
- Support [gradual rollout](https://knative.dev/docs/serving/rolling-out-latest-revision/) of traffic.
- Automatically garbage collected.

## Knative Eventing Concepts

Set of APIs which allow to create components which route events from loosely coupled producers to consumers:

- **Event producers / Sources**: *developed and deployed independently, can generate events before a consumer exist.*
- **Event consumers / Sinks**: *can listen to events before producers exist and can send response events.*

Supporting workloads:

- Kubernetes Services
- Knative Serving Services

**Events:**

- Are send via HTTP POST.
- Conform to `CloudEvents` specification => language agnostic.

**Brokers:**

- Provide endpoint for event ingress.
- Deliver events via Triggers.

**Triggers:**

- Can filter events and send them to a Sink / Subscriber.

**Sink**:

- Can be any URL or `Addressable` resource.
- Can reply and respond with a new event.

![broker](docs/brokers.png)

## Duck Typing

Knative can use a resource without specific knowledge about the resource type, if:

- The resource has the same fields as the common definition specifies.
- The same behaviors as the common definition specifies.

Sounds like **Interfaces**.

## Quickstart

### Issues

Open PRs and issues for this found issues.

#### Issue 1

> **SOLUTION**: `kn quickstart kind -k 1.34.0`

- `kn quickstart kind` times out using latest Kind version:

  ```sh
   kn quickstart kind
  Running Knative Quickstart using Kind
  ✅ Checking dependencies...
      Kind version is: 0.30.0

  A local registry is no longer created by default.
      To create a local registry, use the --registry flag.

  ☸ Creating Kind cluster...
  Creating cluster "knative" ...
  ✓ Ensuring node image (kindest/node:v1.31.6) 🖼
  ✓ Preparing nodes 📦
  ✓ Writing configuration 📜
  ✓ Starting control-plane 🕹️
  ✓ Installing CNI 🔌
  ✓ Installing StorageClass 💾
  ✓ Waiting ≤ 2m0s for control-plane = Ready ⏳
  • Ready after 15s 💚
  Set kubectl context to "kind-knative"
  You can now use your cluster with:

  kubectl cluster-info --context kind-knative

  Thanks for using kind! 😊

  🍿 Installing Knative Serving v1.19.3 ...
      CRDs installed...
  timed out waiting for the condition on pods/activator-6d6644f864-qtq9c
  timed out waiting for the condition on pods/autoscaler-8545d6994c-4cfhr
  timed out waiting for the condition on pods/controller-769f5cd67c-hlcpw
  timed out waiting for the condition on pods/webhook-5f965ddcc5-7bksd

  Error: failed to install serving to kind cluster knative: core: exit status 1
  Usage:
    kn-quickstart kind [flags]

  Flags:
        --extraMountContainerPath string   set the extraMount containerPath on Kind quickstart cluster
        --extraMountHostPath string        set the extraMount hostPath on Kind quickstart cluster
    -h, --help                             help for kind
        --install-eventing                 install Eventing on quickstart cluster
        --install-serving                  install Serving on quickstart cluster
    -k, --kubernetes-version string        kubernetes version to use (1.x.y) or (kindest/node:v1.x.y)
    -n, --name string                      kind cluster name to be used by kn-quickstart (default "knative")
        --registry                         install registry for Kind quickstart cluster

  failed to install serving to kind cluster knative: core: exit status 1
  Error: exit status 1
  ```

- pods are in `CrashLoopBackOff`

  ```sh
   k -n knative-serving get po
  NAMESPACE            NAME                                            READY   STATUS             RESTARTS        AGE
  knative-serving      activator-6d6644f864-qtq9c                      0/1     CrashLoopBackOff   5 (78s ago)     9m9s
  knative-serving      autoscaler-8545d6994c-4cfhr                     0/1     CrashLoopBackOff   6 (28s ago)     9m9s
  knative-serving      controller-769f5cd67c-hlcpw                     0/1     CrashLoopBackOff   6 (2m33s ago)   9m9s
  knative-serving      webhook-5f965ddcc5-7bksd                        0/1     CrashLoopBackOff   6 (2m34s ago)   9m9s
  ```

- pod logs showing wrong kubernetes version

  ```sh
   k -n knative-serving logs activator-6d6644f864-qtq9c
  2025/09/06 16:06:16 Registering 2 clients
  2025/09/06 16:06:16 Registering 3 informer factories
  2025/09/06 16:06:16 Registering 5 informers
  2025/09/06 16:06:16 Failed to get k8s version kubernetes version "1.31.6" is not compatible, need at least "1.32.0-0" (this can be overridden with the env var "KUBERNETES_MIN_VERSION")
  # ...
  ```

#### Issue 2

> **SOLUTION**: ***tba***

- installation of Kourier in Kind cluster fails in the beginning but works later

  ```sh
   kn quickstart kind --registry -k 1.34.0

  Running Knative Quickstart using Kind
  ✅ Checking dependencies...
      Kind version is: 0.30.0
  💽 Installing local registry...
  Pulling from library/registry: 2
  Digest: sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373: %!s(<nil>)
  Status: Image is up to date for registry:2: %!s(<nil>)
  ☸ Creating Kind cluster...
  Creating cluster "knative" ...
  ✓ Ensuring node image (kindest/node:v1.34.0) 🖼
  ✓ Preparing nodes 📦
  ✓ Writing configuration 📜
  ✓ Starting control-plane 🕹️
  ✓ Installing CNI 🔌
  ✓ Installing StorageClass 💾
  ✓ Waiting ≤ 2m0s for control-plane = Ready ⏳
  • Ready after 16s 💚
  Set kubectl context to "kind-knative"
  You can now use your cluster with:

  kubectl cluster-info --context kind-knative

  Have a question, bug, or feature request? Let us know! <https://kind.sigs.k8s.io/#community> 🙂

  🔗 Patching node: knative-control-plane
  🍿 Installing Knative Serving v1.19.3 ...
      CRDs installed...
      Core installed...
      Enabled local registry deployment...
      Finished installing Knative Serving
  🕸️ Installing Kourier networking layer v1.19.2 ...
  error: no matching resources found

  Error: failed to install kourier to kind cluster knative: kourier: exit status 1
  Usage:
    kn-quickstart kind [flags]

  Flags:
        --extraMountContainerPath string   set the extraMount containerPath on Kind quickstart cluster
        --extraMountHostPath string        set the extraMount hostPath on Kind quickstart cluster
    -h, --help                             help for kind
        --install-eventing                 install Eventing on quickstart cluster
        --install-serving                  install Serving on quickstart cluster
    -k, --kubernetes-version string        kubernetes version to use (1.x.y) or (kindest/node:v1.x.y)
    -n, --name string                      kind cluster name to be used by kn-quickstart (default "knative")
        --registry                         install registry for Kind quickstart cluster

  failed to install kourier to kind cluster knative: kourier: exit status 1
  Error: exit status 1
  ```

- error happens in [`install.go:L36`](https://github.com/knative-extensions/kn-plugin-quickstart/blob/main/pkg/install/install.go#L36) => it looks like the previous command `kubectl apply ...` is not yet finished and it moves to the next command waiting for pods but there are no pods yet or not even a namespace
