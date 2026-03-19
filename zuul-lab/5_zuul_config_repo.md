# 📁 Step 5: Create Zuul Config Repository on GitHub

Zuul needs a **config repository** in GitHub that contains pipeline definitions.

---

## Create `zuul-config` repo on GitHub

1. Go to https://github.com/new
2. Create: `your-github-username/zuul-config`
3. Initialize with a README

---

## Add `.zuul.yaml` to the config repo

Create `.zuul.yaml` in the ROOT of `zuul-config`:

```yaml
# zuul-config/.zuul.yaml

- pipeline:
    name: check
    description: Validate pull requests
    manager: independent
    trigger:
      github:
        - event: pull_request
          action:
            - opened
            - changed
            - reopened
        - event: push
          ref: ^refs/heads/main$
    start:
      github:
        check: in_progress
    success:
      github:
        check: success
    failure:
      github:
        check: failure

- pipeline:
    name: gate
    description: Merge approved pull requests
    manager: dependent
    trigger:
      github:
        - event: pull_request_review
          action: submitted
          state: approved
    success:
      github:
        check: success
        merge: true
    failure:
      github:
        check: failure

- job:
    name: base
    parent: null
    description: Base job - all jobs inherit from this
    run: playbooks/base.yaml
    post-run: playbooks/post-base.yaml
    timeout: 1800
    nodeset:
      nodes:
        - name: controller
          label: linux-executor

- job:
    name: hello-world
    parent: base
    description: Simple hello world job
    run: playbooks/hello-world.yaml
```

---

## Create the base playbooks

**Create `playbooks/base.yaml`:**
```yaml
- hosts: controller
  tasks:
    - name: Print starting message
      debug:
        msg: "Job started on {{ inventory_hostname }}"
```

**Create `playbooks/post-base.yaml`:**
```yaml
- hosts: controller
  tasks:
    - name: Print completion message
      debug:
        msg: "Job completed"
```

**Create `playbooks/hello-world.yaml`:**
```yaml
- hosts: controller
  tasks:
    - name: Hello World
      debug:
        msg: "Hello from Zuul CI!"
    
    - name: Show environment
      command: uname -a
      register: result
    
    - name: Print result
      debug:
        var: result.stdout
```

---

## Add `.zuul.yaml` to your TEST repo

In `your-github-username/your-test-repo`, create `.zuul.yaml`:

```yaml
- project:
    check:
      jobs:
        - hello-world
    gate:
      jobs:
        - hello-world
```

---

## Update `main.yaml` in your Zuul lab

Edit `config/main.yaml` and replace the placeholders:

```yaml
- tenant:
    name: my-lab
    source:
      github:
        config-projects:
          - your-github-username/zuul-config
        untrusted-projects:
          - your-github-username/your-test-repo
```

Then restart the scheduler:
```bash
docker compose restart zuul-scheduler
```
