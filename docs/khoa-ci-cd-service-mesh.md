# Khoa - CI/CD Developer Build and Service Mesh

Tài liệu này ghi lại phần việc của Khoa trong Project02: CI build Docker image theo commit SHA, CD `developer_build`, cleanup môi trường developer, và cấu hình Istio Service Mesh.

## 1. Những gì đã làm

### CI Docker Hub

Đã thêm workflow:

```text
.github/workflows/ci.yml
```

Workflow này:

- Chạy khi push lên mọi branch.
- Build Docker image cho các service chính.
- Push image lên Docker Hub.
- Tag image bằng commit SHA, ví dụ `yas-tax:<commit_sha>`.
- Tag thêm bằng tên branch đã sanitize, ví dụ `yas-tax:feature-tax`.
- Nếu push lên `main`, push thêm tag `latest`.

Các image được build:

```text
yas-product
yas-cart
yas-order
yas-customer
yas-inventory
yas-tax
yas-media
yas-search
yas-storefront-bff
yas-storefront-ui
yas-backoffice-bff
yas-backoffice-ui
yas-sampledata
yas-swagger-ui
```

`swagger-ui/Dockerfile` được thêm để CI có thể build image `yas-swagger-ui` theo đúng danh sách service cần demo.

### CD Developer Build

Đã thêm workflow:

```text
.github/workflows/cd-developer.yml
```

Workflow này:

- Chạy thủ công bằng `workflow_dispatch`.
- Có input `action` gồm `deploy` hoặc `cleanup`.
- Deploy vào namespace:

```text
yas-developer
```

- Cho phép nhập branch riêng cho từng service.
- Nếu input branch là `main`, workflow dùng image tag `latest`.
- Nếu input branch khác `main`, workflow resolve commit SHA cuối của branch đó rồi deploy image đúng SHA.
- In URL và hosts entries vào GitHub Actions summary.

Domain developer theo hướng bám sát đề bài:

```text
developer.yas.local.com
backoffice-developer.yas.local.com
api-developer.yas.local.com
```

Các domain này trỏ về Load Balancer của ingress controller.

### Istio Service Mesh

Đã thêm thư mục:

```text
k8s/istio/
```

Các file chính:

```text
k8s/istio/peer-authentication.yaml
k8s/istio/destination-rules.yaml
k8s/istio/virtual-services.yaml
k8s/istio/public-entrypoints.yaml
k8s/istio/install-istio.ps1
k8s/istio/install-istio.sh
k8s/istio/README.md
```

Đã cài Istio `1.30.2` lên cluster DOKS và apply cấu hình:

- Namespace `yas`, `yas-developer`, `dev`, `staging` bật `istio-injection=enabled`.
- Namespace `ingress-nginx` cũng bật injection để public ingress đi qua Envoy.
- Pod trong namespace `yas` đã restart và có `istio-proxy`.
- `PeerAuthentication` bật `STRICT` mTLS ở namespace chính.
- `DestinationRule` dùng `ISTIO_MUTUAL`.
- `VirtualService` retry cho `tax` và `order`.
- Public entrypoints `storefront-bff`, `backoffice-bff`, `swagger-ui` đặt `PERMISSIVE` để NGINX Ingress vẫn truy cập được, backend services vẫn chịu policy `STRICT`.

## 2. GitHub Secrets và Variables cần có

Vào GitHub repository:

```text
Settings -> Secrets and variables -> Actions
```

Tab `Secrets`, cần có:

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
DIGITALOCEAN_ACCESS_TOKEN
```

Tab `Variables`, cần có:

```text
DOKS_CLUSTER_NAME
BASE_DOMAIN
```

Giá trị `BASE_DOMAIN` đang dùng:

```text
yas.local.com
```

`DOKS_CLUSTER_NAME` phải đúng tên cluster DigitalOcean Kubernetes mà workflow dùng để chạy:

```bash
doctl kubernetes cluster kubeconfig save "$DOKS_CLUSTER_NAME"
```

## 3. Cách commit và push

Kiểm tra file đã thay đổi:

```bash
git status
```

Add các file của phần Khoa:

```bash
git add .github/workflows/ci.yml
git add .github/workflows/cd-developer.yml
git add k8s/namespaces.yaml
git add k8s/istio
git add swagger-ui/Dockerfile
git add docs/khoa-ci-cd-service-mesh.md
git add docs/context-memory.md
```

Commit:

```bash
git commit -m "feat: add developer ci cd and istio service mesh"
```

Push branch hiện tại:

```bash
git push origin feat/pipeline-cd
```

Nếu bạn đang ở branch khác, thay `feat/pipeline-cd` bằng tên branch đang dùng:

```bash
git branch --show-current
git push origin <branch-name>
```

## 4. Cách test CI sau khi push

Sau khi push, GitHub Actions sẽ tự chạy:

```text
CI - Build Docker Hub Images
```

Kiểm tra:

1. Vào GitHub repo.
2. Mở tab `Actions`.
3. Chọn workflow `CI - Build Docker Hub Images`.
4. Chọn run mới nhất của branch vừa push.
5. Chờ các job trong matrix build xong.

CI được xem là hoàn thành khi:

- Workflow status màu xanh.
- Các job service đều pass.
- Trong log có bước `Log in to Docker Hub`.
- Trong log có bước `Build and push`.
- Docker Hub xuất hiện image tag commit SHA.

Ví dụ nếu commit SHA là:

```text
abc123...
```

thì Docker Hub phải có image:

```text
<DOCKERHUB_USERNAME>/yas-product:abc123...
<DOCKERHUB_USERNAME>/yas-tax:abc123...
```

Nếu branch là `main`, kiểm tra thêm tag:

```text
latest
```

Lưu ý: CD developer dùng `latest` cho các service để `main`. Vì vậy trước khi chạy CD developer với nhiều input `main`, cần bảo đảm Docker Hub đã có các image `latest`. Cách chắc nhất là merge/push `main` để CI tạo `latest`, hoặc chọn branch cụ thể cho service cần test sau khi CI của branch đó đã chạy xong.

## 5. Cách test CD developer_build

Chỉ chạy CD sau khi CI đã build xong image cần deploy.

Lưu ý quan trọng: workflow chạy thủ công bằng `workflow_dispatch` thường chỉ hiện ổn định trong tab GitHub Actions sau khi file `.github/workflows/cd-developer.yml` đã có trên default branch của repository. Nếu push lên branch `feat/pipeline-cd` mà chưa thấy workflow `CD - Developer Build`, hãy mở PR và merge workflow này vào `main` trước, sau đó quay lại tab Actions để chạy CD.

Trên GitHub:

1. Vào tab `Actions`.
2. Chọn workflow:

```text
CD - Developer Build
```

3. Bấm `Run workflow`.
4. Chọn branch chứa workflow.
5. Chọn:

```text
action = deploy
```

6. Nhập branch cho service cần test.

Ví dụ developer sửa `tax` ở branch:

```text
dev_tax_service
```

thì nhập:

```text
tax_branch = dev_tax_service
```

Các field branch khác để `main`.

Workflow sẽ:

- Resolve commit SHA cuối của `dev_tax_service`.
- Deploy `tax` bằng image tag SHA đó.
- Deploy các service còn lại bằng tag `latest`.
- Deploy vào namespace `yas-developer`.
- In URL test và hosts entries trong summary.

## 6. Hosts file để test Developer environment

Sau khi workflow chạy xong, xem phần summary để lấy IP Load Balancer. Với cluster hiện tại, IP đang là:

```text
129.212.208.194
```

Thêm vào file hosts trên máy test:

```text
129.212.208.194 developer.yas.local.com
129.212.208.194 backoffice-developer.yas.local.com
129.212.208.194 api-developer.yas.local.com
```

Truy cập:

```text
http://developer.yas.local.com
http://backoffice-developer.yas.local.com
http://api-developer.yas.local.com/swagger-ui/index.html
```

## 7. Cách kiểm tra CD developer đã hoàn thành

Chạy bằng local kubeconfig hoặc hỏi người có quyền cluster chạy:

```bash
kubectl get pods -n yas-developer
kubectl get deploy -n yas-developer -o wide
kubectl get ingress -n yas-developer
```

Kết quả mong muốn:

- Pod trong `yas-developer` là `Running`.
- Nếu Istio injection bật, pod app sẽ là `2/2`.
- Service được chọn branch riêng dùng image tag commit SHA.
- Service còn lại dùng tag `latest`.
- Ingress có host `developer.yas.local.com`, `backoffice-developer.yas.local.com`, `api-developer.yas.local.com`.

Kiểm tra image tag cụ thể:

```bash
kubectl get deploy tax -n yas-developer -o jsonpath="{.spec.template.spec.containers[0].image}"
```

Nếu `tax_branch=dev_tax_service`, output phải có commit SHA của branch đó:

```text
<DOCKERHUB_USERNAME>/yas-tax:<commit_sha>
```

## 8. Cách test cleanup

Trên GitHub:

1. Vào `Actions`.
2. Chọn `CD - Developer Build`.
3. Bấm `Run workflow`.
4. Chọn:

```text
action = cleanup
```

Sau khi workflow xong, kiểm tra:

```bash
kubectl get ns yas-developer
```

Nếu cleanup thành công, namespace không còn tồn tại.

## 9. Cách kiểm tra Service Mesh

Kiểm tra Istio system:

```bash
kubectl get pods -n istio-system
```

Kết quả mong muốn:

```text
istiod                       Running
istio-ingressgateway         Running
istio-egressgateway          Running
```

Kiểm tra sidecar:

```bash
kubectl get pods -n yas
```

Kết quả mong muốn: các app pod trong `yas` là `2/2`.

Kiểm tra policy:

```bash
kubectl get peerauthentication -A
kubectl get destinationrule -n yas
kubectl get virtualservice -n yas
```

Kết quả mong muốn:

- `default-strict-mtls` mode `STRICT`.
- DestinationRule có host service nội bộ và dùng `ISTIO_MUTUAL`.
- VirtualService có `tax-retry` và `order-retry`.

Kiểm tra public endpoint sau khi bật mesh:

```powershell
Invoke-WebRequest -Uri http://storefront.yas.local.com -UseBasicParsing -TimeoutSec 15
Invoke-WebRequest -Uri http://backoffice.yas.local.com -UseBasicParsing -TimeoutSec 15
Invoke-WebRequest -Uri http://api.yas.local.com/swagger-ui/index.html -UseBasicParsing -TimeoutSec 15
```

Kết quả mong muốn:

```text
StatusCode: 200
```

Kiểm tra proxy sync:

```bash
istioctl proxy-status
```

Kết quả mong muốn: các proxy trong `yas` và `ingress-nginx` sync với `istiod`.

## 10. Những ảnh/log nên đưa vào báo cáo

Chụp các phần sau:

- GitHub Actions workflow `CI - Build Docker Hub Images` pass.
- Docker Hub có image tag commit SHA.
- GitHub Actions workflow `CD - Developer Build` pass.
- Summary của CD có URL và hosts entries.
- `kubectl get pods -n yas-developer`.
- `kubectl get deploy -n yas-developer -o wide`.
- `kubectl get pods -n yas` hiển thị `2/2`.
- `kubectl get peerauthentication -A`.
- `kubectl get destinationrule -n yas`.
- `kubectl get virtualservice -n yas`.
- Website `developer.yas.local.com` truy cập được.
