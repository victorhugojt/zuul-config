#!/bin/bash
# ===========================================================================
# Step 1: Open GCP firewall for Zuul webhooks
# Run this from your LOCAL machine (where gcloud is authenticated)
# ===========================================================================

PROJECT="project-2c268745-0c2f-477a-b6a"   # Replace with your project ID
STATIC_IP="35.239.241.176"      # Your reserved static IP
VM_NAME="vm-frontend"
ZONE="us-central1-a"

echo "======================================================================"
echo "🔥 Configuring GCP Firewall for Zuul Lab"
echo "======================================================================"

# --- Allow Zuul web/webhook port from GitHub IPs ---
echo "📡 Fetching GitHub webhook IP ranges..."
META=$(curl -sS https://api.github.com/meta)
GITHUB_IPV4=$(echo "$META" | jq -r '[.hooks[] | select(test(":") | not)] | join(",")' 2>/dev/null)
echo "   GitHub IPs: ${GITHUB_IPV4:0:60}..."

# Allow port 9000 from GitHub for webhooks
echo ""
echo "🔓 Creating firewall rule: allow GitHub → Zuul port 9000..."
gcloud compute firewall-rules create allow-zuul-webhook \
    --network=my-poc-vpc \
    --action=ALLOW \
    --direction=INGRESS \
    --rules=tcp:9000 \
    --target-tags=zuul-server \
    --source-ranges="${GITHUB_IPV4},0.0.0.0/0" \
    --description="Allow Zuul webhook from GitHub and local testing" \
    --project=${PROJECT} 2>/dev/null || \
gcloud compute firewall-rules update allow-zuul-webhook \
    --source-ranges="${GITHUB_IPV4},0.0.0.0/0" \
    --project=${PROJECT}

echo "✅ Firewall rule created"

# --- Tag the VM so the firewall rule applies ---
echo ""
echo "🏷️  Tagging VM with 'zuul-server'..."
gcloud compute instances add-tags ${VM_NAME} \
    --tags=zuul-server \
    --zone=${ZONE} \
    --project=${PROJECT}

echo "✅ VM tagged"
echo ""
echo "======================================================================"
echo "✅ Firewall setup complete!"
echo "   Zuul webhook will be available at: http://${STATIC_IP}:9000"
echo "   GitHub webhook URL: http://${STATIC_IP}:9000/api/connection/github/payload"
echo "======================================================================"
