# Zuul Lab — Setup Status

## Fixed ✅

| # | What was fixed |
|---|----------------|
| 1 | `certs/` directory now mounted to all Zuul containers and ZooKeeper |
| 2 | ZooKeeper `secureClientPort=2281` enabled via `ZOO_CFG_EXTRA` with Netty factory |
| 3 | Replaced `zuul-launcher` with proper `nodepool-launcher` image |
| 4 | `nodepool.yaml` mounted to `nodepool-launcher` |
| 5 | `certs/` mounted to `nodepool-launcher` |

---

## Remaining Issues

### 1 (Critical) — ZooKeeper TLS missing `type=PEM` flags

**File:** `docker-compose.yaml` — `zookeeper` service, `ZOO_CFG_EXTRA`

**Current:**
```
ssl.keyStore.location=/certs/zookeeper.pem
ssl.trustStore.location=/certs/cacert.pem
```

**Problem:** ZooKeeper 3.9 with Netty won't parse PEM files unless the type is
explicitly declared. Without it the TLS handshake fails and Zuul cannot connect.

Note: `zookeeper.pem` already contains the cert + private key combined — that
part is correct.

**Fix — add the two type lines and empty passwords to `ZOO_CFG_EXTRA`:**

```yaml
ZOO_CFG_EXTRA: >-
  secureClientPort=2281
  serverCnxnFactory=org.apache.zookeeper.server.NettyServerCnxnFactory
  ssl.keyStore.location=/certs/zookeeper.pem
  ssl.keyStore.type=PEM
  ssl.keyStore.password=
  ssl.trustStore.location=/certs/cacert.pem
  ssl.trustStore.type=PEM
  ssl.trustStore.password=
```

---

### 2 (Critical) — `zuul.d/` config files not pushed to GitHub

**Files:** `zuul.d/jobs.yaml`, `zuul.d/pipelines.yaml`, `zuul.d/projects.yaml`

**Problem:** These files exist locally but Zuul's merger fetches config by doing
a `git fetch` against GitHub. The scheduler reads `main.yaml` which points to
`victorhugojt/zuul-config`, but that repo's `main` branch must actually contain
these files. Until they are pushed, `layout.jobs` only contains the built-in
`noop` and `layout.pipelines` is empty.

**Fix:**

```bash
# Inside a clone of victorhugojt/zuul-config
mkdir -p zuul.d
cp /path/to/lab-example/zuul.d/*.yaml zuul.d/
git add zuul.d/
git commit -m "Add Zuul CI config"
git push origin main
```

Also verify the **GitHub App is installed on `victorhugojt/zuul-config`**:
GitHub → Settings → GitHub Apps → *your app* → Install → select the repo.

After restarting the scheduler, check for loading errors:

```bash
curl http://localhost:9000/api/tenant/my-lab/config-errors
```

---

### 3 (Medium) — `check` pipeline misconfigured

**File:** `zuul.d/pipelines.yaml`

**Problem:**
- Uses `event: push` — that is a post-merge event, not a pre-merge check.
- No `success` / `failure` reporters — GitHub never receives a status update.

**Fix:**

```yaml
- pipeline:
    name: check
    manager: independent
    trigger:
      github:
        - event: pull_request
          action: [opened, changed, reopened]
        - event: pull_request
          action: comment
          comment: (?i)^\s*recheck\s*$
    success:
      github:
        status: success
    failure:
      github:
        status: failure
```

---

### 4 (Medium) — `zuul-node` has no SSH setup

**File:** `docker-compose.yaml` — `zuul-node` service

**Problem:** Nodepool SSHes as user `zuul` to `zuul-node:22` (as defined in
`nodepool.yaml`). For this to work the `zuul-node:lab` image must have:
1. `sshd` running and exposed on port 22
2. A `zuul` system user
3. The executor's public key (`/var/lib/zuul/.ssh/id_rsa.pub` from the
   `zuul-keys` volume) in `/home/zuul/.ssh/authorized_keys`

The executor key is generated on first start inside the `zuul-keys` volume.
The simplest approach for a lab is to bake a known SSH public key into the
`zuul-node:lab` Dockerfile and copy the matching private key into the
`zuul-keys` volume before starting.

---

### 5 (Low) — `zuul-web` unnecessarily mounts `github-app.pem`

**File:** `docker-compose.yaml` — `zuul-web` service

**Problem:** The web component reads data from ZooKeeper and the database. It
does not call the GitHub API directly and has no use for the App private key.

**Fix:** Remove this line from `zuul-web` volumes:

```yaml
- ./config/github-app.pem:/etc/zuul/github-app.pem:ro
```

---

## Priority Order

1. Push `zuul.d/` to GitHub + install GitHub App → fixes empty pipelines/jobs
2. Fix `ZOO_CFG_EXTRA` PEM types → fixes ZooKeeper TLS
3. Fix `check` pipeline trigger + reporters → jobs will actually report back
4. Fix `zuul-node` SSH → jobs will actually run
5. Remove `github-app.pem` from `zuul-web` → cleanup
