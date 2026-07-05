# Problem Completion Check — YAS CD System

**Checked:** 2026-07-05 · **Method:** live `kubectl` against the real cluster (`teammate-kubeconfig.yaml`) + repo manifest/workflow inspection.

> **Cluster note:** The graded/live cluster is the **DigitalOcean managed K8s** `do-sgp1-...` (reachable via `teammate-kubeconfig.yaml`), **not** the local `minikube` (which is empty). All "live" checks below ran against DigitalOcean.

---

## TL;DR Verdict

| Area | Status |
|------|--------|
| K8s cluster | ✅ Live (3 nodes) |
| CI per branch → Docker Hub | ✅ Implemented (workflow present) |
| `developer_build` CD job | ✅ Implemented |
| Delete deployment job | ✅ Implemented (as `cleanup` action, GH Actions not Jenkins) |
| Dev auto-deploy (dev ns) | ⚠️ **Broken live** — placeholder image, Degraded |
| Staging (staging ns) | ⚠️ **Broken live** — placeholder image, Degraded |
| Advanced 1: ArgoCD | ⚠️ **Partial** — installed & Synced, but apps Degraded |
| Advanced 2: Service Mesh | ✅ **Fully live & tested** |
| 14 core services | ✅ All live in `yas` ns (2/2, sidecar-injected) |
| Observability (out of scope) | ⚠️ Deployed but **scaled to 0** (not live) |

**Bottom line:** Service mesh (Advanced 2) is complete and enforcing. Core 14 services run live in the `yas` namespace. The **base dev/staging pipeline and ArgoCD (Advanced 1) are broken in the live cluster** because the ArgoCD-rendered deployments carry an unsubstituted `DOCKERHUB_USERNAME` placeholder image and only render `swagger-ui`.

---

## 1. Kubernetes Cluster — ✅

- DigitalOcean managed K8s `do-sgp1-k8s-1-36-0`, node pool `devops-project02-large-*` (≥3 worker nodes seen scheduling pods).
- Requirement is "1 master + 1 worker OR minikube OR any model" → managed multi-node satisfies it.

## 2. CI Pipeline per branch — ✅ (code)
- `.github/workflows/ci.yml`: `push` on `branches-ignore: [main]`, `tags-ignore: [v*]`, matrix over all services, builds + pushes to Docker Hub with commit tag.
- Per-service CI files also present (`product-ci.yaml`, `cart-ci.yaml`, … ~20 files).
- *Not runtime-verifiable from cluster; workflow definitions are correct.*

## 3. `developer_build` CD Job — ✅ (code)
- `.github/workflows/cd-developer.yml`: `workflow_dispatch` with per-service branch inputs (`product_branch`, `cart_branch`, `tax_branch`, …), `developer_profile` (lean/full), and an `action` = deploy/cleanup. Defaults to `main`. Matches the spec scenario (deploy one branch, rest default). NodePort output path present.

## 4. Delete Deployment Job — ✅ (code, with caveat)
- Implemented as the `cleanup` choice in `cd-developer.yml` (not a separate Jenkins job). Problem text says "Jenkins job," but the assignment allows GitHub Actions **or** Jenkins, so this is acceptable. **No Jenkins/Jenkinsfile exists in the repo** — everything is GitHub Actions.

## 5. Dev & Staging — ⚠️ BROKEN LIVE
- `.github/workflows/deploy-dev.yml`: triggers on `push` to `main` → builds + deploys to `dev`. ✅ trigger correct.
- `.github/workflows/deploy-staging.yml`: triggers on `push` tags `v*` → `staging`. ✅ trigger correct.
- **Live state fails:**
  - `dev` ns: only `dev-yas-app-swagger-ui` pod, **Pending**, `health=Degraded`.
  - `staging` ns: only `staging-yas-app-swagger-ui` pod, **Pending**, `health=Degraded`.
  - Root cause (from `kubectl describe`):
    ```
    Failed to apply default image tag "DOCKERHUB_USERNAME/yas-swagger-ui:main":
    repository name must be lowercase
    ```
  - The Helm values feeding the ArgoCD apps still contain the literal placeholder `DOCKERHUB_USERNAME`, and the apps render **only swagger-ui** (not the full 14-service umbrella). → **dev/staging environments are non-functional.**

---

## Advanced 1: ArgoCD — ⚠️ PARTIAL
- ArgoCD **installed & healthy** in `argocd` ns (server, repo-server, app-controller, applicationset, dex, redis, notifications — all Running).
- Two Applications exist:
  - `dev-yas-app` → `sync=Synced health=Degraded`
  - `staging-yas-app` → `sync=Synced health=Degraded`
- Apps point at `github.com/23122004/Y3S2-DevOps` path `k8s/charts/yas-umbrella` with per-env value files, `automated` sync (prune + selfHeal), `CreateNamespace=true`.
- **Gap:** synced but Degraded (same `DOCKERHUB_USERNAME` placeholder + only swagger-ui). ArgoCD plumbing is done; the delivered app is broken. Not fully credit-worthy until images resolve and the full app renders.

---

## Advanced 2: Service Mesh — ✅ FULLY LIVE

Istio control plane live in `istio-system`: `istiod`, `istio-ingressgateway` (LoadBalancer), `istio-egressgateway`, `kiali`, `prometheus` — all Running.

| Requirement | Live evidence |
|-------------|---------------|
| **mTLS (STRICT)** | `PeerAuthentication default-strict-mtls MODE=STRICT` in `yas` (also dev/staging/yas-developer in manifests). All 14 `yas` pods are **2/2** = Envoy sidecar injected. Public entrypoints (storefront-bff, backoffice-bff, swagger-ui) intentionally PERMISSIVE. |
| **Authorization Policy** | `AuthorizationPolicy product-allow-callers` (ALLOW-list of SPIFFE principals: order, cart, search, storefront-bff, backoffice-bff). Tested: SA=order → 404 (reached app, allowed); SA=default → **403 RBAC: access denied** with matching Envoy `rbac_access_denied` log. |
| **Retry policy** | `VirtualService` `order-retry`, `tax-retry`, `httpbin-retry` — `attempts:3`, `retryOn: 5xx,reset,connect-failure`. Tested: 1 client call to `/status/500` → **4 backend hits** (1 + 3 retries). |
| **Kiali topology** | `kiali` pod Running, `kiali` ClusterIP svc present (port-forward 20001). Evidence: 30 nodes / 16 edges graph for `yas`. |
| DestinationRules | Present in `k8s/istio/destination-rules.yaml`. |

Evidence captured in `docs/service-mesh-test-evidence.txt` and reproduce steps in `docs/worklog-2026-07-05.md` §9.

---

## Core 14 Services — ✅ ALL LIVE (in `yas` ns)

All Running **2/2** (app + istio sidecar):
`product, cart, order, customer, inventory, tax, media, search, storefront-bff, storefront-ui, backoffice-bff, backoffice-ui, swagger-ui, sampledata`.
Plus mesh demo infra: `httpbin`, `mesh-tester-order`, `mesh-tester-default`, `yas-reloader`.

> The live shop runs in **`yas`** (deployed via Helm scripts), **separate** from the broken ArgoCD `dev`/`staging` apps. If the grader expects the full app in `dev`/`staging`, that mapping is not satisfied.

---

## Observability — ⚠️ DEPLOYED BUT NOT LIVE (out of scope)

Problem explicitly states "No need to deploy Grafana and Prometheus." Current state:
- Full LGTM+Prom stack **installed** in `observability` ns (grafana, loki read/write/backend/minio, tempo, prometheus, alertmanager, otel-collector/operator, grafana-operator).
- **All core components scaled to `desired=0`** → not running. Only lightweight agents up: `promtail` (3), `node-exporter` (3), `loki-canary` (3).
- Separate `prometheus` in `istio-system` **is** running (backs Kiali).
- Matches worklog cost note (scale down heavy observability after demo). **Dashboards/traces/metrics are NOT queryable right now.** Spin components back up before any observability demo.

---

## Gaps to Close

1. **Fix ArgoCD dev/staging images** — substitute real Docker Hub username for `DOCKERHUB_USERNAME` in `k8s/environments/{dev,staging}/values.yaml`; make the umbrella render all 14 services, not just swagger-ui. This unblocks base req 5 **and** Advanced 1.
2. **Decide dev/staging vs `yas`** — the live app lives in `yas`; base req wants `dev`/`staging`. Align.
3. **(Optional) Observability** — scale the `observability` stack back up if it must be demoed; otherwise out of scope.
4. **(Cosmetic) Jenkins** — spec names Jenkins for delete/dev/staging; implementation is GitHub Actions. Allowed, but note in report.
