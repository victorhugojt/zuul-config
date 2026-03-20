# Zuul CI/CD Lab — Setup Summary

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  GCP VM  (35.239.241.176)  —  network: my-poc-vpc               │
│                                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  docker-compose.yaml  (~/zuul-lab/)                      │   │
│  │                                                          │   │
│  │  INFRASTRUCTURE          ZUUL PLATFORM                   │   │
│  │  ┌────────────┐          ┌─────────────┐                 │   │
│  │  │ zookeeper  │◄─TLS────►│  scheduler  │                 │   │
│  │  │ (port 2281)│          │  executor   │                 │   │
│  │  └────────────┘          │  web :9000  │                 │   │
│  │  ┌────────────┐          │  nodepool   │                 │   │
│  │  │   mysql    │◄─────────┤             │                 │   │
│  │  └────────────┘          └──────┬──────┘                │   │
│  │                                 │ SSH                    │   │
│  │                          ┌──────▼──────┐                │   │
│  │                          │  zuul-node  │  ← CI jobs run │   │
│  │                          │  (port 22)  │    here        │   │
│  │                          └─────────────┘                │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
         ▲                          ▲
         │ webhooks                 │ dashboard
    GitHub.com              Your browser
                         http://35.239.241.176:9000
```

### How a CI job flows

```
GitHub PR opened
      │
      ▼ webhook (port 9000)
zuul-scheduler  ──► reads .zuul.yaml from config repo
      │
      ▼
zuul-executor   ──► SSH into zuul-node
      │
      ▼
zuul-node       ──► runs Ansible playbooks
      │
      ▼
GitHub PR       ──► check status updated
```

---

## File Structure

```
~/zuul-lab/
├── docker-compose.yaml          # All services definition
├── config/
│   ├── zuul.conf                # Main Zuul configuration
│   ├── main.yaml                # Tenant + project config
│   ├── nodepool.yaml            # Worker node registration
│   ├── github-app.pem           # GitHub App private key
│   └── certs/                   # ZooKeeper TLS certificates
│       ├── cacert.pem           # Certificate Authority
│       ├── zookeeper.pem        # ZK server keystore (cert+key)
│       ├── zookeepercert.pem    # ZK server certificate
│       ├── zookeeperkey.pem     # ZK server private key
│       ├── clientcert.pem       # Client certificate (Zuul services)
│       └── clientkey.pem        # Client private key
└── node-image/
    └── Dockerfile               # Worker node image
```

---

## Key Config Files

### `config/zuul.conf`

```ini
[gearman]
server=scheduler

[gearman_server]
start=true

[zookeeper]
hosts=zookeeper:2281           # TLS port (not 2181)
tls_cert=/etc/zuul/certs/clientcert.pem
tls_key=/etc/zuul/certs/clientkey.pem
tls_ca=/etc/zuul/certs/cacert.pem

[keystore]
password=zuul_keystore_pass    # Required for secret encryption

[database]
dburi=mysql+pymysql://zuul:zuul_pass@mysql/zuul

[scheduler]
tenant_config=/etc/zuul/main.yaml

[web]
listen_address=0.0.0.0
port=9000
root=http://35.239.241.176:9000

[executor]
private_key_file=/var/lib/zuul/.ssh/id_rsa

[connection github]
driver=github
server=github.com
app_id=YOUR_GITHUB_APP_ID
app_key=/etc/zuul/github-app.pem
webhook_token=YOUR_WEBHOOK_SECRET
```

### `config/main.yaml`

```yaml
- tenant:
    name: my-lab
    source:
      github:
        config-projects:
          - victorhugojt/zuul-config
        untrusted-projects:
          - victorhugojt/recordtec
          - victorhugojt/recordtec-fe
```

### `config/nodepool.yaml`

```yaml
zookeeper-servers:
  - host: zookeeper
    port: 2281                  # TLS port

zookeeper-tls:
  cert: /etc/nodepool/certs/clientcert.pem
  key: /etc/nodepool/certs/clientkey.pem
  ca: /etc/nodepool/certs/cacert.pem

providers:
  - name: local-static
    driver: static
    pools:
      - name: main
        nodes:
          - name: zuul-node
            host: zuul-node     # dedicated worker container
            username: zuul
            connection-port: 22
            host-key-checking: false
            labels:
              - linux-executor

labels:
  - name: linux-executor
    min-ready: 1
```

---

## Issues Resolved

### 1. `nodepool.yaml` mounted as a directory (not a file)
**Error:** `IsADirectoryError: /etc/nodepool/nodepool.yaml`  
**Cause:** Docker created a directory instead of a file because the host path didn't exist when the container started.  
**Fix:** Stopped the stack, deleted the directory, recreated `config/nodepool.yaml` as a proper file, restarted.

### 2. Container name conflicts on restart
**Error:** `Conflict. The container name "/zuul-mysql" is already in use`  
**Cause:** Previous containers from a different compose run were still registered.  
**Fix:**
```bash
docker compose down --remove-orphans
docker rm -f zuul-mysql zuul-zookeeper zuul-scheduler zuul-executor zuul-web nodepool-launcher zuul-node
docker compose up -d
```

### 3. `Exception: Database configuration is required`
**Error:** Scheduler crashed before reading `[database]` section.  
**Cause:** `zuul.conf` was not mounted correctly (directory instead of file).  
**Fix:** Same as issue 1 — recreated config files as proper files.

### 4. ZooKeeper TLS required by newer Zuul versions
**Error:** `A TLS ZooKeeper connection is required; please supply the tls_* zookeeper config values`  
**Cause:** Zuul (latest) mandates TLS for ZooKeeper. The lab was using plain port `2181`.  
**Fix:**
- Generated self-signed TLS certs (`cacert.pem`, `zookeeper.pem`, `clientcert.pem`, `clientkey.pem`)
- Configured ZooKeeper with `secureClientPort=2281` + `NettyServerCnxnFactory`
- Updated `zuul.conf` `[zookeeper]` to use port `2281` + `tls_*` paths
- Updated `nodepool.yaml` to use port `2281` + `zookeeper-tls` section
- Mounted `config/certs` into all services in `docker-compose.yaml`

```bash
# Cert generation commands
CERTS=~/zuul-lab/config/certs
mkdir -p $CERTS
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -subj "/CN=zuul-ca" \
  -keyout $CERTS/cakey.pem -out $CERTS/cacert.pem
# ... (see deploy notes for full commands)
chmod 644 $CERTS/*.pem   # must be 644, not 600 — ZK runs as different user
```

### 5. ZooKeeper cert `AccessDeniedException`
**Error:** `java.nio.file.AccessDeniedException: /certs/zookeeper.pem`  
**Cause:** Certs were generated with `chmod 600` (owner-only). ZooKeeper runs as a different user inside the container.  
**Fix:** `chmod 644 ~/zuul-lab/config/certs/*.pem`

### 6. ZooKeeper TLS handshake failure
**Error:** `Unsuccessful handshake with session 0x0`  
**Cause:** `zookeeper.pem` keystore was malformed.  
**Fix:** Regenerated the combined keystore (cert must come before key):
```bash
cat $CERTS/zookeepercert.pem $CERTS/zookeeperkey.pem > $CERTS/zookeeper.pem
```

### 7. Scheduler connecting to wrong ZooKeeper port
**Error:** `Len error 369295616` (= hex `0x16030100` = TLS ClientHello on plain port)  
**Cause:** The VM's `zuul.conf` still had `hosts=zookeeper:2181` (old port).  
**Fix:** `sed -i 's/hosts=zookeeper:2181/hosts=zookeeper:2281/' ~/zuul-lab/config/zuul.conf`

### 8. `RuntimeError: No key store password configured!`
**Error:** Scheduler crashed after connecting to ZooKeeper.  
**Cause:** Newer Zuul versions require a `[keystore]` section in `zuul.conf` for encrypting secrets in the database.  
**Fix:** Added to `zuul.conf`:
```ini
[keystore]
password=zuul_keystore_pass
```

### 9. Docker iptables NAT rule had wrong port (`900` instead of `9000`)
**Error:** `curl localhost:9000` gave `Connection reset by peer` from inside the VM.  
**Cause:** Docker's NAT rule was `to:172.18.0.7:900` (missing a digit), so port forwarding was broken.  
**Fix:** Removed and recreated the `zuul-web` container so Docker rebuilt the iptables rule correctly.

### 10. GCP firewall rule on wrong network
**Error:** Port 9000 unreachable from outside even after creating the firewall rule.  
**Cause:** Original firewall scripts used `--network=default` but the VM's NIC is on `my-poc-vpc`.  
**Fix:** Updated `fix_gcp_firewall.sh` to use `--network=my-poc-vpc` and recreated the rule.

---

## Useful Commands

```bash
# Status
docker compose -f ~/zuul-lab/docker-compose.yaml ps

# Logs
docker compose -f ~/zuul-lab/docker-compose.yaml logs -f zuul-scheduler
docker compose -f ~/zuul-lab/docker-compose.yaml logs -f zuul-web

# Verify worker node is registered
docker exec nodepool-launcher nodepool list

# Test SSH from executor to worker node
docker exec zuul-executor ssh \
  -i /var/lib/zuul/.ssh/id_rsa \
  -o StrictHostKeyChecking=no \
  zuul@zuul-node echo "SSH works"

# Full restart
docker compose -f ~/zuul-lab/docker-compose.yaml down
docker compose -f ~/zuul-lab/docker-compose.yaml up -d

# Update firewall if your IP changes
cd ~/zuul-lab && bash fix_gcp_firewall.sh
```

---

## Dashboard & Webhook URLs

| Purpose | URL |
|---|---|
| Zuul Dashboard | `http://35.239.241.176:9000` |
| GitHub Webhook | `http://35.239.241.176:9000/api/connection/github/payload` |
