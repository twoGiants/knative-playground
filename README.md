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

