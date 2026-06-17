# nvidia-dynamo

Cozystack external app that wraps the NVIDIA Dynamo Kubernetes Platform
(`ai-dynamo/dynamo`) as a tenant-creatable `NvidiaDynamo` resource.

A tenant provisions an `NvidiaDynamo` CR through the Cozystack dashboard;
the cozystack controller renders it into a Flux `HelmRelease` that deploys
the upstream `dynamo-platform` chart (operator + NATS + etcd + Grove +
Kai scheduler) and, optionally, a `DynamoGraphDeployment` CR that brings
up the configured model serving topology.

## Layout (cozystack v1.x PackageSource model)

- `charts/nvidia-dynamo/` — the wrapper Helm chart. CI publishes this as
  an OCI artifact at `oci://ghcr.io/aenix-org/charts/nvidia-dynamo`.
- `packages/core/platform/templates/`:
  - `packagesource.yaml` — `OCIRepository` + `PackageSource`. Cozystack
    engine consumes the OCI artifact and emits an `ExternalArtifact`
    named `nvidia-dynamo-default-nvidia-dynamo` per cluster.
  - `cozyrds.yaml` — `ApplicationDefinition` (`kind: NvidiaDynamo`)
    whose `release.chartRef` points at the `ExternalArtifact` above.
- `init.yaml` — bootstrap `GitRepository` + `HelmRelease` for the
  platform chart (registers PackageSource and ApplicationDefinition
  into the cluster). Mirrors the kubernetes-switchcloud pattern.
- `_packages/`:
  - `package.yaml` — one-time `Package` CR (variant `default`) that
    activates the PackageSource in a target cluster.
  - `example-values.yaml` — sample `NvidiaDynamo` tenant resource for
    end-to-end test on ttk (Qwen 2.5 7B on 1× RTX A6000).

## Prerequisites on the target cluster

- At least one node with NVIDIA GPUs exposed as `nvidia.com/gpu`. On
  Cozystack/Talos this means either:
  - `system/gpu-operator` deployed in `native-talos` mode (preferred from
    cozystack v1.0+), or
  - A Talos installer image that bakes `nonfree-kmod-nvidia-production` +
    `nvidia-container-toolkit-production` extensions, plus
    `nvidia-device-plugin` running on GPU nodes.
- A storage class that can satisfy NATS PVCs.
- An external etcd reachable from `cozy-dynamo` — the Bitnami etcd
  subchart is stripped during vendoring (Bitnami images are forbidden in
  this org). Point the operator at a cozystack-managed `Etcd` instance
  via `dynamo-platform.dynamo-operator.etcdAddr` in your Package values.
- An NGC API key in every namespace that pulls Dynamo runtime / operator
  images from `nvcr.io`. Anonymous pulls return `404`. Free NGC account
  at <https://ngc.nvidia.com/setup/api-key>; create the `ngc-creds`
  Secret in `cozy-dynamo` and every tenant namespace that will host a
  `NvidiaDynamo` CR:

  ```sh
  kubectl create secret docker-registry ngc-creds \
    --namespace=cozy-dynamo \
    --docker-server=nvcr.io \
    --docker-username='$oauthtoken' \
    --docker-password='<NGC_API_KEY>'
  ```

  Override `serving.imagePullSecrets` / `dynamo-platform.dynamo-operator.imagePullSecrets`
  in `values.yaml` (or via the `NvidiaDynamo` CR) to point at a different
  Secret name when needed.
- Ingress controller available if `host` is set in the `NvidiaDynamo`
  spec.

## Status

Skeleton — not yet pushed to its own git repository. Will be moved to
`aenix-org/package-nvidia-dynamo` with CI once the wiring is verified end-to-end
on the ttk cluster.
