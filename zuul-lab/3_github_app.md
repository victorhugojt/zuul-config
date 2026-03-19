# 🔑 Step 3: Create GitHub App for Zuul

Zuul connects to GitHub via a **GitHub App** (not a personal token).
This gives webhook delivery, repository access, and status checks.

---

## 📋 Create the GitHub App

Go to: **GitHub → Settings → Developer settings → GitHub Apps → New GitHub App**

Or directly: https://github.com/settings/apps/new

### Fill in these fields:

| Field | Value |
|-------|-------|
| **GitHub App name** | `zuul-lab-yourname` (must be unique) |
| **Homepage URL** | `http://35.239.241.176:9000` |
| **Webhook URL** | `http://35.239.241.176:9000/api/connection/github/payload` |
| **Webhook secret** | Generate one: `openssl rand -hex 20` |

Webhook secret: f0236baaa987218dece53b9de40bfd4f1c8e0199

### Permissions required:

> ⚠️ GitHub renamed some permissions in recent UI updates.
> Use this exact list as it appears in the current GitHub interface:

**Repository permissions:**
| What you see in GitHub UI | Set to |
|--------------------------|--------|
| **Checks** | Read & Write |
| **Commit statuses** | Read & Write |  ← this is the old "Statuses"
| **Contents** | Read-only |
| **Deployments** | Read & Write |
| **Issues** | Read & Write |
| **Metadata** | Read-only (auto-selected, mandatory) |
| **Pull requests** | Read & Write |

**Account permissions:** _(nothing needed here)_

**Subscribe to events:**
- [x] Check run
- [x] Check suite
- [x] Create
- [x] Delete
- [x] Deployment
- [x] Issue comment
- [x] Pull request
- [x] Pull request review
- [x] Push
- [x] Release

### Where can this GitHub App be installed?
- Select: **Only on this account** (for lab purposes)

---

## 📥 Download the Private Key

After creating the app:
1. Scroll to **Private keys** section
2. Click **Generate a private key**
3. Save the downloaded `.pem` file → you'll need it for Zuul config

---

## 📝 Note these values (you'll need them):

```bash
# After creating the app, save these:
GITHUB_APP_ID=3084515
GITHUB_APP_WEBHOOK_SECRET=f0236baaa987218dece53b9de40bfd4f1c8e0199
GITHUB_APP_KEY_FILE=zuul-integration-app.2026-03-13.private-key.pem
GITHUB_APP_NAME=zuul-integration-app
```

---

## 🔗 Install the App on your Repository

1. Go to your GitHub App page
2. Click **Install App**
3. Select your account
4. Choose: **Only select repositories** → select your test repo
5. Click **Install**
