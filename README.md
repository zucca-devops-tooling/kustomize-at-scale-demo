# Kustomize and Kyverno at Scale: A CI/CD Demonstration

This repository is a demonstration environment for two tools aimed at large Kustomize-based GitOps repositories.

It showcases two tools:

- [kustom-trace](https://github.com/zucca-devops-tooling/kustom-trace) to discover which Kustomize applications should be built
- [kyverno-parallel-apply](https://github.com/zucca-devops-tooling/kyverno-parallel-apply) to reduce the runtime of large `kyverno apply` scans in Jenkins

The Kubernetes content in this repository is the workload. `kustom-trace` and `kyverno-parallel-apply` are the products being demonstrated.

The workload is intentionally non-trivial. It mixes real-world style application trees with a synthetic stress workload so the pipeline exercises discovery, rendering, and policy evaluation at a scale where naive CI approaches start to break down.

The application set is derived from several large repositories and layouts, including:

- [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
- [operate-first/apps](https://github.com/operate-first/apps)
- a generated workload from [`generate-expensive-apps.sh`](./generate-expensive-apps.sh) used to make Kyverno evaluation meaningfully expensive on `main`

## Why This Repository Is A Good Demo Workload

- [`kubernetes/apps/`](./kubernetes/apps/) and [`kubernetes/operate-first/`](./kubernetes/operate-first/)
  Provide a large set of deployable Kustomize entry points, nested structures, and reused building blocks so root-app discovery is a real problem instead of a toy example.
- [`kubernetes/components/`](./kubernetes/components/) and [`kubernetes/flux/`](./kubernetes/flux/)
  Add shared dependencies and indirection that make simple path-based PR heuristics unreliable.
- [`policies/`](./policies/)
  Supplies a real Kyverno policy set for validating the rendered manifests.
- [`generate-expensive-apps.sh`](./generate-expensive-apps.sh)
  Adds synthetic scale on `main` by writing 100 files with 100 ConfigMaps each, where every ConfigMap contains 100 annotations. This exists because the demo runs against rendered manifests only: without live clusters or remote APIs in the loop, raw manifest evaluation alone was not slow enough to make the parallelization impact obvious.
- [`Jenkinsfile`](./Jenkinsfile)
  Shows how both tools fit into one CI pipeline: discovery, selective rendering, sequential policy evaluation, and parallel policy evaluation.

## The Problems This Demo Targets

As a Kustomize repository grows, three CI problems become hard to ignore:

1. **Finding build targets**

   In a repo with shared bases, components, and nested Kustomizations, maintaining a hand-written list of "root apps" is brittle. It drifts over time and is easy to get wrong.

2. **Validating pull requests efficiently**

   PR validation usually falls into one of three bad patterns:

   - build everything and pay the full cost on every change
   - build too little and miss regressions in shared dependencies
   - rely on path heuristics that do not understand the real Kustomize graph

3. **Keeping policy enforcement fast enough**

   Kyverno is valuable, but `kyverno apply` can become expensive for two different reasons: large rendered manifest sets and remote communication during policy evaluation. In production, the dominant bottleneck is often the remote side of the work. This demo does not have live clusters or external APIs available, so it uses synthetic manifest scale to create an expensive enough local workload to benchmark.

## The Tooling Strategy

### `kustom-trace`

[`kustom-trace`](https://github.com/zucca-devops-tooling/kustom-trace) analyzes the local Kustomize dependency graph and answers two key questions for this demo:

- `list-root-apps`: which Kustomization directories are true deployable entry points
- `affected-apps`: which root apps are impacted by a set of changed files

That gives the pipeline a reliable way to:

- build everything on `main`
- build only the affected applications on pull requests

Recent `kustom-trace` releases also publish native binaries for Linux, Windows, and macOS, which removes the local Java prerequisite when reproducing the workflow. This demo pipeline still downloads the shaded JAR because it is simple and already wired into Jenkins.

Example invocations:

```bash
# Shaded JAR
java -jar kustomtrace-cli-<version>-all.jar --apps-dir ./kubernetes list-root-apps

# Native binary
./kustomtrace-linux-x64 --apps-dir ./kubernetes affected-apps ./kubernetes/components/common/namespace.yaml
```

### `kyverno-parallel-apply`

[`kyverno-parallel-apply`](https://github.com/zucca-devops-tooling/kyverno-parallel-apply) is a Jenkins Shared Library that splits a large manifest directory into shards, runs `kyverno apply` in parallel, and merges the results into a final report.

In this repository it is used to demonstrate the difference between:

- a straightforward single-process `kyverno apply`
- a sharded parallel scan on the same rendered manifest set

The local benchmark here is manifest-heavy by design, but the library is also relevant when Kyverno spends time waiting on remote communication, cluster lookups, or API-driven policy evaluation. Those production bottlenecks are not fully reproduced by this local-only demo.

## How The Jenkins Pipeline Works

The pipeline in [`Jenkinsfile`](./Jenkinsfile) has two modes.

### `main` branch flow

1. Check out the repository.
2. Download the pinned `kustom-trace` CLI JAR.
3. Run `list-root-apps` against `./kubernetes`.
4. Build each discovered root app into `kustomize-output/<app>.yaml`.
5. Build the Kyverno policies from `./policies` into `policies.yaml`.
6. Generate an extra synthetic workload with [`generate-expensive-apps.sh`](./generate-expensive-apps.sh).
7. Run a regular `kyverno apply` and archive `results.yaml`.
8. Run `kyvernoParallelApply(...)` against the same manifest directory to demonstrate the parallel path.

### Pull request flow

1. Fetch the target branch from `env.CHANGE_TARGET` or default to `main`.
2. Collect changed files from `git diff`.
3. Run `affected-apps` with that file list.
4. Collapse the file-to-app mapping into a unique root app list.
5. Build only the impacted applications.
6. Build the Kyverno policies.
7. Run the regular `kyverno apply` stage.
8. Skip the synthetic workload and the parallel apply stage.

This is the key idea of the demo:

- `kustom-trace` keeps application selection precise
- `kustomize` renders the selected applications
- `kyverno` validates the rendered output
- `kyverno-parallel-apply` reduces the bottleneck once the manifest set is large enough

## Representative Commands

Full application discovery:

```bash
java -jar kustomtrace-cli-<version>-all.jar --apps-dir ./kubernetes --output apps.yaml list-root-apps
```

Affected application discovery for a pull request:

```bash
git fetch origin main
git diff --name-only FETCH_HEAD...HEAD > changed-files.txt
java -jar kustomtrace-cli-<version>-all.jar --apps-dir ./kubernetes --output affected.yaml affected-apps --files-from-file changed-files.txt
```

Sequential Kyverno run:

```bash
kustomize build ./policies -o policies.yaml
kyverno apply policies.yaml --resource kustomize-output --audit-warn --policy-report --output generated > results.yaml
```

The Jenkins pipeline then archives `results.yaml`, and the parallel stage uses the same rendered manifests as input for the shared library.

## Example Results

One benchmark captured for this demo repository showed:

- **Single-threaded `kyverno apply`:** **8 minutes, 22 seconds**
- **Parallelized apply with 4 executors:** **3 minutes, 46 seconds**

That is roughly a **55% reduction** in the Kyverno bottleneck. The parallel timing reflects the full Jenkins stage, including setup, four shard executions, result merge, and workspace cleanup, not just the shard bodies alone. Because this demo runs on rendered manifests rather than live cluster or remote API interactions, treat the numbers as a local demonstration of the technique rather than a direct predictor of production results. Exact numbers will vary with agent size, policy set, remote dependencies, and how much synthetic workload is added.

![Kyverno Runtime Comparison](https://github.com/user-attachments/assets/89c6a640-decd-4091-9feb-204c51b74d9d)

The shard structure in Jenkins looks like this:

- setup a shared parallel workspace
- fan out into `Shard 0` through `Shard 3`
- run `kyverno apply` once per shard
- merge the shard reports
- clean up the temporary workspace

That matters because the comparison is against a real end-to-end parallel stage rather than an isolated micro-benchmark.

The demo setup can also emit generated artifacts and shard-level debug logs for inspection during the parallel run.

![Archived Jenkins Artifacts](https://github.com/user-attachments/assets/9205644d-cea6-4816-9da8-0385d65c104f)

## Why This Demo Is Useful

This repository is not a toy example. It is useful for evaluating:

- root app discovery across a large Kustomize tree
- PR blast-radius analysis for shared components and bases
- the cost of rendering many deployable units
- the runtime impact of Kyverno as the manifest set grows
- the practical benefit of sharding policy evaluation in Jenkins

## License

Apache License 2.0. See [`LICENSE`](./LICENSE).
