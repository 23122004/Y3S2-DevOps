# Cluster Upgrade & Recovery Walkthrough

## 1. Hiện Tượng & Nguyên Nhân
- **Sự cố**: Môi trường dev trả về lỗi `503 Service Unavailable`, staging trả về lỗi `Not connect upstream` (Gateway Timeout).
- **Nguyên nhân**: Node cũ `devops-project02-large-3cw2nm` bị sập chuyển sang trạng thái **`NotReady`** do cạn kiệt RAM vật lý (Out Of Memory). Node này phải chịu tải rất nặng khi chạy PostgreSQL, Kafka, Zookeeper, Elasticsearch Operator, Redis, Tempo, Loki Agent cùng 15 pod microservices của namespace dev.

---

## 2. Các Bước Khắc Phục (Nâng Cấp Node Pool)

### Bước 2.1: Khởi tạo Node Pool Memory-Optimized Mới
Sử dụng `doctl` tạo node pool mới cấu hình `m-2vcpu-16gb` (Memory-Optimized) với số lượng 2 node:
```bash
doctl kubernetes cluster node-pool create 01333b63-5474-4eec-a515-98030c5c872d --name devops-project02-mem-opt --size m-2vcpu-16gb --count 2
```

### Bước 2.2: Scale up Node Pool lên 3 Nodes
Sau khi 2 node mới online, chúng ta phát hiện CPU Requests của các pod lớn hơn dung lượng 4 vCPU của 2 node mới (lỗi `Insufficient cpu`). Do đó, tiến hành scale node pool mới lên **3 nodes** (Tổng cộng: 6 vCPU và 48GB RAM):
```bash
doctl kubernetes cluster node-pool update 01333b63-5474-4eec-a515-98030c5c872d e66d8652-c711-474b-a551-fa8dc39b0600 --count 3
```

### Bước 2.3: Di chuyển Workloads (Cordon & Drain)
- Cordon các node cũ để ngưng lập lịch pod mới:
  ```bash
  kubectl cordon devops-project02-large-3cw2n7 devops-project02-large-3cw2nm devops-project02-large-3cvc0g
  ```
- Drain các node cũ để dời pod sang node mới (sử dụng `--disable-eviction=true` để ghi đè PDB tránh kẹt):
  ```bash
  kubectl drain devops-project02-large-3cw2n7 --ignore-daemonsets --delete-emptydir-data --force --disable-eviction=true
  kubectl drain devops-project02-large-3cvc0g --ignore-daemonsets --delete-emptydir-data --force --disable-eviction=true
  ```

### Bước 2.4: Xóa Node Pool Cũ
Giải phóng 3 node cũ trên DigitalOcean:
```bash
doctl kubernetes cluster node-pool delete 01333b63-5474-4eec-a515-98030c5c872d b47cdbd4-bd5b-4650-9faa-42198baeb473 --force
```

### Bước 2.5: Cập nhật Cấu hình NodeSelector của Observability
Cập nhật `nodeSelector` trong các file values (`loki.values.yaml`, `tempo.values.yaml`, `prometheus.values.yaml`) từ hostname cũ `devops-project02-large-3cvc0g` sang nhãn node pool mới:
```yaml
  nodeSelector:
    doks.digitalocean.com/node-pool: devops-project02-mem-opt
```
Chạy script `deploy-observability.ps1` để nâng cấp các chart:
```powershell
powershell -File .\k8s\deploy\observability\deploy-observability.ps1
```

---

## 3. Kết Quả Xác Minh
- **Trạng thái Nodes**: 3 node memory optimized mới hoạt động ở trạng thái `Ready`.
- **Môi trường Dev & Staging**: Toàn bộ 14 services đều đã khởi động lại thành công, không còn pod nào bị kẹt ở trạng thái `Pending` hay `Terminating`.
- **Dịch vụ Observability**: Grafana (`3/3 Running`), Prometheus (`2/2 Running`), Tempo, Loki đều hoạt động ổn định trên hạ tầng mới.
