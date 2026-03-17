# Zuul Node Provisioning with Nodepool

## Overview

Nodepool is the component that provisions and manages the nodes (workers) where
Zuul jobs run. It sits between Zuul and the underlying infrastructure, handling
the full lifecycle of nodes: request → provision → assign → delete.

```
Zuul Scheduler
     │ "I need a node with label linux-executor"
     ▼
Nodepool Launcher
     │ provisions a node from the configured provider
     ▼
Node (VM / container / pod)
     │ ready, SSH accessible
     ▼
Zuul Executor runs Ansible playbooks on the node
```

---

## Nodepool Drivers

Each driver answers the question: **"where do nodes come from?"**

| Driver | What it provisions | Best for |
|---|---|---|
| `static` | Pre-existing machines or containers (always on) | Lab / dev |
| `docker` | Docker containers spun up on demand | Lab / dev |
| `openstack` | OpenStack VMs | On-prem cloud |
| `aws` | EC2 instances | AWS |
| `gce` | GCP Compute Engine VMs | Production on GCP |
| `kubernetes` | Kubernetes pods | K8s clusters |

---

## Current Lab Setup — Static Driver

The lab uses the `static` driver pointing to a persistent `zuul-node` Docker
container. The node is always on and reused across jobs.

```
nodepool.yaml (current)

providers:
  - name: local-static
    driver: static
    pools:
      - name: main
        nodes:
          - name: zuul-node
            labels:
              - linux-executor     ← matches nodeset label in .zuul.yaml
            host: zuul-node        ← Docker container hostname
            username: zuul
            connection-port: 22
            host-key-checking: false

labels:
  - name: linux-executor
    min-ready: 1                   ← keep 1 node warm at all times
```

**Limitation:** nodes are never discarded between jobs, so state can leak.
This is acceptable for a lab but not for production.

---

## Path 1 — Improve the Lab Node (custom Docker image)

Rebuild `zuul-node:lab` with all common tools pre-installed so jobs don't
need to install them at runtime.

```dockerfile
# ~/zuul-lab/node-image/Dockerfile

FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# System tools
RUN apt-get update && apt-get install -y \
    openssh-server sudo curl wget git \
    python3 python3-pip python3-venv \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Docker CLI (for jobs that build/push images)
RUN curl -fsSL https://get.docker.com | sh

# Node.js 20
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs

# Common Python tools
RUN pip3 install flake8 pylint pytest black

# Common JS tools
RUN npm install -g eslint prettier

# Zuul user
RUN useradd -m -s /bin/bash zuul \
    && echo "zuul ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers \
    && usermod -aG docker zuul \
    && mkdir -p /home/zuul/.ssh /run/sshd \
    && chown -R zuul:zuul /home/zuul/.ssh \
    && chmod 700 /home/zuul/.ssh

COPY authorized_keys /home/zuul/.ssh/authorized_keys
RUN chmod 600 /home/zuul/.ssh/authorized_keys \
    && chown zuul:zuul /home/zuul/.ssh/authorized_keys

EXPOSE 22
CMD ["/usr/sbin/sshd", "-D"]
```

Rebuild and restart:
```bash
cd ~/zuul-lab/node-image
docker build -t zuul-node:lab .
cd ~/zuul-lab
docker compose restart zuul-node
```

No changes to `nodepool.yaml` needed — same label, same config, better image.

---

## Path 2 — Multiple Node Types (labels)

Define different node labels for different job requirements. Light nodes for
fast jobs, heavy nodes for resource-intensive ones.

### nodepool.yaml

```yaml
providers:
  - name: local-static
    driver: static
    pools:
      - name: main
        nodes:
          - name: zuul-node-light
            labels:
              - linux-light          # for lint and unit tests
            host: zuul-node-light
            username: zuul
            connection-port: 22
            host-key-checking: false

          - name: zuul-node-heavy
            labels:
              - linux-heavy          # for integration tests and Docker builds
            host: zuul-node-heavy
            username: zuul
            connection-port: 22
            host-key-checking: false

labels:
  - name: linux-light
    min-ready: 2                     # keep 2 warm for fast parallel jobs
  - name: linux-heavy
    min-ready: 1
```

### Job nodeset override (in untrusted repo .zuul.yaml)

```yaml
- job:
    name: recordtec-lint
    parent: base
    nodeset:
      nodes:
        - name: controller
          label: linux-light         # override base job's node

- job:
    name: recordtec-integration-tests
    parent: base
    nodeset:
      nodes:
        - name: controller
          label: linux-heavy         # needs Docker, more RAM, more time
    timeout: 3600
```

---

## Path 3 — GCP Compute Engine (production)

In production, Nodepool provisions fresh GCP VMs per job. Each VM is created
from a pre-built GCP image, assigned to one job, then permanently deleted.
This eliminates all state leakage between jobs.

```
Job triggered
     ↓
Nodepool creates a new e2-medium VM from your GCP image
     ↓
Zuul executor SSHes in, runs Ansible playbooks
     ↓
Job finishes → Nodepool DELETES the VM
     ↓
No state remains
```

### nodepool.yaml for GCP

```yaml
zookeeper-servers:
  - host: zookeeper
    port: 2281

zookeeper-tls:
  cert: /etc/nodepool/certs/clientcert.pem
  key: /etc/nodepool/certs/clientkey.pem
  ca: /etc/nodepool/certs/cacert.pem

providers:
  - name: gcp-us-central1
    driver: gce
    project: your-gcp-project-id
    region: us-central1
    zone: us-central1-a
    boot-timeout: 120
    pools:
      - name: main
        max-servers: 10              # maximum concurrent VMs
        networks:
          - default
        labels:
          - name: linux-executor
            image: zuul-node-v1      # your pre-built GCP image name
            machine-type: e2-medium
            key-name: zuul-ssh-key
            username: zuul

labels:
  - name: linux-executor
    min-ready: 1                     # keep 1 VM pre-booted for low latency
```

### Building a GCP base image with Packer

Create a GCP image with all tools pre-installed using Packer:

```hcl
# zuul-node-image.pkr.hcl

source "googlecompute" "zuul-node" {
  project_id   = "your-gcp-project-id"
  zone         = "us-central1-a"
  image_name   = "zuul-node-v{{timestamp}}"
  source_image_family = "ubuntu-2204-lts"
  machine_type = "e2-medium"
  ssh_username = "packer"
}

build {
  sources = ["source.googlecompute.zuul-node"]

  provisioner "shell" {
    inline = [
      "apt-get update",
      "apt-get install -y python3 python3-pip git curl",
      "curl -fsSL https://get.docker.com | sh",
      "curl -fsSL https://deb.nodesource.com/setup_20.x | bash -",
      "apt-get install -y nodejs",
      "useradd -m -s /bin/bash zuul",
      "echo 'zuul ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers",
      "usermod -aG docker zuul"
    ]
  }
}
```

```bash
packer build zuul-node-image.pkr.hcl
```

---

## Comparison

| | Static (lab) | Static + custom image | GCP VMs (prod) |
|---|---|---|---|
| Node lifecycle | Always on, reused | Always on, reused | Fresh per job, deleted after |
| State between jobs | Leaks | Leaks | None |
| Startup time | Instant | Instant | 60–120 seconds |
| Cost | GCP VM always running | GCP VM always running | Pay per job minute |
| Tools pre-installed | Minimal | Full | Full |
| Maintenance | Rebuild image manually | Rebuild image manually | Rebuild GCP image |
| Recommended for | Early testing | Lab testing | Production |

---

## Recommended Progression

```
Stage 1 — Lab (now)
  static driver → zuul-node:lab container → minimal Ubuntu + sshd

Stage 2 — Lab improved (next step)
  static driver → zuul-node:lab container → Python + Node.js + Docker pre-installed

Stage 3 — Lab scaled
  static driver → multiple containers with different labels (light / heavy)

Stage 4 — Production
  gce driver → GCP VMs from Packer-built image → fresh per job, deleted after
```
