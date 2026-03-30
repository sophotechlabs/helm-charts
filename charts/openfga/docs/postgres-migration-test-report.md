# Bitnami Legacy Sub-Chart to extraObjects Migration Test Report

---

## Summary

Tested the end-to-end migration path from the deprecated bundled Bitnami PostgreSQL sub-chart (`postgresql.enabled: true`) to the `extraObjects` pattern using official Docker images, reusing the existing PVC to preserve data. **All data (store, authorization model, tuples) survived the migration intact. All permission checks passed.**

No chart code changes were required. The user provides the `datastore.uri` (including a known password set via `postgresql.auth.postgresPassword`) when using the bundled subchart, then switches to `datastore.uriSecret` pointing at a self-managed Secret when migrating to `extraObjects`.

---

## Step 1: Fresh Install with Bundled PostgreSQL

### Values (`step1-values.yaml`):
```yaml
replicaCount: 1

image:
  tag: v1.11.6

datastore:
  engine: postgres
  uri: "postgres://postgres:openfga-test-pw@openfga-postgresql:5432/postgres?sslmode=disable"
  applyMigrations: true

postgresql:
  enabled: true
  auth:
    postgresPassword: openfga-test-pw

playground:
  enabled: true

log:
  format: json
```

### Command:
```sh
helm install openfga ./charts/openfga -n openfga -f step1-values.yaml
```

### Output:
```
NAME: openfga
LAST DEPLOYED: Mon Mar 30 01:51:36 2026
NAMESPACE: openfga
STATUS: deployed
REVISION: 1
```

### Pod Status:
```
NAME                      READY   STATUS      RESTARTS   AGE
openfga-c58596655-ng9ts   1/1     Running     0          72s
openfga-migrate-dxz7h     0/1     Completed   0          70s
openfga-postgresql-0      1/1     Running     0          71s
```

### PVC Created:
```
NAME                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
data-openfga-postgresql-0   Bound    pvc-46d7fe4a-aeef-4a0a-be25-8776716ff2d5   8Gi        RWO            default
```

---

## Step 2: Add Test Data

### Create Store:
```sh
curl -s -X POST http://localhost:8080/stores \
  -H "Content-Type: application/json" \
  -d '{"name":"migration-test-store"}'
```
```json
{
  "id": "01KMYMY7S7STCSW349XCSYPP55",
  "name": "migration-test-store",
  "created_at": "2026-03-30T05:54:48.744477Z",
  "updated_at": "2026-03-30T05:54:48.744477Z"
}
```

### Write Authorization Model:
Types: `user`, `document` (owner/editor/viewer), `folder` (owner/viewer)
- editor inherits from owner
- viewer inherits from editor (document) or owner (folder)

```json
{"authorization_model_id": "01KMYMY8S7DYGY86T656S62JQ1"}
```

### Write 5 Tuples:
```json
{"writes":{"tuple_keys":[
  {"user":"user:alice","relation":"owner","object":"document:readme"},
  {"user":"user:bob","relation":"editor","object":"document:readme"},
  {"user":"user:charlie","relation":"viewer","object":"document:readme"},
  {"user":"user:alice","relation":"owner","object":"folder:projects"},
  {"user":"user:bob","relation":"viewer","object":"folder:projects"}
]}}
```
Result: `{}` (success)

### Pre-Migration Verification:
```
Tuple count: 5

"user:alice -> owner -> document:readme"
"user:bob -> editor -> document:readme"
"user:charlie -> viewer -> document:readme"
"user:alice -> owner -> folder:projects"
"user:bob -> viewer -> folder:projects"

bob viewer document:readme   -> true
charlie owner document:readme -> false
```

---

## Step 3: Migrate to extraObjects Pattern

### 3a. Set PV Reclaim Policy to Retain

Following the migration guide, set the PV reclaim policy to `Retain` before removing the subchart:

```sh
PV_NAME=$(kubectl get pvc data-openfga-postgresql-0 -n openfga -o jsonpath='{.spec.volumeName}')
kubectl patch pv "${PV_NAME}" -p '{"spec":{"persistentVolumeReclaimPolicy":"Retain"}}'
```
```
persistentvolume/pvc-46d7fe4a-aeef-4a0a-be25-8776716ff2d5 patched
PV pvc-46d7fe4a-aeef-4a0a-be25-8776716ff2d5 -> Retain
```

### 3b. Bitnami Data Directory Compatibility Note

The bitnami PostgreSQL image stores data at `PGDATA=/bitnami/postgresql/data` and generates `postgresql.conf` and `pg_hba.conf` outside the PGDATA directory. The official `postgres` Docker image expects these files inside PGDATA.

**Solution:** An init container creates the missing config files before the postgres container starts.

### 3c. Values (`step2-values.yaml`):
```yaml
replicaCount: 1

image:
  tag: v1.11.6

datastore:
  engine: postgres
  uriSecret: openfga-postgres-credentials
  applyMigrations: true

postgresql:
  enabled: false

playground:
  enabled: true

log:
  format: json

extraObjects:
  - apiVersion: v1
    kind: Secret
    metadata:
      name: openfga-postgres-credentials
    stringData:
      uri: "postgres://postgres:openfga-test-pw@openfga-postgres:5432/postgres?sslmode=disable"
  - apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: openfga-postgres
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: openfga-postgres
      template:
        metadata:
          labels:
            app: openfga-postgres
        spec:
          initContainers:
            - name: fix-bitnami-conf
              image: busybox
              command:
                - sh
                - -c
                - |
                  PGDATA=/data/data
                  if [ ! -f "$PGDATA/postgresql.conf" ]; then
                    cat > "$PGDATA/postgresql.conf" <<'CONF'
                  listen_addresses = '*'
                  max_connections = 100
                  shared_buffers = 128MB
                  dynamic_shared_memory_type = posix
                  max_wal_size = 1GB
                  min_wal_size = 80MB
                  log_timezone = 'UTC'
                  datestyle = 'iso, mdy'
                  timezone = 'UTC'
                  lc_messages = 'en_US.utf8'
                  lc_monetary = 'en_US.utf8'
                  lc_numeric = 'en_US.utf8'
                  lc_time = 'en_US.utf8'
                  default_text_search_config = 'pg_catalog.english'
                  CONF
                    echo "Created postgresql.conf"
                  fi
                  if [ ! -f "$PGDATA/pg_hba.conf" ]; then
                    cat > "$PGDATA/pg_hba.conf" <<'HBA'
                  local   all   all                 trust
                  host    all   all   127.0.0.1/32  scram-sha-256
                  host    all   all   ::1/128       scram-sha-256
                  host    all   all   0.0.0.0/0     scram-sha-256
                  HBA
                    echo "Created pg_hba.conf"
                  fi
              volumeMounts:
                - name: data
                  mountPath: /data
          containers:
            - name: postgres
              image: postgres:15
              ports:
                - containerPort: 5432
              env:
                - name: POSTGRES_USER
                  value: postgres
                - name: POSTGRES_PASSWORD
                  value: openfga-test-pw
                - name: PGDATA
                  value: /bitnami/postgresql/data
              volumeMounts:
                - name: data
                  mountPath: /bitnami/postgresql
          volumes:
            - name: data
              persistentVolumeClaim:
                claimName: data-openfga-postgresql-0
  - apiVersion: v1
    kind: Service
    metadata:
      name: openfga-postgres
    spec:
      selector:
        app: openfga-postgres
      ports:
        - port: 5432
          targetPort: 5432
```

### 3d. Upgrade Command:
```sh
kubectl delete job openfga-migrate -n openfga
helm upgrade openfga ./charts/openfga -n openfga -f step2-values.yaml
```

### Output:
```
Release "openfga" has been upgraded. Happy Helming!
NAME: openfga
LAST DEPLOYED: Mon Mar 30 01:55:20 2026
NAMESPACE: openfga
STATUS: deployed
REVISION: 2
```

---

## Step 4: Post-Migration Verification

### Pod Status:
```
NAME                                READY   STATUS      RESTARTS   AGE
openfga-79c9b6fc75-j62wn            1/1     Running     0          40s
openfga-migrate-2jjwt               0/1     Completed   0          35s
openfga-postgres-5bfc6ccc9f-44nn6   1/1     Running     0          39s
```

Key observations:
- `openfga-postgresql-0` (bitnami StatefulSet) is **gone**
- `openfga-postgres-*` (extraObjects Deployment) is **running** with the same PVC
- `openfga-migrate-*` job **completed** successfully
- `openfga-*` app pod is **running** and connected to the new postgres

### Health Check:
```json
{"status":"SERVING"}
```

### PVC (preserved):
```
NAME                        STATUS   VOLUME                                     CAPACITY   ACCESS MODES   STORAGECLASS
data-openfga-postgresql-0   Bound    pvc-46d7fe4a-aeef-4a0a-be25-8776716ff2d5   8Gi        RWO            default
```

### Store (preserved):
```json
{
  "stores": [
    {
      "id": "01KMYMY7S7STCSW349XCSYPP55",
      "name": "migration-test-store",
      "created_at": "2026-03-30T05:54:48.744477Z",
      "updated_at": "2026-03-30T05:54:48.744477Z"
    }
  ]
}
```

### Tuple Count: **5** (all preserved)

### All Tuples (preserved):
```
"user:alice -> owner -> document:readme"
"user:bob -> editor -> document:readme"
"user:charlie -> viewer -> document:readme"
"user:alice -> owner -> folder:projects"
"user:bob -> viewer -> folder:projects"
```

### Authorization Model ID (preserved): `01KMYMY8S7DYGY86T656S62JQ1`

### Permission Checks:

| # | Check | Expected | Actual | Pass |
|---|-------|----------|--------|------|
| 1 | bob viewer document:readme | true | **true** | YES |
| 2 | alice owner folder:projects | true | **true** | YES |
| 3 | charlie viewer document:readme | true | **true** | YES |
| 4 | charlie owner document:readme (negative) | false | **false** | YES |

---

## Key Findings

1. **Data Integrity:** All stores, authorization models, and relationship tuples survived the migration from the bitnami subchart to extraObjects with PVC reuse. Zero data loss.

2. **No Chart Code Changes Required:** The existing chart works as-is. Users provide their own password via `postgresql.auth.postgresPassword` and construct the `datastore.uri` accordingly.

3. **Bitnami Compatibility Gotcha:** When migrating from bitnami PostgreSQL to official Docker images, `postgresql.conf` and `pg_hba.conf` must be created in PGDATA via an init container, because bitnami stores these config files outside the data directory.

4. **PV Reclaim Policy:** Must be set to `Retain` before the migration upgrade, otherwise the PV will be deleted when the bitnami StatefulSet is removed.

5. **Version Match:** Using `postgres:15` (matching bitnami's PG 15.4) for the migration target avoids potential major-version data directory incompatibilities.

6. **Migration is a single `helm upgrade`:** Once the values file is prepared, the migration is a single command. The bitnami StatefulSet is removed, the extraObjects Deployment takes over the same PVC, and OpenFGA reconnects seamlessly.
