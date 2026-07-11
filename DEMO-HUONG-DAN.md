# Hướng dẫn Demo YAS DevOps cho Thầy (Step-by-Step)

> Tài liệu này hướng dẫn bạn demo **toàn bộ** các yêu cầu trong `docs/context.md`
> theo đúng thứ tự 10 mục thầy yêu cầu. Mọi lệnh đã được kiểm chứng với cụm
> DOKS **live** vào **2026-07-11**. Đọc kỹ **Phần 0** trước — trong đó có
> **báo cáo tình trạng cụm hiện tại** và **3 quyết định bạn phải chốt** trước
> khi demo (vì hiện có vài thứ chưa sẵn sàng).

- **Repo:** https://github.com/23122004/Y3S2-DevOps (nhánh `main`)
- **Registry:** GHCR — `ghcr.io/23122004/yas-<service>` (KHÔNG dùng Docker Hub, xem mục 1)
- **Load Balancer IP:** `129.212.208.194`
- **Base domain:** `yas.local.com`
- **Cluster:** DOKS `k8s-1-36-0-do-1-sgp1-1782356447895` (region `sgp1`, 4 nodes `s-4vcpu-8gb`)

---

## Phần 0 — TÌNH TRẠNG CỤM & QUYẾT ĐỊNH BẮT BUỘC TRƯỚC KHI DEMO

### 0.1 Ảnh chụp tình trạng live (2026-07-11)

| Thành phần | Trạng thái | Demo được ngay? |
|---|---|---|
| 4 nodes DOKS | ✅ Ready | — |
| NGINX Ingress + LB `129.212.208.194` | ✅ Running | — |
| ArgoCD `dev-yas-app` | ✅ Synced / Healthy | ✅ Mục 6 |
| ArgoCD `staging-yas-app` | ✅ Synced / Healthy | ✅ Mục 6 |
| Namespace `dev` (14 service, 2/2 có sidecar) | ✅ Running | ✅ Mục 2, 3 |
| Namespace `staging` (14 service, 2/2 có sidecar) | ✅ Running | ✅ Mục 2, 3 |
| Istio control plane (`istiod`, gateways, `kiali`) | ✅ Running | ✅ (một phần) |
| Namespace `dev`/`staging` có sidecar (PERMISSIVE) | ✅ Running | ✅ nền cho mesh |
| **Mesh policy (STRICT/DR/VS/AuthZ)** | ⚠️ **Chưa áp** — áp lên `staging` qua Phần 1B | ⚠️ **Mục 7, 8, 9 cần chạy Phần 1B trước** |
| Namespace `yas` (thiết kế gốc) | ❌ Không dựng (tiết kiệm RAM) | — dùng `staging` thay thế |
| Grafana / Prometheus / Tempo | ✅ Running | ✅ Mục 10 (metric + trace) |
| **Loki (log)** | ⚠️ **`loki-write` CrashLoop** | ⚠️ **Mục 10: xem log KHÔNG chạy** |
| Namespace `yas-developer` | ❌ Không tồn tại (đúng, nó ephemeral) | ✅ tạo khi demo Mục 2/4 |

### 0.2 Ba quyết định BẠN phải chốt trước khi demo

> Tôi **không tự động sửa cụm** (theo yêu cầu của bạn). Dưới đây là vấn đề +
> phương án. Bạn quyết định rồi chạy lệnh tương ứng.

**QUYẾT ĐỊNH 1 — Cách demo Service Mesh (Mục 7, 8, 9). → ĐÃ CHỐT: áp lên `staging`.**
Namespace `yas` (nơi bật mTLS `STRICT` + retry + authz) đã bị xóa để tiết kiệm RAM.
Sau khi phân tích, nhóm **KHÔNG dựng lại `yas`** mà **áp trực tiếp bộ policy mesh
lên namespace `staging`** (giữ `dev` sạch cho demo ArgoCD/CI). Lý do:

- **Tài nguyên (yếu tố quyết định):** 4 node hiện dùng **94–106% RAM thực tế**
  (đã bão hòa — chính vì vậy Loki crash + ~90 pod bị Evicted). Dựng lại `yas`
  cần thêm ~15 pod JVM + sidecar (≈ +4–6 GB) → gần như chắc chắn OOM/eviction
  dây chuyền, có thể làm node `NotReady` (**đây mới là kịch bản dễ "sập server"**).
  Ngược lại, áp policy lên `staging` **không thêm pod nặng nào** (pod staging đã
  chạy 2/2 sẵn sidecar); Istio CR gần như miễn phí, chỉ thêm 2 pod tester + 1
  httpbin (~150 MB). **An toàn về RAM.**
- **Logic:** ArgoCD **không quản lý** resource Istio (umbrella chart không có
  manifest mesh) → `kubectl apply` policy vào staging **không bị selfHeal/prune
  revert**. staging có đủ ServiceAccount đúng tên (`order`, `cart`, ...) nên authz
  chạy đúng. Rủi ro gói gọn trong staging, không đụng tới `dev` (môi trường demo CI/CD).

Bộ manifest đã retarget `yas → staging` nằm ở **`k8s/istio/staging-demo/`** (đã
validate bằng server dry-run). Cách áp: xem
[Phần 1B](#phần-1b--áp-mesh-lên-namespace-staging-bắt-buộc-cho-mục-7-8-9).

> Phương án dự phòng nếu không muốn đụng staging: demo bằng file YAML +
> báo cáo `docs/huy-service-mesh-report.md` (đã test, có Kiali graph 30 node).

**QUYẾT ĐỊNH 2 — Loki (log) đang hỏng (ảnh hưởng Mục 10).**
`loki-write-0` CrashLoopBackOff suốt 3 ngày với lỗi
`failed to flush chunks: store put chunk: mkdir fake: read-only file system`
→ backend object-storage (`loki-minio`) không hoạt động, nên **truy vấn log
trong Grafana sẽ trống**. Metric (Prometheus) và Trace (Tempo) **vẫn hoạt động bình thường**.

- **Phương án A (khuyến nghị): Demo Mục 10 với Metric + Trace**, và nói rõ log
  pipeline (Promtail → Loki) có kiến trúc đầy đủ nhưng backend storage đang lỗi
  trên cụm lab. Đủ để chứng minh observability.
- **Phương án B: Sửa Loki trước.** Cần redeploy `loki` (khôi phục `loki-minio`).
  Đây là thao tác Helm không nhỏ, nên chỉ làm nếu bạn có thời gian. Xem
  [mục 10.4](#104-nếu-muốn-sửa-loki-tùy-chọn).

👉 **Khuyến nghị A** (an toàn cho buổi demo).

**QUYẾT ĐỊNH 3 — Dọn rác cosmetic (không bắt buộc nhưng nên làm).**
`istio-system` có ~90 pod `Evicted` của Prometheus cũ + `dev` có 1 pod `order`
`ContainerStatusUnknown`. Vô hại nhưng nhìn xấu khi `kubectl get pods`. Nên dọn
trước để screenshot đẹp:

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
kubectl delete pod -n istio-system --field-selector=status.phase=Failed
kubectl delete pod -n istio-system --field-selector=status.phase=Succeeded
kubectl delete pod -n dev --field-selector=status.phase=Failed
```

---

## Phần 1A — CHUẨN BỊ MÁY DEMO (làm 1 lần)

### Bước 1 — Mở terminal & trỏ kubeconfig

Mọi terminal demo phải bắt đầu bằng dòng này (dùng **đường dẫn tuyệt đối**,
nếu dùng `$PWD` sẽ lỗi `connection refused localhost:8080`):

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
kubectl config current-context
# kỳ vọng: do-sgp1-k8s-1-36-0-do-1-sgp1-1782356447895
```

### Bước 2 — Cấu hình `/etc/hosts` (RẤT QUAN TRỌNG cho Mục 3)

Tất cả tên miền `*.yas.local.com` đều trỏ về **cùng 1 IP Load Balancer**
(`129.212.208.194`). Trình duyệt/`curl` phân biệt dịch vụ bằng **tên miền**
(Host header), còn NGINX Ingress định tuyến dựa trên đó.

Mở file hosts bằng quyền admin:

```bash
sudo nano /etc/hosts        # Linux/macOS
# Windows: mở Notepad bằng Administrator, sửa C:\Windows\System32\drivers\etc\hosts
```

Dán khối sau vào cuối file rồi lưu:

```text
129.212.208.194 argocd.yas.local.com
129.212.208.194 grafana.yas.local.com
129.212.208.194 kiali.yas.local.com
129.212.208.194 pgadmin.yas.local.com
129.212.208.194 kibana.yas.local.com
129.212.208.194 akhq.yas.local.com
129.212.208.194 identity.yas.local.com
129.212.208.194 storefront.dev.yas.local.com
129.212.208.194 backoffice.dev.yas.local.com
129.212.208.194 api.dev.yas.local.com
129.212.208.194 storefront.staging.yas.local.com
129.212.208.194 backoffice.staging.yas.local.com
129.212.208.194 api.staging.yas.local.com
129.212.208.194 developer.yas.local.com
129.212.208.194 backoffice-developer.yas.local.com
129.212.208.194 api-developer.yas.local.com
129.212.208.194 storefront.yas.local.com
129.212.208.194 backoffice.yas.local.com
129.212.208.194 api.yas.local.com
```

Kiểm tra đã ăn DNS local:

```bash
getent hosts storefront.dev.yas.local.com     # phải in ra 129.212.208.194
```

> **Giải thích cho thầy (Mục 3):** "Em không mua domain thật. Em ánh xạ các
> subdomain `*.yas.local.com` về IP của DigitalOcean Load Balancer ngay trong
> file `/etc/hosts` của máy. Khi trình duyệt gọi `storefront.dev.yas.local.com`,
> DNS local trả về IP LB, request đi tới NGINX Ingress Controller, và Ingress
> dựa vào Host header để route đúng tới service `storefront-bff` trong namespace `dev`."

### Bước 3 — Health check toàn hệ thống (chạy đầu buổi demo)

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml

echo "### Nodes"
kubectl get nodes -o wide
echo "### ArgoCD apps (phải Synced/Healthy)"
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{" sync="}{.status.sync.status}{" health="}{.status.health.status}{"\n"}{end}'
echo "### dev / staging pods"
kubectl get pods -n dev  --no-headers | awk '{print $1,$2,$3}'
kubectl get pods -n staging --no-headers | awk '{print $1,$2,$3}'
echo "### Endpoint HTTP codes"
LB_IP=129.212.208.194
for host in argocd.yas.local.com grafana.yas.local.com kiali.yas.local.com \
            storefront.dev.yas.local.com storefront.staging.yas.local.com; do
  code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H "Host: $host" "http://$LB_IP/")
  printf '%-40s %s\n' "$host" "$code"
done
```

Kỳ vọng: 4 node `Ready`; 2 app ArgoCD `Synced/Healthy`; các endpoint trả `200`
hoặc `302` (302 = redirect tới trang login, vẫn là "sống").

---

## Phần 1B — ÁP MESH LÊN NAMESPACE `staging` (bắt buộc cho Mục 7, 8, 9)

> Áp bộ policy mesh (đã retarget `yas → staging`) lên namespace `staging` có sẵn.
> **Không thêm pod nặng, không đụng `dev`.** Nên chạy **trước buổi demo ~5 phút**.
> Toàn bộ file nằm ở `k8s/istio/staging-demo/`, đã validate bằng server dry-run.

**Bước 1 — Áp mTLS STRICT + client mTLS + retry + authz lên staging:**

```bash
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml

# (a) đảm bảo 3 override PERMISSIVE cho BFF/swagger có mặt (chống chặn ingress)
kubectl apply -f k8s/istio/staging-demo/public-entrypoints-staging.yaml
# (b) DestinationRule: client tự khởi tạo mTLS (ISTIO_MUTUAL) khi gọi service nội bộ
kubectl apply -f k8s/istio/staging-demo/destination-rules-staging.yaml
# (c) VirtualService retry (tax-retry, order-retry)
kubectl apply -f k8s/istio/staging-demo/virtual-services-staging.yaml
# (d) AuthorizationPolicy (product chỉ nhận từ order/cart/search/2 BFF)
kubectl apply -f k8s/istio/staging-demo/authorization-policies-staging.yaml
# (e) CUỐI CÙNG mới flip namespace sang STRICT (làm sau (a)-(d) để tránh gián đoạn)
kubectl apply -f k8s/istio/staging-demo/peer-authentication-staging-strict.yaml
```

**Bước 2 — Kiểm chứng đã áp và app vẫn khỏe (QUAN TRỌNG — làm ngay để bắt lỗi sớm):**

```bash
kubectl get peerauthentication -n staging    # default-strict-mtls = STRICT + 3 entrypoint PERMISSIVE
kubectl get destinationrule    -n staging    # 10 rule ISTIO_MUTUAL
kubectl get virtualservice     -n staging    # tax-retry, order-retry
kubectl get authorizationpolicy -n staging   # product-allow-callers

# App vẫn truy cập được qua ingress? (STRICT không được làm hỏng cái này)
LB_IP=129.212.208.194
curl -s -o /dev/null -w 'storefront.staging = %{http_code}\n' -H 'Host: storefront.staging.yas.local.com' http://$LB_IP/
# ArgoCD staging phải vẫn Healthy (authz không làm product Degraded)
kubectl get application staging-yas-app -n argocd \
  -o jsonpath='{.status.sync.status}/{.status.health.status}{"\n"}'
```

> **Nếu `storefront.staging` KHÔNG trả 200 hoặc ArgoCD báo Degraded** → rollback
> ngay (xem Phần 1C) rồi báo lại. Đừng demo khi staging đang hỏng.

**Bước 3 — Triển khai pod test + backend retry (dùng cho Mục 9):**

```bash
kubectl apply -f k8s/istio/staging-demo/demo/mesh-test-clients-staging.yaml
kubectl apply -f k8s/istio/staging-demo/demo/retry-demo-httpbin-staging.yaml
kubectl wait --for=condition=ready pod -n staging -l app=mesh-tester --timeout=120s
kubectl get pod -n staging -l app=mesh-tester   # mesh-tester-order & -default phải 2/2
```

---

## Phần 1C — ROLLBACK staging về trạng thái ban đầu (sau demo hoặc khi lỗi)

```bash
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml

# 1) đưa staging về PERMISSIVE (mở lại như cũ) TRƯỚC
kubectl apply -f k8s/istio/staging-demo/peer-authentication-staging-permissive-ROLLBACK.yaml
# 2) xóa các policy/tài nguyên demo
kubectl delete -f k8s/istio/staging-demo/demo/ --ignore-not-found
kubectl delete -f k8s/istio/staging-demo/authorization-policies-staging.yaml --ignore-not-found
kubectl delete -f k8s/istio/staging-demo/virtual-services-staging.yaml --ignore-not-found
kubectl delete -f k8s/istio/staging-demo/destination-rules-staging.yaml --ignore-not-found
# (public-entrypoints giữ nguyên — vốn đã tồn tại từ trước)

# 3) xác nhận staging về như cũ
kubectl get peerauthentication,destinationrule,virtualservice,authorizationpolicy -n staging
```

---

## MỤC 1 — CI: Trigger commit → Build → Push GHCR với tag = commit SHA

**Mục tiêu:** Cho thầy thấy CI (Continuous Integration) tự chạy khi push code,
build bằng Maven, đóng Docker image, đẩy lên registry với tag trùng commit SHA.

**Nói thật với thầy về việc đổi registry:**
> "Đề gợi ý Docker Hub, nhưng nhóm em **chuyển sang GHCR (`ghcr.io/23122004/yas-*`)**
> vì hai lý do: (1) Docker Hub có rate-limit pull rất gắt gây fail deploy;
> (2) GHCR tích hợp sẵn với GitHub — workflow xác thực bằng `GITHUB_TOKEN` built-in,
> không cần tạo secret ngoài, phân quyền `packages: write` theo repo, bảo mật tốt hơn.
> Hai secret `DOCKERHUB_*` cũ giờ không còn dùng."

### Cách demo (kết hợp Web + CLI)

**Bước 1 — Tạo commit nhỏ trên nhánh feature và push:**

```bash
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps
git checkout -b demo_ci_tax
# sửa 1 dòng nhỏ, ví dụ thêm comment vào một file thuộc service tax
echo "// demo CI $(date)" >> tax/src/main/java/... # (chọn file bất kỳ, hoặc sửa README)
git commit -am "feat(tax): demo CI trigger"
git push origin demo_ci_tax
```

**Bước 2 — Cho thầy xem pipeline chạy (Web GitHub — trực quan nhất):**
Mở https://github.com/23122004/Y3S2-DevOps/actions → chọn workflow **CI**
(`ci.yml`) → click run mới nhất của nhánh `demo_ci_tax`. Chỉ cho thầy:
- Matrix build **14 service**.
- Với backend: bước `mvn -B -ntp -DskipTests clean package -pl <module> -am`
  (build JAR bằng Maven, JDK) → sau đó `docker/build-push-action` đóng image.
- Image được push với **3 tag**: `${{ github.sha }}` (commit SHA — đúng yêu cầu
  "tag = last commit ID"), tên nhánh đã sanitize (vd `demo-ci-tax`), và `latest`
  (chỉ khi nhánh là `main`).

Theo dõi bằng CLI song song (tùy chọn, gây ấn tượng):

```bash
gh run list --workflow=ci.yml --branch=demo_ci_tax --limit 3
gh run watch          # xem log chạy trực tiếp
```

**Bước 3 — Chứng minh image đã lên GHCR (Web Packages):**
Mở https://github.com/users/23122004/packages hoặc tab **Packages** của repo →
chọn package `yas-tax` → cho thầy xem tag mới **trùng với commit SHA** vừa push.

Hoặc CLI:

```bash
gh api /users/23122004/packages/container/yas-tax/versions \
  --jq '.[0].metadata.container.tags'
# in ra danh sách tag, có chứa commit SHA của commit vừa push
```

> **Chốt ý:** commit → CI tự trigger → Maven build → Docker image → push GHCR
> với tag = SHA. Đúng luồng §4.1 trong `docs/context.md`.

---

## MỤC 2 — CD: developer (parameterized) · main · staging

Ba luồng CD tương ứng ba file workflow trong `.github/workflows/`.

### 2A — CD Developer Build (parameterized, cho Developer)

**File:** `cd-developer.yml` — chạy tay (`workflow_dispatch`), namespace riêng `yas-developer`.

**Cách demo (Web — dễ nhìn tham số nhất):**
1. Mở https://github.com/23122004/Y3S2-DevOps/actions → chọn **CD - Developer Build**.
2. Bấm **Run workflow**. Cho thầy xem các tham số:
   - `action`: `deploy` | `cleanup`
   - `developer_profile`: `lean` (mặc định, tắt sidecar, giảm RAM/heap để không OOM cụm lab)
     hoặc `full` (bật sidecar, pod 2/2, dùng khi cần demo developer env trong mesh).
   - **14 ô `<service>_branch`** (vd `tax_branch`, `product_branch`, ...), mặc định `main`.
3. Giải thích cơ chế: nếu `tax_branch=demo_ci_tax` còn các service khác để `main`,
   workflow chạy `git ls-remote --heads origin demo_ci_tax` để lấy SHA của nhánh đó
   và deploy đúng image tag SHA cho **tax**; mọi service khác dùng tag `latest`.
   Đây chính là yêu cầu `developer_build` §4.2 trong `docs/context.md`.
4. Namespace `yas-developer` được tạo mới độc lập cho mỗi lần deploy.

**Cách demo (CLI):**

```bash
gh workflow run cd-developer.yml \
  -f action=deploy \
  -f developer_profile=lean \
  -f tax_branch=demo_ci_tax
gh run watch
```

Kiểm chứng sau khi chạy:

```bash
kubectl get pods -n yas-developer
# tax dùng image tag = SHA của nhánh; product dùng :latest
kubectl get deploy tax     -n yas-developer -o jsonpath="{.spec.template.spec.containers[0].image}{'\n'}"
kubectl get deploy product -n yas-developer -o jsonpath="{.spec.template.spec.containers[0].image}{'\n'}"
```

Truy cập môi trường developer (đã có trong `/etc/hosts`):
`http://developer.yas.local.com`, `http://api-developer.yas.local.com/swagger-ui/index.html`.

### 2B — CD main (auto-deploy `dev` khi merge vào `main`)

**File:** `deploy-dev.yml` — trigger khi push `main`.

**Cách demo:** Giải thích + cho xem run gần nhất trên GitHub Actions.
Luồng: push `main` → build 14 image push GHCR (tag SHA + `main`) →
`yq -i` patch `image.tag` của mọi service trong `k8s/environments/dev/values.yaml`
thành SHA → commit `chore(dev): update image tags to <sha> [skip ci]` và push lại
`main` → **ArgoCD** phát hiện commit mới và auto-sync vào namespace `dev`.

Bằng chứng có sẵn trên cụm — commit gần nhất chính là kiểu này:

```bash
git log --oneline -5
# f4245e2 chore(dev): update image tags to 9a72869... [skip ci]   <-- do workflow tạo
```

Xem lịch sử chạy:

```bash
gh run list --workflow=deploy-dev.yml --limit 5
```

### 2C — CD staging (deploy khi push tag `v*`)

**File:** `deploy-staging.yml` — trigger khi push tag khớp `v*` (semantic version).

**Cách demo (tạo tag thật):**

```bash
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps
git checkout main && git pull
git tag v1.2.3
git push origin v1.2.3
gh run watch
```

Mở GitHub Actions xem **deploy-staging.yml** chạy: build image với tag =
**tên tag** (`ghcr.io/23122004/yas-product:v1.2.3`, KHÔNG phải SHA) → patch
`k8s/environments/staging/values.yaml` → ArgoCD sync vào namespace `staging`.

Kiểm chứng:

```bash
kubectl get deploy product -n staging -o jsonpath="{.spec.template.spec.containers[0].image}{'\n'}"
# kỳ vọng: ghcr.io/23122004/yas-product:v1.2.3
```

---

## MỤC 3 — Domain & Port test (truy cập qua tên miền + định tuyến)

**Mục tiêu:** Chứng minh app truy cập được qua tên miền, Ingress route đúng.

**Bước 1 — Giải thích `/etc/hosts`** (đã cấu hình ở Phần 1A Bước 2). Mở file
cho thầy xem:

```bash
grep yas.local.com /etc/hosts
```

Giải thích: mọi domain trỏ về 1 IP LB, NGINX Ingress route theo Host header
(xem `kubectl get ingress -A` để thấy ánh xạ host → service).

**Bước 2 — Truy cập bằng trình duyệt** (trực quan nhất): mở
- http://storefront.dev.yas.local.com (giao diện shop — trả 200)
- http://backoffice.dev.yas.local.com (trang admin — redirect login Keycloak)
- http://storefront.staging.yas.local.com

**Bước 3 — Kiểm tra bằng `curl` (chứng minh mã trạng thái):**

```bash
LB_IP=129.212.208.194
curl -I -H 'Host: storefront.dev.yas.local.com' http://$LB_IP/
# HTTP/1.1 200 OK
```

**Bước 4 — Bảng trạng thái hàng loạt tất cả domain** (ấn tượng nhất):

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "LB IP = $LB_IP"
for host in argocd.yas.local.com grafana.yas.local.com kiali.yas.local.com \
            identity.yas.local.com pgadmin.yas.local.com akhq.yas.local.com kibana.yas.local.com \
            storefront.dev.yas.local.com backoffice.dev.yas.local.com \
            storefront.staging.yas.local.com backoffice.staging.yas.local.com; do
  code=$(curl -s -m 10 -o /dev/null -w '%{http_code}' -H "Host: $host" "http://$LB_IP/")
  printf '%-42s %s\n' "$host" "$code"
done
```

> `200`/`302` = OK (302 là redirect sang trang login — vẫn chứng minh routing đúng).
> Nếu có domain của `yas` (storefront.yas.local.com...) thì chỉ trả 200 sau khi
> đã chạy Phần 1B.

---

## MỤC 4 — Clean up job (xóa môi trường tạm)

**Mục tiêu:** Chứng minh có job dọn dẹp môi trường `developer_build` để tiết kiệm tài nguyên.

**Bước 1 — Chạy cleanup (Web hoặc CLI):**

Web: Actions → **CD - Developer Build** → Run workflow → `action` = **`cleanup`** → Run.

CLI:

```bash
gh workflow run cd-developer.yml -f action=cleanup
gh run watch
```

**Bước 2 — Chứng minh namespace tạm đã bị xóa sạch:**

```bash
kubectl get ns yas-developer
# kỳ vọng: Error from server (NotFound): namespaces "yas-developer" not found
```

> **Chốt ý:** Job cleanup xóa hoàn toàn namespace `yas-developer` cùng mọi
> resource trong đó → trả RAM/CPU về cho cụm. Đây là yêu cầu "Jenkins job
> dedicated to deleting developer_build configs" §4.2, nhóm em cài như job thứ
> hai trong cùng workflow (tương đương chức năng).

---

## MỤC 5 — Pipeline Dev & Staging KHÔNG qua ArgoCD (ô xám trong sơ đồ)

**Mục tiêu:** Thể hiện luồng deploy trực tiếp (push-based), không qua cơ chế
pull của GitOps.

**Đây là phần GIẢI THÍCH (không cần chạy live), dùng sơ đồ `architecture.md` §1:**

> "Trong sơ đồ, ô màu xám là môi trường **`yas-developer`**. Khác với `dev` và
> `staging` (đi qua GitOps: workflow chỉ patch `values.yaml` rồi ArgoCD tự kéo về),
> môi trường `yas-developer` được **GitHub Actions gọi thẳng `helm upgrade --install`**
> tới cụm Kubernetes — **không** commit cấu hình lên Git, **không** chờ ArgoCD sync.
> Đây là luồng kiểm thử nhanh cho developer, không phụ thuộc GitOps."

Đối chiếu trực quan:
- **Qua GitOps** (`dev`/`staging`): xem `.github/workflows/deploy-dev.yml` /
  `deploy-staging.yml` → có bước `yq patch values.yaml` + `git commit/push`, KHÔNG
  có `helm ... --install` trực tiếp lên cụm.
- **Không GitOps** (`yas-developer`): xem `.github/workflows/cd-developer.yml` →
  có bước `helm upgrade --install ... --namespace yas-developer` chạy thẳng.

Mở 2 file này trên GitHub cho thầy so sánh, hoặc:

```bash
grep -n "helm upgrade" .github/workflows/cd-developer.yml   # có → push trực tiếp
grep -n "helm upgrade" .github/workflows/deploy-dev.yml     # không có → GitOps
grep -n "yq\|git push" .github/workflows/deploy-dev.yml     # có → chỉ patch git
```

---

## MỤC 6 — ArgoCD: dev & staging · Synced/Healthy · Self-Healing

**Mục tiêu:** Demo công cụ GitOps ArgoCD.

**Bước 1 — Lấy mật khẩu admin & đăng nhập UI:**

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo
```

Mở https://argocd.yas.local.com (hoặc http://argocd.yas.local.com → nó redirect).
Đăng nhập `admin` + mật khẩu vừa lấy.

**Bước 2 — Cho thầy xem 2 Application Synced/Healthy:**
Trên UI thấy 2 card: **`dev-yas-app`** và **`staging-yas-app`**, cả hai badge
**Synced** (xanh) và **Healthy** (xanh). Click vào để xem cây resource (14 service).

Xác nhận bằng CLI (đã kiểm chứng live: cả 2 đều Synced/Healthy):

```bash
kubectl get applications -n argocd \
  -o jsonpath='{range .items[*]}{.metadata.name}{" sync="}{.status.sync.status}{" health="}{.status.health.status}{"\n"}{end}'
# dev-yas-app     sync=Synced health=Healthy
# staging-yas-app sync=Synced health=Healthy
```

**Bước 3 — Demo Self-Healing (điểm nhấn):**
ArgoCD cấu hình `syncPolicy.automated` với `selfHeal: true` → mọi thay đổi
"chui" (out-of-band) sẽ bị revert về trạng thái Git trong vài giây.

```bash
# Xem replicas hiện tại
kubectl get deploy product -n dev -o jsonpath='{.spec.replicas}{"\n"}'   # vd: 1

# Sửa "chui" thành 3 replicas
kubectl scale deploy product -n dev --replicas=3
kubectl get deploy product -n dev -o jsonpath='{.spec.replicas}{"\n"}'   # 3 (tạm thời)

# Chờ ~10-30s, ArgoCD tự phát hiện drift và revert
sleep 25
kubectl get deploy product -n dev -o jsonpath='{.spec.replicas}{"\n"}'   # tự về 1
```

Trên UI ArgoCD: trong lúc đó app chuyển **OutOfSync** rồi tự **Synced** lại,
kèm event "auto-sync". Giải thích: "Git là source of truth — mọi drift bị tự hoàn tác."

---

## MỤC 7 — mTLS (mã hóa giữa các pod, chế độ STRICT)

> **Yêu cầu Phần 1B đã chạy xong** (staging đã ở STRICT). Nếu chưa, chạy trước.

**Bước 1 — Cho thầy xem file cấu hình `PeerAuthentication` STRICT:**

```bash
cat k8s/istio/staging-demo/peer-authentication-staging-strict.yaml
cat k8s/istio/staging-demo/public-entrypoints-staging.yaml
```

Chỉ vào object `default-strict-mtls` (namespace `staging`, `mode: STRICT`) — mọi
kết nối pod-to-pod trong `staging` bắt buộc phải mTLS. Giải thích 3 override
`PERMISSIVE` cho `storefront-bff`/`backoffice-bff`/`swagger-ui` (vì được gọi từ
ngoài mesh qua Ingress nên phải chấp nhận cả plaintext ở lối vào).

Xác nhận đã áp trên cụm:

```bash
kubectl get peerauthentication -n staging
```

**Bước 2 — Chạy kịch bản chứng minh STRICT chặn plaintext:**

```bash
kubectl exec -n staging deploy/tax -c istio-proxy -- \
  curl -s http://product.staging.svc.cluster.local/
```

Kỳ vọng: **connection reset / empty reply**.

> **Giải thích cho thầy:** "Em cố tình chạy `curl` từ **bên trong container
> `istio-proxy`** (UID 1337). Istio loại UID này khỏi iptables capture, nên
> request đi ra dưới dạng **plaintext**, không qua mTLS. Vì `product` đang ở chế
> độ `STRICT`, Envoy của nó **từ chối** kết nối không mã hóa → connection reset.
> Đây chính là bằng chứng mTLS STRICT đang được thực thi. Nếu là traffic hợp lệ
> (từ sidecar), nó sẽ được mã hóa bằng chứng chỉ SPIFFE tự động và đi qua bình thường."

---

## MỤC 8 — Kiali: Topology & Flowchart

> Cần Phần 1B (staging đã có DestinationRule ISTIO_MUTUAL → ổ khóa mTLS hiện lên).
> Kiali đã chạy sẵn (`kiali.yas.local.com`).

**Bước 1 — Sinh traffic để graph có dữ liệu** (Kiali đọc metric ~vài phút gần nhất):

```bash
LB_IP=129.212.208.194
for i in $(seq 1 30); do
  curl -s -o /dev/null -H 'Host: storefront.staging.yas.local.com' http://$LB_IP/
  curl -s -o /dev/null -H 'Host: api.staging.yas.local.com' http://$LB_IP/swagger-ui/index.html
done
```

**Bước 2 — Mở Kiali:** http://kiali.yas.local.com → menu **Graph**.
- **Namespace:** chọn `staging`.
- **Graph type:** chọn **Versioned app graph**.
- Bật **Display → Traffic Animation** (thấy chấm chạy trên các cạnh).
- Bật **Display → Security** (hiện biểu tượng ổ khóa trên các cạnh).

**Bước 3 — Chỉ cho thầy:**
- Các node service (`product`, `cart`, `order`, `tax`, `customer`, `inventory`,
  `search`, `media`, các BFF/UI, `postgres`, `kafka`...) và luồng đi.
- **Ổ khóa màu xanh** trên các cạnh nội bộ = traffic được mã hóa bằng **mTLS**.
  Đây là bằng chứng trực quan cho yêu cầu §5.2.2.

- Chỉ cho thầy các node service trong `staging` và **ổ khóa xanh mTLS** trên các
  cạnh nội bộ (nhờ DestinationRule `ISTIO_MUTUAL` vừa áp ở Phần 1B).

Nếu DNS/ingress trục trặc, mở nhanh bằng port-forward:

```bash
kubectl -n istio-system port-forward svc/kiali 20001:20001
# mở http://localhost:20001
```

> Tham chiếu báo cáo: lần test trước (trên namespace `yas`) graph có **30 node /
> 16 cạnh** đầy đủ (xem `docs/huy-service-mesh-report.md`). Chụp lại graph
> full-namespace `staging` bật Security để đưa vào báo cáo nộp.

---

## MỤC 9 — Kịch bản Test: Authorization Policy & Retry Policy

> Cần Phần 1B (pod test đã tạo ở Bước 3). Đây là §18 `tutorial.md` chạy trên `staging`.

Hai pod đã tạo ở Phần 1B: `mesh-tester-order` (ServiceAccount `order` — **được phép**
gọi `product`) và `mesh-tester-default` (SA `default` — **không** trong allow-list).

### 9A — Authorization Policy: ALLOW

```bash
kubectl exec -n staging mesh-tester-order -c tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://product.staging.svc.cluster.local/
```

Kỳ vọng: **KHÔNG phải 403** (thường `404` vì `/` không phải route thật — điều
quan trọng là request được cho vào tới app).

### 9B — Authorization Policy: DENY (403)

```bash
kubectl exec -n staging mesh-tester-default -c tester -- \
  curl -s http://product.staging.svc.cluster.local/
kubectl exec -n staging mesh-tester-default -c tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://product.staging.svc.cluster.local/
```

Kỳ vọng: body chứa **`RBAC: access denied`**, mã **`403`**. Xác nhận phía server:

```bash
kubectl logs -n staging deploy/product -c istio-proxy | grep rbac_access_denied | tail -1
```

> **Giải thích:** `AuthorizationPolicy product-allow-callers` chỉ cho phép các
> principal (SPIFFE identity theo ServiceAccount) `order`, `cart`, `search`,
> `storefront-bff`, `backoffice-bff` gọi `product`. Pod `default` không nằm trong
> danh sách → bị chặn 403. Danh tính được chứng thực bằng chứng chỉ mTLS nên
> không thể giả mạo.

**(Tùy chọn) Bản demo đúng nguyên văn đề "chỉ order gọi được product":**

```bash
kubectl apply -f k8s/istio/staging-demo/demo/authorization-policy-strict-demo-staging.yaml
kubectl exec -n staging deploy/order -c istio-proxy -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://product.staging.svc.cluster.local/actuator/health   # 200
kubectl exec -n staging deploy/tax -c istio-proxy -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://product.staging.svc.cluster.local/actuator/health   # 403
# KHÔI PHỤC ngay (nếu không storefront sẽ 403 khi xem product):
kubectl delete -f k8s/istio/staging-demo/demo/authorization-policy-strict-demo-staging.yaml
```

### 9C — Retry Policy (tự thử lại khi 500)

```bash
# Client gọi endpoint luôn trả 500
kubectl exec -n staging mesh-tester-order -c tester -- \
  curl -s -o /dev/null -w '%{http_code}\n' http://httpbin.staging.svc.cluster.local:8000/status/500
# Đếm số hit thực tế tại server
kubectl logs -n staging deploy/httpbin | grep -c '/status/500'
```

Kỳ vọng: client thấy `500` (retry không cứu được lỗi cố định — đó là chủ đích),
nhưng log httpbin hiện **4 hit** = 1 lần gốc + **3 lần retry** → chứng minh
`retries.attempts: 3` trong `VirtualService` đang chạy. Đọc thêm từ Envoy stats:

```bash
kubectl exec -n staging mesh-tester-order -c istio-proxy -- \
  curl -s localhost:15000/stats | grep 'httpbin.*upstream_rq_retry'
```

Cho thầy xem file cấu hình retry:

```bash
cat k8s/istio/staging-demo/virtual-services-staging.yaml   # tax-retry / order-retry: attempts 3, retryOn 5xx,...
```

**Dọn dẹp sau demo mesh:** dùng Phần 1C (rollback staging về PERMISSIVE + xóa policy demo).

---

## MỤC 10 — Observability (Grafana)

> ⚠️ **Loki (log) đang hỏng** (xem Quyết định 2). Demo Metric + Trace, và giải
> thích kiến trúc log. Metric/Trace hoạt động bình thường.

**Bước 1 — Đăng nhập Grafana:** mở http://grafana.yas.local.com →
login `admin` / `admin` (theo `k8s/deploy/cluster-config.yaml`).

**Bước 2 — Metrics (Prometheus) — "hệ thống đang khỏe không?":**
- Vào **Dashboards** → mở dashboard Kubernetes/cluster có sẵn. Chỉ cho thầy:
  CPU/Memory theo namespace & pod, số pod Running, request rate.
- Giải thích: "Dashboard này cho biết mức tiêu thụ tài nguyên, tình trạng pod,
  phát hiện pod OOM/CrashLoop, cảnh báo qua Alertmanager."

**Bước 3 — Traces (Tempo) — "một request đi qua đâu, chậm ở đâu":**
- Vào **Explore** → chọn datasource **Tempo** → **Search** trace (theo service/thời gian)
  hoặc dán một `traceId`. Mở 1 trace ra xem **waterfall các span** qua nhiều service.
- Xem **Node graph** (service dependency) của Tempo.
- Giải thích cách fix bug: "Khi một API chậm/500, em mở trace tương ứng, nhìn
  waterfall để thấy span nào tốn thời gian hoặc lỗi (vd `order → tax` timeout),
  rồi từ span đó nhảy sang log/metric của đúng service đó (Tempo được cross-link
  sang Loki & Prometheus)."

**Bước 4 — Logs (Loki):** *(hiện KHÔNG chạy trên cụm lab)*
Nói thật với thầy:
> "Pipeline log của em là **Promtail → Loki → Grafana**, đã cấu hình đầy đủ
> (Promtail đang chạy 4/4 trên các node, thu log mọi pod). Tuy nhiên backend
> lưu trữ của Loki (`loki-minio`) trên cụm lab đang lỗi (`read-only file system`)
> nên truy vấn log tạm thời trống. Về kiến trúc và luồng thì đầy đủ; em có thể
> chỉ file cấu hình datasource và Promtail."

Bằng chứng pipeline vẫn tồn tại:

```bash
kubectl get pods -n observability | grep -E 'promtail|loki|tempo|grafana|prometheus'
kubectl logs loki-write-0 -n observability -c loki --tail=3   # thấy lỗi read-only fs
```

### 10.4 (Nếu muốn sửa Loki — tùy chọn, làm trước demo)

Nguyên nhân: `loki-write` không ghi được vào object storage vì `loki-minio`
không hoạt động. Cần redeploy chart loki (hoặc khôi phục `loki-minio` StatefulSet).
Đây là thao tác Helm, **không chạy live trước thầy**. Nếu quyết định sửa, kiểm tra:

```bash
kubectl get statefulset -n observability | grep minio    # hiện KHÔNG có → cần dựng lại
helm list -n observability                                # xem release loki
```

> Khuyến nghị: **để nguyên và demo Metric + Trace** (an toàn). Việc sửa Loki
> nằm ngoài phạm vi demo bắt buộc.

---

## PHỤ LỤC A — Sau buổi demo: dọn dẹp & tiết kiệm chi phí

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml

# Rollback staging về PERMISSIVE + xóa policy/pod demo → xem Phần 1C
# (đưa staging về đúng trạng thái trước buổi demo)

# Xóa sandbox developer nếu còn
gh workflow run cd-developer.yml -f action=cleanup

# Hạ node pool xuống 2 để tiết kiệm (~$24/tháng/node) — chỉ khi không demo nữa
doctl kubernetes cluster node-pool update \
  01333b63-5474-4eec-a515-98030c5c872d \
  5090e1e7-ca6e-42ed-8463-4d5b783577a4 --count 2
```

## PHỤ LỤC B — Bảng đối chiếu yêu cầu ↔ mục demo

| Yêu cầu (`docs/context.md`) | Mục demo | Trạng thái |
|---|---|---|
| CI build + push, tag=SHA (§4.1) | Mục 1 | ✅ sẵn sàng |
| CD developer parameterized (§4.2) | Mục 2A | ✅ sẵn sàng |
| CD dev auto trên `main` (§4.2) | Mục 2B | ✅ sẵn sàng |
| CD staging trên tag `v*` (§4.2) | Mục 2C | ✅ sẵn sàng |
| Domain / routing (§4.2) | Mục 3 | ✅ sẵn sàng |
| Cleanup job (§4.2) | Mục 4 | ✅ sẵn sàng |
| Non-GitOps direct deploy (arch §1) | Mục 5 | ✅ giải thích |
| ArgoCD GitOps + self-heal (§5.1) | Mục 6 | ✅ sẵn sàng |
| mTLS STRICT (§5.2.1) | Mục 7 | ⚠️ chạy Phần 1B (áp lên `staging`) |
| Kiali topology (§5.2.2) | Mục 8 | ⚠️ chạy Phần 1B (namespace `staging`) |
| Retry + Authz policy (§5.2.3) | Mục 9 | ⚠️ chạy Phần 1B (áp lên `staging`) |
| Observability (§2.1) | Mục 10 | ⚠️ Loki hỏng, demo metric+trace |
