# Loki fix runbook — làm cho Logs (Mục 10) chạy LIVE

> **Trạng thái:** ✅ **ĐÃ APPLY 2026-07-12** — `helm upgrade loki` **revision 9**,
> pod `loki-0` (SingleBinary) 2/2 Running, PVC `storage-loki-0` (10Gi) Bound,
> query `{namespace="staging"}` trả log thật, Grafana→Loki HTTP 200.
> Patch: `k8s/deploy/observability/loki.values.fixed.yaml` (chart `grafana/loki` v7.0.0).
>
> **Dọn PVC cũ mồ côi (tùy chọn):** SSD cũ để lại `data-loki-write-0` (10Gi,
> không còn dùng). Xoá để khỏi tốn tiền: `kubectl delete pvc -n observability data-loki-write-0`.
> Các mục 3–4 dưới đây là để tham khảo/tái lập; đã chạy rồi.

## 1. Vì sao Loki đang hỏng (đã kiểm chứng trên cụm 2026-07-12)

Pod `loki-write/read/backend` **Running** nhưng không lưu được log:

```
failed to flush chunks: store put chunk: mkdir fake: read-only file system
failed to CAS cluster seed key: open loki_cluster_seed.json: read-only file system
```

Nguyên nhân gốc trong cấu hình cũ (`loki.values.yaml` + `--set loki.useTestSchema=true`):

- `deploymentMode` mặc định = **SimpleScalable** (write/read/backend) → **bắt buộc**
  phải có **object storage dùng chung** (S3/GCS/minio). Nhưng `minio.enabled: false`,
  không cấu hình S3, và `persistence.enabled: false` (emptyDir trên root fs
  read-only) → ingester không flush được chunk.
- `useTestSchema: true` là schema smoke-test, không dùng để ingest thật.
- `write/read` giới hạn RAM **128Mi** → OOM/crashloop.

Promtail + OTel Collector vẫn đẩy log về `loki-gateway`, nhưng Loki **rớt hết**.

## 2. Cách sửa (patch đã soạn)

Chuyển sang **SingleBinary + filesystem trên PVC DigitalOcean block-storage**:
không cần object storage, nhẹ nhất, và **không đổi phía client** (promtail /
collector vẫn push vào Service `loki-gateway`).

Patch render ra: 1 `StatefulSet loki` (replicas=1, volumeClaimTemplate `storage`
10Gi) + `Deployment loki-gateway`; bỏ hẳn write/read/backend; không minio.

## 3. Apply (chạy khi muốn — KHÔNG có trong CI, Loki là helm release thường)

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
cd /home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps

# QUAN TRỌNG: KHÔNG kèm --set loki.useTestSchema=true (patch đã có schemaConfig thật)
helm upgrade loki grafana/loki --version 7.0.0 \
  --namespace observability \
  -f k8s/deploy/observability/loki.values.fixed.yaml
```

> Nếu cài mới từ đầu: sửa `k8s/deploy/setup-cluster.sh` dòng ~72 — **bỏ**
> `--set loki.useTestSchema=true` và trỏ `-f` tới `loki.values.fixed.yaml`.

## 4. Verify

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml

# (a) chỉ còn statefulset 'loki' (1/1) + loki-gateway; write/read/backend biến mất
kubectl get pods -n observability | grep -E 'loki'
kubectl get pvc -n observability | grep loki        # storage-loki-0 = Bound

# (b) không còn lỗi read-only; ingester khỏe
kubectl logs -n observability loki-0 --tail=20 | grep -iE 'error|read-only' || echo "no errors"

# (c) Loki nhận được log qua gateway (đợi ~1-2 phút cho promtail đẩy)
kubectl -n observability port-forward svc/loki-gateway 3100:80 >/tmp/pfloki.log 2>&1 &
sleep 5
curl -s 'http://localhost:3100/loki/api/v1/labels' | head -c 300      # phải trả list label
curl -s -G 'http://localhost:3100/loki/api/v1/query_range' \
  --data-urlencode 'query={namespace="staging"}' --data-urlencode 'limit=5' | head -c 400
```

Rồi mở **Grafana → Explore → datasource Loki** và chạy LogQL, ví dụ:

```logql
{k8s_namespace_name="staging", service_name="product"}
```

## 5. Rollback (nếu có sự cố)

```bash
export KUBECONFIG=/home/huy/Documents/University/DevOps/Project02/Y3S2-DevOps/teammate-kubeconfig.yaml
helm rollback loki -n observability            # về revision trước
# PVC 'storage-loki-0' còn lại; xoá nếu muốn dọn hẳn:
# kubectl delete pvc -n observability storage-loki-0
```

## 6. Chi phí / tài nguyên

- PVC 10Gi block-storage ≈ **$1/tháng**.
- SingleBinary ~256–512Mi RAM (1 pod) thay cho 3 pod SSD → **nhẹ hơn** hiện tại.
- Cụm đang 8 node, RAM 40–95% → thừa chỗ cho 1 pod này.
