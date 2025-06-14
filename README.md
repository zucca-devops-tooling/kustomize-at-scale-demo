# Kustomize and Kyverno at Scale: A CI/CD Demonstration

This repository serves as a real-world demonstration for a suite of tools designed to solve the performance and complexity challenges of managing large-scale Kubernetes GitOps repositories. It showcases the combined power of [**kustom-trace**](https://github.com/zucca-devops-tooling/kustom-trace) and [**kyverno-parallel-apply**](https://github.com/zucca-devops-tooling/kyverno-parallel-apply) to create fast, intelligent, and reliable CI/CD pipelines.

The application set used for this demo is derived from several excellent, complex, real-world repositories, including:

* [onedr0p/home-ops](https://github.com/onedr0p/home-ops)
* [operate-first/apps](https://github.com/operate-first/apps)
* [A custom-generated](https://github.com/zucca-devops-tooling/kustomize-at-scale-demo/blob/main/generate-expensive-apps.sh) workload of over 1500 resources designed to simulate an expensive policy evaluation environment.

---

## The Problem: CI/CD Bottlenecks in Complex GitOps Repos

As GitOps repositories grow to manage hundreds or thousands of applications, standard CI/CD processes face significant challenges that lead to slow, unreliable, and inefficient builds.

1.  **Identifying Build Targets:** In a complex repository with many applications reusing shared components, simply identifying which applications to build with `kustomize build` becomes a challenge. The common approach of maintaining a manually curated list of "root" applications (e.g., in a central `kustomization.yaml` or a script) is brittle, error-prone, and adds maintenance overhead.

2.  **Expensive Policy Enforcement:** Applying security and best-practice policies with tools like Kyverno is critical, but it can be extremely slow. In this demo repository, applying a full set of policies against all 2500+ generated resources takes **8 minutes and 22 seconds** in a single thread. In large enterprise environments, this can scale to hours, making it an unacceptable bottleneck.

3.  **Inefficient Pull Request Validation:** The lack of a reliable way to identify which applications are truly affected by a PR leads to poor choices, each with a significant disadvantage:
    * **a) Build Everything:** Running `kustomize build` and `kyverno apply` on all applications for every PR is safe but leads to extremely slow and expensive CI pipelines.
    * **b) Build Nothing:** Skipping validation on PRs makes the pipeline fast but provides zero feedback to developers, shifting the burden of finding errors to the post-merge build.
    * **c) Use Heuristics:** Relying on simple path-based logic (e.g., "only build apps in directories that have changed files") is unreliable and dangerous. It often fails to detect changes in shared components or bases, creating a significant risk of not building and testing all truly affected applications.

## The Solution: Intelligent Tooling

This demo showcases a two-part solution that directly addresses these problems.

### 1. `kustom-trace`: For Reliable Application Discovery

[kustom-trace](https://github.com/zucca-devops-tooling/kustom-trace) is a command-line tool that analyzes the dependency graph of a Kustomize repository to provide precise answers about its structure.

* `list-root-apps`: This function scans the entire repository and reliably identifies all the "root" applications that can be built, solving Problem #1 without any manual lists.
* `affected-apps`: This function takes a list of changed files from a pull request and accurately determines the exact set of root applications impacted by those changes, solving Problem #3.

### 2. `kyverno-parallel-apply`: For High-Performance Policy Enforcement

[kyverno-parallel-apply](https://github.com/zucca-devops-tooling/kyverno-parallel-apply) is a Jenkins Shared Library that fixes Problem #2. It takes a large set of manifests and automatically shards them into smaller batches, running `kyverno apply` on each batch in a parallel Jenkins stage. This takes full advantage of the multiple CPU cores available on Jenkins nodes, dramatically reducing the overall execution time.

## The Impact: A Fast and Reliable CI Workflow

By combining these two tools, we can create a CI pipeline that is both fast and reliable. The `Jenkinsfile` in this repository demonstrates the complete workflow.

### 1. Simple and Reliable Application Building

First, we get a reliable list of which applications to build.

**For a full build (e.g., on the `main` branch):**

```bash
# Get the list of all applications
java -jar kustomtrace.jar -a ./kubernetes -o app-list.yaml list-root-apps
```

**For a partial build (on a Pull Request):**

```bash
# Get the list of changed files from Git
# (The Jenkinsfile contains the full logic for this)
CHANGED_FILES=$(git diff --name-only origin/main...HEAD)

# Get only the applications affected by the changed files
java -jar kustomtrace.jar -a ./kubernetes -o app-list.yaml affected-apps $CHANGED_FILES
```

### 2. High-Performance Parallel Policy Application

Next, we use the `kyverno-parallel-apply` library to run `kyverno apply` on the generated manifests. The library call is simple and configurable.

```groovy
// Import the library at the top of your Jenkinsfile:
// @Library('kyverno-parallel-apply@v1.0.0') _
// In a later Jenkinsfile stage, after building the manifests
stage('Apply Kyverno Policies') {
    steps {
        script {
            kyvernoParallelApply([
                'manifestSourceDirectory': builtAppsFolder,
                'policyPath': policiesFile,
                'finalReportPath': kyvernoResults,
                'generatedResourcesDir': 'generated-artifacts',
                'debugLogDir': 'debug-logs',
                'extraKyvernoArgs': '--cluster --audit-warn'
            ])
        }
    }
}
```

### The Results

The impact on performance is significant.

* **Single-Threaded Kyverno Apply Time:** **8 minutes, 22 seconds**
* **Parallelized Kyverno Apply Time (4 executors):** **3 minutes, 46 seconds**
    * (This includes a fixed overhead of ~30 seconds for setup and result merging)

![image](https://github.com/user-attachments/assets/89c6a640-decd-4091-9feb-204c51b74d9d)

This represents a **55% reduction** in the policy enforcement bottleneck. The pipeline also automatically archives the final merged policy report, any generated/mutated resources, and the debug logs from each parallel shard as build artifacts.

![image](https://github.com/user-attachments/assets/9c55fac8-2629-4452-be85-3d5dbe891d1a)
![image](https://github.com/user-attachments/assets/1d03cd51-f5b2-4fc9-bf8b-f6ff7ab46eba)


*(You could add a screenshot here of the Jenkins "Pipeline Steps" view showing the parallel stages running simultaneously)*

This approach provides a robust, efficient, and maintainable solution for managing CI/CD on large-scale Kustomize repositories.
