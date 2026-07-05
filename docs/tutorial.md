# Tutorial: Hoàn thành phần Service Mesh của Huy (YAS trên DigitalOcean)

> Tài liệu này viết cho **Huy** — người phụ trách phần **Service Mesh** (`docs/huy_job.md`).
> Mục tiêu: (1) hiểu nhóm đã làm tới đâu, (2) biết chính xác mình cần làm gì & học được gì,
> (3) xử lý các vấn đề còn tồn đọng của project.
>
> Toàn bộ số liệu dưới đây được **kiểm chứng trực tiếp** trên cluster DigitalOcean (DOKS) ngày `2026-07-05`
> bằng `kubectl` với file `teammate-kubeconfig.yaml`.

---

## 0. TL;DR (đọc cái này trước)

| Hạng mục | Trạng thái | Ai làm |
|----------|-----------|--------|
| K8s cluster (DOKS 2 node) | ✅ Chạy | Nhóm/hạ tầng |
| CI per-branch → Docker Hub | ✅ (theo docs) | Khoa |
| CD: developer_build / dev / staging / delete | ✅ (theo docs) | Khoa |
| ArgoCD GitOps (dev, staging) | ⚠️ Synced nhưng **Degraded** | Khoa |
| Istio cài đặt (istiod, gateway) | ✅ | Partner B |
| mTLS STRICT (PeerAuthentication) | ✅ | Partner B |
| DestinationRule ISTIO_MUTUAL | ✅ | Partner B |
| VirtualService **retry** (tax, order) | ✅ | Partner B |
| **AuthorizationPolicy** | ❌ **CHƯA CÓ** (`No resources found`) | **← Huy** |
| **Kiali** (cài + topology) | ❌ **CHƯA CÓ** | **← Huy** |
| **Test plan + logs** (allow/deny/retry) | ❌ **CHƯA CÓ** | **← Huy** |

**Việc của Huy = 3 thứ đang ❌ ở trên.** Phần mesh nền tảng (mTLS, retry) đã có sẵn, Huy build tiếp lên trên.

> ⚠️ **Bẫy lớn**: File thiết kế `docs/implementation-spec.md` (mục 10.5) viết AuthorizationPolicy dùng
> `matchLabels: app: product` và port `8080`. **Cả hai đều SAI so với cluster thật.** Cluster thật dùng label
> `app.kubernetes.io/name: product` và service port `80` / `8090`. Mục 4 bên dưới đã sửa đúng — dùng bản của tutorial này.

---

## 1. Truy cập cluster (làm 1 lần)

Cluster là **DigitalOcean Kubernetes (DOKS)**, region `sgp1`. Kubeconfig đã có sẵn trong repo.

```bash
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps

# Trỏ kubectl tới cluster của nhóm (chạy mỗi terminal mới, hoặc thêm vào ~/.zshrc)
export KUBECONFIG=$PWD/teammate-kubeconfig.yaml

# Kiểm tra kết nối
kubectl get nodes
```

Kỳ vọng: 2 node `Ready`, version `v1.36.0`.

```
NAME                            STATUS   ROLES    AGE   VERSION
devops-project02-large-3cw2n7   Ready    <none>   9d    v1.36.0
devops-project02-large-3cw2nm   Ready    <none>   9d    v1.36.0
```

### Cài công cụ còn thiếu

Máy Huy đã có `kubectl` + `helm v3.21`. **Thiếu `istioctl`** (rất cần cho Kiali dashboard + kiểm tra proxy):

```bash
# Cài istioctl khớp version cluster (istiod đang chạy 1.30.2)
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.30.2 sh -
sudo mv istio-1.30.2/bin/istioctl /usr/local/bin/
istioctl version    # nên hiển thị client + control plane 1.30.2
```

`doctl` (CLI DigitalOcean) **không bắt buộc** — mọi thứ có thể xem qua `kubectl` hoặc GUI web DO.

---

## 2. PHẦN A — Nhóm đã làm những gì (đã kiểm chứng)

### 2.1 Hạ tầng Kubernetes trên DigitalOcean

**Kiểm tra bằng CLI:**
```bash
kubectl get nodes -o wide
kubectl get ns
```

- Cluster DOKS 2 worker node (`large`), Cilium CNI, containerd runtime.
- Có sẵn 19 namespace: `argocd`, `istio-system`, `cert-manager`, `ingress-nginx`,
  `dev`, `staging`, `yas`, `yas-developer`, `kafka`, `keycloak`, `elasticsearch`,
  `postgres`, `redis`, `observability`, `zookeeper`, ...

**Kiểm tra trên GUI DigitalOcean** (web console):
1. Đăng nhập https://cloud.digitalocean.com → menu trái **Kubernetes** → cluster `devops-project02`.
2. Tab **Overview**: xem node pool, region `SGP1`, version.
3. Tab **Insights**: xem CPU/memory từng node (dùng để chẩn đoán pod Pending — xem Phần C).
4. Menu **Networking → Load Balancers**: thấy 2 LB (istio-ingressgateway + ingress-nginx).
   - `ingress-nginx` EXTERNAL-IP = `129.212.208.194`
   - `istio-ingressgateway` EXTERNAL-IP = `168.144.48.115`

### 2.2 CI/CD & GitOps (phần của Khoa)

Theo `docs/khoa-ci-cd-service-mesh.md` + commit history:
- **CI**: mỗi branch commit → build image tag = commit-id → push Docker Hub.
- **CD**: `developer_build` (deploy 1 branch tùy chọn), auto-deploy `dev`, release `staging` theo tag `vX.Y.Z`, job delete.
- **ArgoCD GitOps**: 2 Application quản lý dev & staging.

**Kiểm tra:**
```bash
kubectl get applications -n argocd
```
```
NAME              SYNC STATUS   HEALTH STATUS
dev-yas-app       Synced        Degraded
staging-yas-app   Synced        Degraded
```
> `Synced` = ArgoCD đã apply đúng git. `Degraded` = pod bên trong chưa healthy (xem Phần C — vấn đề tài nguyên, không phải lỗi cấu hình của Huy).

### 2.3 Service Mesh — phần Partner B đã làm xong

Namespace `yas`, `dev`, `staging` đã bật **auto sidecar injection**:
```bash
kubectl get ns yas dev staging yas-developer --show-labels
# yas/dev/staging: istio-injection=enabled  | yas-developer: disabled
```

Pod đang chạy có **2/2 container** = app + `istio-proxy` (Envoy sidecar). Ví dụ:
```bash
kubectl get pods -n yas
# search-cc8d449bc-sx9sc   2/2   Running   ← có sidecar
```

**(a) mTLS STRICT** — `PeerAuthentication`:
```bash
kubectl get peerauthentication -A
```
```
yas       default-strict-mtls                STRICT       ← toàn namespace ép mTLS
yas       storefront-bff-public-entrypoint   PERMISSIVE   ← chừa cổng public cho NGINX Ingress
yas       backoffice-bff-public-entrypoint   PERMISSIVE
yas       swagger-ui-public-entrypoint       PERMISSIVE
dev       default-strict-mtls                STRICT
staging   default-strict-mtls                STRICT
```

**(b) DestinationRule ISTIO_MUTUAL** cho 10 service:
```bash
kubectl get destinationrule -n yas
# cart / customer / inventory / media / order / product / search / tax / *-bff → *-istio-mutual
```

**(c) VirtualService retry** cho `tax` và `order`:
```bash
kubectl get virtualservice -n yas
kubectl get virtualservice -n yas tax-retry -o yaml
```
`tax-retry`: `attempts: 3, perTryTimeout: 5s, retryOn: 5xx,reset,connect-failure,retriable-4xx`.
`order-retry`: `attempts: 3, perTryTimeout: 10s, retryOn: 5xx,reset,connect-failure`.

> 📁 Các file YAML nguồn nằm ở `k8s/istio/` (`peer-authentication.yaml`, `destination-rules.yaml`,
> `virtual-services.yaml`, `public-entrypoints.yaml`, `install-istio.sh`, `README.md`).

---

## 3. PHẦN B — Việc của Huy: tổng quan & mục đích học tập

Từ `docs/huy_job.md`, Huy làm **4 việc** (đối chiếu checklist đề bài mục "Advanced 2"):

| # | Việc | File deliverable | Học được gì |
|---|------|------------------|-------------|
| B1 | **AuthorizationPolicy** — chỉ cho service được phép gọi nhau | `k8s/istio/authorization-policies.yaml` | Zero-trust, SPIFFE identity, RBAC L7 trong mesh |
| B2 | **Kiali** — cài + expose dashboard + chụp topology | screenshot vào `screenshots/` | Quan sát service graph, verify mTLS bằng mắt |
| B3 | **Test plan** — kịch bản curl từ pod | `docs/mesh-test-plan.md` | Thiết kế test cho policy mạng |
| B4 | **Chạy test + thu log** — allow / deny / retry | `docs/mesh-test-results.md` + screenshot | Đọc log Envoy, chứng minh policy hoạt động |

Mỗi phần chi tiết ở mục 4–7.

---

## 4. B1 — AuthorizationPolicy (việc chính, làm trước)

### 4.1 Ý tưởng & mục đích học tập

**Vấn đề học**: mTLS (đã có) chỉ đảm bảo *mã hóa + xác thực danh tính*, nó **KHÔNG giới hạn ai được gọi ai**.
Mọi service vẫn gọi được mọi service. `AuthorizationPolicy` là lớp **RBAC ở tầng 7** dùng danh tính
**SPIFFE** (`cluster.local/ns/<namespace>/sa/<serviceaccount>`) mà mTLS cung cấp để nói:
"chỉ `order` mới được gọi `tax`, còn lại **403**".

→ Huy học được: mô hình **zero-trust networking**, cách Istio map ServiceAccount → SPIFFE identity, cơ chế
allow/deny của Envoy RBAC filter.

### 4.2 Điều kiện cần — ĐÃ SẴN

AuthorizationPolicy theo danh tính cần **mỗi service có ServiceAccount riêng**. Kiểm tra:
```bash
kubectl get sa -n yas
# order, product, tax, search, cart, customer, inventory, media, storefront-bff, backoffice-bff ... ✅ đủ
```
Pod đang chạy đã gắn đúng SA (ví dụ pod `search` dùng `serviceAccountName: search`). ✅ Không cần sửa Deployment.

### 4.3 ⚠️ Sửa lỗi thiết kế trước khi viết manifest

Manifest mẫu trong `implementation-spec.md` dùng `app: product` và port `8080`.
**Cluster thật khác:**
```bash
kubectl get pod -n yas search-cc8d449bc-sx9sc -o jsonpath='{.metadata.labels}'
# → app.kubernetes.io/name=search   (KHÔNG có label "app")
kubectl get svc -n yas
# → port 80 (http chính) và 8090 (management/actuator)
```
Vậy selector đúng là **`app.kubernetes.io/name: <svc>`**, port đúng là **80** (hoặc 8090 cho `/actuator/health`).

### 4.4 Chiến lược an toàn (QUAN TRỌNG — đừng phá app đang chạy)

Đề bài gợi ý `deny-all` toàn namespace. **KHÔNG nên** chạy `deny-all` trên namespace `yas` đang chạy thật —
nó sẽ chặn luôn traffic hợp lệ (BFF → backend, ingress → BFF) và làm sập cả shop.

**Cách khuyến nghị (không phá app):** dùng **ALLOW policy nhắm vào 1 workload** (ví dụ `tax`).
Trong Istio, khi một workload có ít nhất 1 ALLOW policy, mọi nguồn **không nằm trong danh sách sẽ bị chặn**
tự động — tức là "implicit deny" chỉ cho riêng workload đó, không đụng phần còn lại.

→ Demo sạch: `order → tax` (ALLOW) vs `search → tax` (DENY 403), mà `product`, `cart`, storefront vẫn sống.

### 4.5 Manifest — tạo file `k8s/istio/authorization-policies.yaml`

```yaml
# ── Demo 1: chỉ order (và backoffice-bff) được gọi TAX ──────────────
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-order-to-tax
  namespace: yas
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: tax      # ⚠️ label THẬT, không phải "app: tax"
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/yas/sa/order"
              - "cluster.local/ns/yas/sa/backoffice-bff"
---
# ── Demo 2: chỉ search + BFF được gọi PRODUCT ───────────────────────
# (khớp kịch bản đề bài "search depends on product")
apiVersion: security.istio.io/v1
kind: AuthorizationPolicy
metadata:
  name: allow-callers-to-product
  namespace: yas
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: product
  action: ALLOW
  rules:
    - from:
        - source:
            principals:
              - "cluster.local/ns/yas/sa/search"
              - "cluster.local/ns/yas/sa/storefront-bff"
              - "cluster.local/ns/yas/sa/backoffice-bff"
              - "cluster.local/ns/yas/sa/cart"
              - "cluster.local/ns/yas/sa/order"
```

> 💡 Nếu muốn demo **đúng chữ đề bài** "chỉ order được gọi product, chặn còn lại": bỏ `search` khỏi danh sách
> Demo 2. Nhưng nhớ điều đó **làm hỏng chức năng search thật** → chỉ bật lúc quay demo rồi xóa. An toàn nhất là
> demo trên `tax` (Demo 1).

**Apply:**
```bash
kubectl apply -f k8s/istio/authorization-policies.yaml
kubectl get authorizationpolicy -n yas
```

### 4.6 (Tùy chọn) Demo `deny-all` sạch trong namespace riêng
Nếu muốn thể hiện `deny-all` mà không sợ hỏng: tạo namespace `mesh-demo`, bật injection, deploy 2 pod nhỏ
(`sleep` + `httpbin`), rồi apply `deny-all` + 1 allow rule. An toàn tuyệt đối, không đụng `yas`.

---

## 5. B2 — Cài Kiali & chụp topology

### 5.1 Mục đích học tập
Kiali = **bản đồ trực quan** của mesh: nhìn thấy service gọi nhau ra sao, mTLS có bật không (biểu tượng ổ khóa),
tỉ lệ lỗi, và **AuthorizationPolicy chặn ở đâu** (mũi tên đỏ). Đây là cách chứng minh trực quan cho giám khảo.

### 5.2 Cài Kiali + Prometheus (Kiali cần Prometheus để có số liệu)
```bash
# addon khớp dòng minor của Istio (1.30 dùng nhánh release-1.30)
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/prometheus.yaml
kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.30/samples/addons/kiali.yaml

kubectl rollout status deployment/kiali -n istio-system --timeout=5m
kubectl get pods -n istio-system | grep -E 'kiali|prometheus'
```

### 5.3 Mở dashboard
```bash
# Cách 1 (gọn nhất, cần istioctl):
istioctl dashboard kiali

# Cách 2 (không cần istioctl):
kubectl port-forward -n istio-system svc/kiali 20001:20001
# rồi mở http://localhost:20001
```

### 5.4 Chụp topology
1. Trong Kiali: menu **Graph** → chọn Namespace `yas`.
2. Bật hiển thị: **Display → Security** (hiện ổ khóa mTLS) + **Traffic Animation**.
3. Sinh traffic để đồ thị có dữ liệu (mở storefront qua ingress, hoặc curl nội bộ — xem Phần 6).
4. Chụp màn hình → lưu vào `screenshots/kiali-topology-yas.png`.
5. Chụp thêm 1 ảnh sau khi apply AuthorizationPolicy để thấy đường bị chặn (mũi tên đỏ / 403).

> Giải thích trong report: các mũi tên = luồng request; ổ khóa = mTLS đang mã hóa; badge màu = health/tỉ lệ lỗi.

---

## 6. B3 — Test plan (tạo file `docs/mesh-test-plan.md`)

Ý tưởng: từ **bên trong 1 pod** (dùng sidecar mesh), curl sang service khác để kiểm chứng policy.
Dùng port **80** (service thật) hoặc `8090/actuator/health`.

| TC | Từ pod | Tới | Kỳ vọng | Chứng minh |
|----|--------|-----|---------|-----------|
| TC1 mTLS | bất kỳ | bất kỳ | 200, có mTLS | sidecar + PeerAuthentication |
| TC2 allow | `order` | `tax` | **200** | AuthorizationPolicy cho phép |
| TC3 deny | `search` | `tax` | **403 RBAC: access denied** | AuthorizationPolicy chặn |
| TC4 retry | client | `tax` khi 500 | thấy `x-envoy-attempt-count` > 1 | VirtualService retry |

**Lệnh mẫu (đưa vào test plan):**
```bash
# TC2 — ALLOW: order → tax  (kỳ vọng 200)
kubectl exec -n yas deploy/order -c order -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://tax.yas.svc.cluster.local/actuator/health

# TC3 — DENY: search → tax  (kỳ vọng 403)
kubectl exec -n yas deploy/search -c search -- \
  curl -s -o /dev/null -w "%{http_code}\n" http://tax.yas.svc.cluster.local/actuator/health
# hoặc -v để thấy dòng "RBAC: access denied"
```
> Nếu image service **không có `curl`**, deploy 1 pod client có SA tương ứng:
> ```bash
> kubectl run tester --image=curlimages/curl -n yas --overrides='{"spec":{"serviceAccountName":"search"}}' -it --rm -- sh
> ```

---

## 7. B4 — Chạy test & thu log (tạo `docs/mesh-test-results.md`)

Chạy từng TC ở mục 6, **lưu output đầy đủ** (kèm `-v`), và screenshot.

**Log DENY cần bắt được dòng:**
```
< HTTP/1.1 403 Forbidden
RBAC: access denied
```

**Chứng minh RETRY** — dùng Envoy access log của sidecar phía **client** (upstream) hoặc `tax`:
```bash
# 1) Ép tax trả 500: hoặc dùng Fault Injection tạm trên VirtualService,
#    hoặc gọi endpoint lỗi. Cách nhanh nhất: thêm fault abort 500 vào tax-retry tạm thời.
# 2) Bắn request rồi xem attempt-count trong log Envoy:
kubectl logs -n yas deploy/order -c istio-proxy --tail=50 | grep -i "attempt"
# Kỳ vọng: x-envoy-attempt-count = 2, 3 (Envoy tự retry theo VirtualService)
```
> Cách gọn để chứng minh retry mà không cần app lỗi thật: tạm thêm `fault.abort` (percentage 50, httpStatus 500)
> vào `tax-retry`, curl vài lần, quan sát Envoy retry rồi **gỡ fault ra**.

**Deliverables cuối (khớp checklist đề bài mục 10.5 spec):**
- [ ] `k8s/istio/authorization-policies.yaml` (deny/allow)
- [ ] `screenshots/kiali-topology-yas.png` (+ ảnh sau khi chặn)
- [ ] `docs/mesh-test-plan.md`
- [ ] `docs/mesh-test-results.md` (log allow / deny 403 / retry attempt-count)

---

## 8. PHẦN C — Vấn đề còn tồn tại & cách xử lý

### C1. Nhiều pod `yas` đang crash 🔴
```bash
kubectl get pods -n yas
```
Hiện trạng: `product`, `tax`, `order`, `media`, `customer`, `inventory` ở trạng thái
`CrashLoopBackOff` / `Error` / `ContainerStatusUnknown`, số lần restart rất cao (1000+).

**Nguyên nhân (đã điều tra):**
1. **Không kết nối được PostgreSQL** — log `product` cho thấy lỗi ở
   `org.postgresql.core...enableSSL` (SSL handshake tới `postgresql-0` fail hoặc timeout).
2. **`ContainerStatusUnknown` tập trung ở node `3cw2nm`** — dấu hiệu node từng bị eviction/restart, pod cũ mồ côi.
3. Cụm chỉ **2 node** nhưng gánh `yas` + `dev` + `staging` + Kafka + Keycloak + ES → thiếu tài nguyên.

**Cách xử lý (không bắt buộc với job của Huy, nhưng cần vài service sống để demo đẹp):**
```bash
# Xóa pod mồ côi (ContainerStatusUnknown/Error) để scheduler tạo lại
kubectl delete pod -n yas --field-selector status.phase=Failed

# Kiểm tra postgres sống & service backend nối được
kubectl get pods -n postgres
kubectl logs -n yas deploy/product -c product --tail=30   # xem còn lỗi SSL không

# Nếu do SSL: kiểm tra biến JDBC (sslmode) trong ConfigMap/Secret của service
kubectl get cm -n yas | grep -i product
```
> Để demo mesh, chỉ cần **`order` + `tax` (hoặc `search` + `product`) chạy được**. Nếu không ổn định, có thể
> `kubectl scale deploy/<svc> --replicas=1` và chờ, hoặc demo trên các service đang `Running` (`search`, `cart`,
> `storefront-bff`, `backoffice-bff`, `swagger-ui`).

### C2. ArgoCD apps `Degraded`
```bash
kubectl get applications -n argocd
kubectl get pods -n dev; kubectl get pods -n staging   # nhiều pod Pending
```
Pod `Pending` = **không đủ CPU/RAM** để schedule (cùng nguyên nhân C1: 2 node quá tải). Config đúng (`Synced`),
chỉ là tài nguyên. Xử lý: tăng node pool trên DO, hoặc scale bớt namespace không dùng khi demo:
```bash
# Ví dụ tạm giảm tải khi cần demo yas:
kubectl scale deploy --all -n staging --replicas=0
```

### C3. Thiếu `istioctl` local
Đã nêu ở mục 1 — cài để dùng `istioctl dashboard kiali` và `istioctl proxy-config`.

### C4. Namespace không khớp giữa spec và thực tế
Spec viết `yas-dev` / `yas-staging`; cluster thật dùng `dev` / `staging` / `yas`. Khi copy lệnh từ
`implementation-spec.md`, **luôn đổi namespace về tên thật** và **label về `app.kubernetes.io/name`**.

---

## 9. Checklist thứ tự thực thi (copy-paste theo dõi)

```
[ ] 1. export KUBECONFIG=$PWD/teammate-kubeconfig.yaml ; kubectl get nodes
[ ] 2. Cài istioctl 1.30.2
[ ] 3. (C1) Dọn pod Failed, đảm bảo order+tax hoặc search+product Running
[ ] 4. (B1) Viết k8s/istio/authorization-policies.yaml (label app.kubernetes.io/name, ns yas)
[ ] 5. (B1) kubectl apply -f ... ; kiểm tra get authorizationpolicy -n yas
[ ] 6. (B2) Cài prometheus.yaml + kiali.yaml (nhánh release-1.30)
[ ] 7. (B2) istioctl dashboard kiali → chụp topology yas
[ ] 8. (B3) Viết docs/mesh-test-plan.md (TC1-TC4)
[ ] 9. (B4) Chạy TC2 allow(200), TC3 deny(403), TC4 retry(attempt-count)
[ ] 10.(B4) Lưu log + screenshot → docs/mesh-test-results.md
[ ] 11. Chụp lại Kiali sau khi chặn (mũi tên đỏ) cho report
[ ] 12. Commit: k8s/istio/authorization-policies.yaml + docs/* + screenshots/*
```

---

## 10. Phụ lục — Lệnh kiểm chứng nhanh

```bash
export KUBECONFIG=$PWD/teammate-kubeconfig.yaml

# Mesh đã có gì?
kubectl get peerauthentication,destinationrule,virtualservice,authorizationpolicy -A

# Pod có sidecar chưa? (cột READY phải là 2/2)
kubectl get pods -n yas

# Label & SA thật của 1 service (dùng khi viết policy)
kubectl get pod -n yas -l app.kubernetes.io/name=search -o jsonpath='{.items[0].spec.serviceAccountName}{"\n"}'

# Xem cấu hình RBAC mà Envoy nhận (debug policy)
istioctl proxy-config listener deploy/tax -n yas

# LB IP để truy cập ngoài
kubectl get svc -n ingress-nginx ingress-nginx-controller
kubectl get svc -n istio-system istio-ingressgateway
```

---

*Cập nhật: 2026-07-05. Số liệu lấy trực tiếp từ cluster `do-sgp1-...-1782356447895`.*
