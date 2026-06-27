# YAS: Yet Another Shop - Context Memory & Deployment Status

Tài liệu này ghi nhận toàn bộ bối cảnh dự án, các công việc đã thực hiện, cấu trúc triển khai hạ tầng và trạng thái deploy hiện tại trên nhánh `feat/pipeline-cd`. Mục tiêu là giúp các thành viên trong dự án hoặc các AI Agent tiếp quản có thể nhanh chóng nắm bắt và tiếp tục phát triển.

---

## 1. Tổng quan Dự án & Mục tiêu hiện tại

- **Dự án**: **YAS (Yet Another Shop)** - Ứng dụng thương mại điện tử (e-commerce) xây dựng theo kiến trúc microservices sử dụng Java (Spring Boot) cho backend và Next.js cho frontend.
- **Mục tiêu của nhánh `feat/pipeline-cd`**: 
  - Hoàn thiện cấu hình triển khai Kubernetes trên môi trường phát triển cục bộ (**Minikube**) và môi trường Cloud (**DigitalOcean Kubernetes - DOKS**).
  - Cấu hình hệ thống CI/CD thông qua **GitHub Actions** kết hợp **Helm**, **NGINX Ingress Controller**, **Argo CD** (cho GitOps) và **Istio Service Mesh**.
  - Triển khai cổng tài liệu API tập trung bằng **Swagger UI**.
  - Sửa các lỗi giao diện frontend liên quan đến quản lý Thuế (`tax-classes`, `tax-rates`).
  - Tối ưu hóa tài nguyên (CPU/Memory requests/limits) của các dịch vụ để đảm bảo khả năng chạy ổn định trên cấu hình máy cá nhân.

---

## 2. Nhật ký Công việc đã Thực hiện (Commit History)

Các công việc gần đây do tác giả `htrung1105` thực hiện trên nhánh `feat/pipeline-cd` bao gồm:

*   **`a71d95bd` (fix: api page)**:
    *   Bổ sung cấu hình triển khai **Swagger UI** (`k8s/charts/swagger-ui`).
    *   Tạo `nginx-configmap.yaml` để thiết lập NGINX làm proxy phục vụ tài liệu API tĩnh cho các microservices backend.
*   **`0a308e9f` (fix)**:
    *   Sửa lỗi hiển thị và lưu dữ liệu trên các trang quản lý Thuế trong **Backoffice UI**:
        *   Trang chỉnh sửa/tạo mới nhóm thuế: [edit.tsx](file:///d:/Y3S2/%5BDevOps%5D_Project02/backoffice/pages/tax/tax-classes/%5Bid%5D/edit.tsx), [create.tsx](file:///d:/Y3S2/%5BDevOps%5D_Project02/backoffice/pages/tax/tax-classes/create.tsx), [index.tsx](file:///d:/Y3S2/%5BDevOps%5D_Project02/backoffice/pages/tax/tax-classes/index.tsx).
        *   Trang quản lý thuế suất: [edit.tsx](file:///d:/Y3S2/%5BDevOps%5D_Project02/backoffice/pages/tax/tax-rates/%5Bid%5D/edit.tsx), [index.tsx](file:///d:/Y3S2/%5BDevOps%5D_Project02/backoffice/pages/tax/tax-rates/index.tsx).
    *   Cập nhật `values.yaml` của **Swagger UI**.
*   **`7455e1d1` (fix)**:
    *   Thêm cấu hình Ingress backend chung [yas-backend-apis-ingress.yaml](file:///d:/Y3S2/%5BDevOps%5D_Project02/k8s/yas-backend-apis-ingress.yaml) giúp định tuyến URL dạng `/product`, `/cart`, `/order`,... về đúng service trong namespace `yas`.
    *   Cấu hình NGINX service và các bí danh dịch vụ (service aliases) trong [service-aliases.yaml](file:///d:/Y3S2/%5BDevOps%5D_Project02/k8s/service-aliases.yaml).
*   **`ce982c4e` (fix: reduce unless service)**:
    *   Tối ưu hóa tài nguyên phần cứng bằng cách giảm mức CPU/Memory requests/limits trong các file Helm Chart của các service (`product`, `cart`, `order`,...).
    *   Chỉnh sửa Dockerfile của `payment-paypal` để tối ưu hóa quá trình build image.
*   **`153386c5` (update: deploy k8s service)**:
    *   Cập nhật toàn bộ các manifest triển khai Kubernetes hạ tầng (`Elasticsearch`, `Kibana`, `Kafka`, `Debezium Connect`, `Keycloak`, `PostgreSQL`, `pgAdmin`, `Prometheus`, `Grafana`, `Loki`, `Tempo`, `OpenTelemetry Collector`, `Zookeeper`).
    *   Tạo script cài đặt ứng dụng tự động:
        *   [deploy-yas-applications.sh](file:///d:/Y3S2/%5BDevOps%5D_Project02/k8s/deploy/deploy-yas-applications.sh) (Shell script cho Linux/macOS).
        *   [deploy-yas-applications.ps1](file:///d:/Y3S2/%5BDevOps%5D_Project02/k8s/deploy/deploy-yas-applications.ps1) (PowerShell script cho Windows).
    *   Soạn thảo tài liệu đặc tả chi tiết [implementation-spec.md](file:///d:/Y3S2/%5BDevOps%5D_Project02/docs/implementation-spec.md) định hướng thiết lập hạ tầng đám mây DOKS và quy trình CI/CD.

---

## 3. Kiến trúc Triển khai & Hạ tầng (Kubernetes)

Ứng dụng YAS được chia thành hai nhóm chính khi chạy trên Kubernetes:

### 3.1 Ứng dụng nghiệp vụ (Microservices) - Namespace `yas`
Các microservice chạy trong namespace `yas` và được quản lý thông qua các Helm Charts nằm trong `k8s/charts/`:
- `storefront-ui` & `storefront-bff`: Ứng dụng mua sắm cho khách hàng và Gateway.
- `backoffice-ui` & `backoffice-bff`: Ứng dụng quản trị hệ thống và Gateway.
- `swagger-ui`: Cổng API documentation.
- Các API Business Services: `product`, `cart`, `order`, `customer`, `inventory`, `tax`, `media`, `search`.
- `sampledata`: Job hỗ trợ seeding dữ liệu mẫu lúc khởi tạo hệ thống.

### 3.2 Dịch vụ hạ tầng (Infrastructure)
Các dịch vụ hỗ trợ được triển khai thông qua các toán tử (Operators) và Helm Charts trong `k8s/deploy/`:
- **Database**: PostgreSQL (quản lý bởi Zalando Postgres Operator) trong namespace `postgres`.
- **Cache/Session**: Redis trong namespace `redis`.
- **Identity & Access Management (IAM)**: Keycloak trong namespace `keycloak`.
- **Event Streaming & CDC**: Kafka (quản lý bởi Strimzi Operator) và Debezium Connect trong namespace `kafka`.
- **Search Engine**: Elasticsearch và Kibana (quản lý bởi ECK Operator) trong namespace `elasticsearch`.
- **Giám sát (Observability)**: Loki (Log), Tempo (Trace), Prometheus & Grafana (Metric) và OpenTelemetry Collector trong namespace `observability`.

---

## 4. Hướng dẫn Deploy dự án cục bộ (Local Deployment)

Để chạy thử nghiệm toàn bộ hệ thống trên **Minikube** cục bộ, hãy thực hiện theo trình tự sau:

### Bước 1: Chuẩn bị Môi trường
- Yêu cầu cấu hình tối thiểu: CPU 4 cores, RAM 16GB, Ổ cứng trống 40GB.
- Khởi động Minikube và kích hoạt Ingress:
  ```bash
  minikube start --disk-size='40000mb' --memory='16g'
  minikube addons enable ingress
  ```

### Bước 2: Deploy các dịch vụ hạ tầng (Infrastructure Services)
Di chuyển vào thư mục [k8s/deploy](file:///d:/Y3S2/%5BDevOps%5D_Project02/k8s/deploy) và chạy các script thiết lập theo thứ tự:
1. Triển khai Keycloak làm dịch vụ định danh:
   ```bash
   ./setup-keycloak.sh
   ```
2. Triển khai Redis để quản lý sessions:
   ```bash
   ./setup-redis.sh
   ```
3. Triển khai cơ sở dữ liệu và các thành phần bổ trợ (Postgres, Kafka, Elasticsearch, Observability stack):
   ```bash
   ./setup-cluster.sh
   ```
   *Lưu ý: Chờ cho toàn bộ các Pod trong các namespace (`postgres`, `elasticsearch`, `kafka`, `keycloak`, `observability`) chuyển sang trạng thái `Running` trước khi sang bước tiếp theo.*

### Bước 3: Deploy toàn bộ ứng dụng YAS
Chạy script cài đặt ứng dụng:
- Trên Linux/macOS:
  ```bash
  ./deploy-yas-applications.sh
  ```
- Trên Windows (PowerShell):
  ```powershell
  .\deploy-yas-applications.ps1
  ```
Script này sẽ tự động cập nhật các Helm Chart dependencies và deploy toàn bộ microservices của YAS vào namespace `yas`.

### Bước 4: Cấu hình File Hosts
Lấy địa chỉ IP của Minikube:
```bash
minikube ip
```
Thêm dòng sau vào file `/etc/hosts` (Linux/macOS) hoặc `C:\Windows\System32\drivers\etc\hosts` (Windows) để ánh xạ IP sang các tên miền local:
```text
<MINIKUBE_IP> pgoperator.yas.local.com
<MINIKUBE_IP> pgadmin.yas.local.com
<MINIKUBE_IP> akhq.yas.local.com
<MINIKUBE_IP> kibana.yas.local.com
<MINIKUBE_IP> identity.yas.local.com
<MINIKUBE_IP> backoffice.yas.local.com
<MINIKUBE_IP> storefront.yas.local.com
<MINIKUBE_IP> grafana.yas.local.com
<MINIKUBE_IP> api.yas.local.com
<MINIKUBE_IP> argocd.yas.local.com
```

Bây giờ bạn có thể truy cập:
- Frontend mua sắm: `http://storefront.yas.local.com`
- Frontend quản trị: `http://backoffice.yas.local.com`
- Tài liệu API (Swagger UI): `http://api.yas.local.com/swagger-ui.html`
- Giám sát Grafana: `http://grafana.yas.local.com` (Bị lỗi 503)

---

## 5. Thiết kế Quy trình CI/CD trên Cloud (DOKS)

Tài liệu [implementation-spec.md](file:///d:/Y3S2/%5BDevOps%5D_Project02/docs/implementation-spec.md) quy định chi tiết mô hình triển khai thực tế trên DigitalOcean Kubernetes.

### 5.1 Các Workflow GitHub Actions chính cần cấu hình:
1.  **`ci.yml`**: Tự động kích hoạt khi có commit mới trên mọi branch. Thực hiện build Docker Image bằng Docker Buildx và push lên Docker Hub với tag định dạng: `${IMAGE}:${COMMIT_SHA}` và `${IMAGE}:${BRANCH_NAME}`.
2.  **`cd-developer.yml`**: Kích hoạt thủ công (workflow_dispatch). Cho phép lập trình viên chỉ định branch tùy ý cho một service cụ thể để test, các service còn lại sẽ tự động lấy tag `latest`. Triển khai tại namespace `yas-developer`.
3.  **`cd-dev.yml`**: Tự động kích hoạt khi code được merge vào branch `main`. Triển khai phiên bản mới nhất tại namespace `yas-dev`.
4.  **`cd-staging.yml`**: Tự động kích hoạt khi push tag phiên bản (`v*`). Thực hiện build release images và deploy tại namespace `yas-staging`.

### 5.2 Các Secrets & Variables cần khai báo trên GitHub Repository:
- **Secrets**:
  - `DOCKERHUB_USERNAME`: Tên tài khoản Docker Hub.
  - `DOCKERHUB_TOKEN`: Access Token dùng để push image.
  - `DIGITALOCEAN_ACCESS_TOKEN`: Token API của DigitalOcean để quản lý cluster DOKS.
- **Variables**:
  - `DOKS_CLUSTER_NAME`: Tên của cluster DOKS (mặc định: `yas-doks`).
  - `DOKS_REGION`: Vùng địa lý của cluster (mặc định: `sgp1`).
  - `BASE_DOMAIN`: Tên miền gốc trỏ tới Load Balancer của DigitalOcean (ví dụ: `yas.example.com`).

### 5.3 Cập nhật phần Khoa - CI/CD Developer Build và Service Mesh

Đã bổ sung tài liệu thao tác chi tiết tại [khoa-ci-cd-service-mesh.md](khoa-ci-cd-service-mesh.md).

Các thay đổi chính:

1. **CI Docker Hub**:
   - Thêm workflow `.github/workflows/ci.yml`.
   - Build Docker image cho các service chính khi push mọi branch.
   - Push image lên Docker Hub với tag commit SHA.
   - Push thêm tag branch-name và `latest` khi branch là `main`.

2. **CD Developer Build**:
   - Thêm workflow `.github/workflows/cd-developer.yml`.
   - Chạy thủ công bằng `workflow_dispatch`.
   - Deploy vào namespace `yas-developer`.
   - Cho phép nhập branch riêng cho từng service.
   - Service chọn branch riêng dùng image tag commit SHA, service còn lại dùng `latest`.
   - Có `developer_profile=lean/full`: `lean` là workaround cho cluster thiếu RAM, tắt Istio sidecar riêng ở `yas-developer`; `full` giữ sidecar/mTLS cho developer environment khi cluster đủ tài nguyên.
   - Có action `cleanup` để xóa namespace `yas-developer`.

3. **Service Mesh**:
   - Thêm thư mục `k8s/istio/`.
   - Cài Istio `1.30.2` trên DOKS.
   - Bật sidecar injection cho `yas`, `dev`, `staging`, và `ingress-nginx`; `yas-developer` có thể chạy `full` để bật sidecar hoặc `lean` để giảm RAM khi demo CD.
   - Apply `PeerAuthentication` STRICT, `DestinationRule` ISTIO_MUTUAL, và `VirtualService` retry cho `tax`/`order`.
   - Public entrypoints `storefront-bff`, `backoffice-bff`, `swagger-ui` được đặt `PERMISSIVE` để tương thích NGINX Ingress.

4. **Trạng thái test thực tế**:
   - Pod trong namespace `yas` đã chạy `2/2` sau khi inject sidecar.
   - `storefront.yas.local.com`, `backoffice.yas.local.com`, và `api.yas.local.com/swagger-ui/index.html` trả HTTP `200`.
   - `istioctl proxy-status` cho thấy proxy trong `yas` và `ingress-nginx` đã sync với `istiod`.

---

## 6. Ghi chú Kỹ thuật Quan trọng

1.  **BFF (Backend-for-Frontend) & Bảo mật**:
    *   Dự án sử dụng cơ chế bảo mật SameSite Cookie giữa trình duyệt và BFF (Spring Cloud Gateway).
    *   BFF giữ vai trò là OAuth2 Client, giao tiếp trực tiếp với Keycloak và tự động đính kèm Access Token (`TokenRelay`) vào header khi gửi request đến các API Resource Server phía sau. Điều này ngăn chặn việc lưu trữ token ở LocalStorage/SessionStorage của trình duyệt, nâng cao khả năng chống tấn công XSS.
2.  **Swagger UI (API Portal)**:
    *   Swagger UI đã được deploy độc lập trong namespace `yas` và được cấu hình định tuyến thông qua Ingress (`api.yas.local.com`).
    *   Nó sẽ gom toàn bộ tài liệu API từ các microservices backend về một giao diện tập trung để thuận tiện cho việc tích hợp hệ thống.
3.  **Change Data Capture (CDC)**:
    *   Debezium Connector lắng nghe các thay đổi dữ liệu (Insert/Update/Delete) từ cơ sở dữ liệu PostgreSQL (`postgres`) và đẩy vào Kafka topics.
    *   Một service background sẽ lắng nghe Kafka topics này và đồng bộ tức thời thông tin lên Elasticsearch để phục vụ chức năng tìm kiếm sản phẩm tốc độ cao.
