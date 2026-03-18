# Zuul Worker Node

## What is the worker node?

The worker node is the machine where your CI jobs actually run. Every Ansible
playbook defined in your jobs is executed on this node via SSH from the executor.

The Zuul platform (scheduler, executor, web, nodepool) runs separately and
never executes your job code directly.

```
┌────────────────────────────────────────────────────┐
│  GCP VM                                            │
│                                                    │
│  ┌─────────────────────────────────────────────┐   │
│  │  docker-compose.yml                         │   │
│  │                                             │   │
│  │  ZUUL PLATFORM          WORKER NODE         │   │
│  │  ┌─────────────┐        ┌───────────────┐   │   │
│  │  │ zookeeper   │        │               │   │   │
│  │  │ mysql       │   SSH  │  zuul-node    │   │   │
│  │  │ scheduler   │───────▶│  (your image) │   │   │
│  │  │ executor    │        │               │   │   │
│  │  │ web         │        └───────────────┘   │   │
│  │  │ nodepool    │                            │   │
│  │  └─────────────┘                            │   │
│  └─────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────┘
```

---

## How the platform finds the node

There is a 4-step chain linking your Docker image to a Zuul job:

```
node-image/Dockerfile
      │  docker build -t zuul-node:lab .
      ▼
docker-compose.yml  →  image: zuul-node:lab
                        hostname: zuul-node
      │
      ▼
nodepool.yaml       →  host: zuul-node
                        label: linux-executor
      │
      ▼
.zuul.yaml          →  nodeset:
                          label: linux-executor
```

The only connection between your image and Zuul is the **label name**.
Change the image, rebuild, restart the container — Zuul keeps working as long
as the label still exists in Nodepool.

---

## File 1 — `node-image/Dockerfile`

This is the image you fully control. Add any tools your CI jobs need.

```dockerfile
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# ── System tools ──────────────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y \
    openssh-server \
    sudo \
    curl \
    wget \
    git \
    build-essential \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# ── Docker CLI (for jobs that build or push images) ───────────────────────────
RUN curl -fsSL https://get.docker.com | sh

# ── Node.js 20 (for frontend jobs) ───────────────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# ── Python CI tools ───────────────────────────────────────────────────────────
RUN pip3 install flake8 pylint pytest black

# ── JavaScript CI tools ───────────────────────────────────────────────────────
RUN npm install -g eslint prettier

# ── Zuul user setup ───────────────────────────────────────────────────────────
# The executor always SSHes in as the "zuul" user.
# NOPASSWD sudo allows playbooks to run privileged commands.
RUN useradd -m -s /bin/bash zuul \
    && echo "zuul ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && usermod -aG docker zuul \
    && mkdir -p /home/zuul/.ssh /run/sshd \
    && chown -R zuul:zuul /home/zuul/.ssh \
    && chmod 700 /home/zuul/.ssh

# ── SSH authorized key ────────────────────────────────────────────────────────
# Copy the executor's public key so it can SSH in without a password.
# Get the key with: docker exec zuul-executor cat /var/lib/zuul/.ssh/id_rsa.pub
COPY authorized_keys /home/zuul/.ssh/authorized_keys
RUN chmod 600 /home/zuul/.ssh/authorized_keys \
    && chown zuul:zuul /home/zuul/.ssh/authorized_keys

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
```

Build the image on the GCP VM:
```bash
cd ~/zuul-lab/node-image
docker build -t zuul-node:lab .
```

---

## File 2 — `docker-compose.yml` (worker node section)

The `zuul-node` service is the last service in the file, after all platform
services.

```yaml
  # ---------------------------------------------------------------------------
  # Worker Node — where CI jobs actually run
  # Built from node-image/Dockerfile — customize this image to add tools.
  # Nodepool SSHes into this container to run Ansible playbooks.
  # ---------------------------------------------------------------------------
  zuul-node:
    image: zuul-node:lab            # built from node-image/Dockerfile
    container_name: zuul-node
    hostname: zuul-node             # DNS name used by nodepool to reach it
    restart: unless-stopped
```

No ports need to be published. Nodepool reaches the node over the internal
Docker network using the hostname `zuul-node`.

---

## File 3 — `config/nodepool.yaml` (node registration)

```yaml
zookeeper-servers:
  - host: zookeeper
    port: 2281

zookeeper-tls:
  cert: /etc/nodepool/certs/clientcert.pem
  key: /etc/nodepool/certs/clientkey.pem
  ca: /etc/nodepool/certs/cacert.pem

webapp:
  listen_address: '0.0.0.0'
  port: 8005

providers:
  - name: local-static
    driver: static
    pools:
      - name: main
        nodes:
          - name: zuul-node
            host: zuul-node         # must match container hostname
            username: zuul          # must match the user in the Dockerfile
            connection-port: 22
            host-key-checking: false
            labels:
              - linux-executor      # the label Zuul jobs will request

labels:
  - name: linux-executor
    min-ready: 1                    # keep 1 node ready before jobs arrive
```

---

## File 4 — `zuul-config/.zuul.yaml` (node request in base job)

```yaml
- job:
    name: base
    parent: null
    run: playbooks/base.yaml
    post-run: playbooks/post-base.yaml
    timeout: 1800
    nodeset:
      nodes:
        - name: controller          # Ansible inventory group name
          label: linux-executor     # must match the label in nodepool.yaml
```

Every job that inherits from `base` automatically uses the same node.
A child job can override the nodeset to use a different label:

```yaml
- job:
    name: recordtec-integration-tests
    parent: base
    nodeset:
      nodes:
        - name: controller
          label: linux-heavy        # requests a different node type
```

---

## Updating the node image

When you need to add or update tools on the worker node:

```bash
# 1. Edit the Dockerfile
vim ~/zuul-lab/node-image/Dockerfile

# 2. Rebuild the image
cd ~/zuul-lab/node-image
docker build -t zuul-node:lab .

# 3. Restart only the worker node (platform stays running)
cd ~/zuul-lab
docker compose restart zuul-node

# 4. Verify nodepool sees it as ready
docker exec nodepool-launcher nodepool list
```

The Zuul platform containers (scheduler, executor, web, nodepool) do not need
to be restarted. Only `zuul-node` restarts.

---

## What is pre-installed vs installed at job runtime

| Approach | When | Example |
|---|---|---|
| Pre-installed in Dockerfile | Image build time — always available, fast | Python, Node.js, Docker, git |
| Installed in `base.yaml` playbook | Every job start — adds seconds | Project-agnostic setup steps |
| Installed in job playbook | Per job — slowest, most flexible | Repo-specific dependencies |

**Best practice:** pre-install everything that is shared across many jobs in
the Dockerfile. Install only repo-specific dependencies in the job playbook.

---

## Verifying the node is connected

```bash
# Check nodepool sees the node as ready
docker exec nodepool-launcher nodepool list

# Expected output:
# | ID         | Provider     | Label          | Server ID | State | Locked   |
# | 0000000000 | local-static | linux-executor | zuul-node | ready | unlocked |

# Test SSH from executor to node manually
docker exec zuul-executor ssh \
  -i /var/lib/zuul/.ssh/id_rsa \
  -o StrictHostKeyChecking=no \
  zuul@zuul-node echo "SSH works"
```
