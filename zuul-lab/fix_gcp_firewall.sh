#!/bin/bash
# ===========================================================================
# Fix GCP Firewall for Zuul - run on your LOCAL machine
# ===========================================================================

PROJECT="project-2c268745-0c2f-477a-b6a"
VM_NAME="vm-frontend"
ZONE="us-central1-a"
STATIC_IP="35.239.241.176"

# Auto-detect your current public IP
MY_PUBLIC_IP=$(curl -s https://checkip.amazonaws.com)
echo "🌐 Your current public IP: ${MY_PUBLIC_IP}"

echo "======================================================================"
echo "🔧 FIXING GCP FIREWALL FOR ZUUL"
echo "======================================================================"

# 1. Show current firewall rules for port 9000
echo ""
echo "1️⃣  Current firewall rules (port 9000):"
gcloud compute firewall-rules list \
    --project=${PROJECT} \
    --filter="allowed.ports:9000" \
    --format="table(name, direction, allowed, sourceRanges, targetTags)"

# 2. Check VM tags
echo ""
echo "2️⃣  Current VM tags:"
gcloud compute instances describe ${VM_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT} \
    --format="get(tags.items)"

# 3. Delete old rule if exists and recreate
echo ""
echo "3️⃣  Recreating firewall rules..."
gcloud compute firewall-rules delete allow-zuul-webhook \
    --project=${PROJECT} --quiet 2>/dev/null || true
gcloud compute firewall-rules delete allow-zuul-port-9000 \
    --project=${PROJECT} --quiet 2>/dev/null || true

# Fetch GitHub webhook IPs (they also need to reach port 9000)
echo "   Fetching GitHub webhook IPs..."
GITHUB_IPV4=$(curl -s https://api.github.com/meta | \
    jq -r '[.hooks[] | select(test(":") | not)] | join(",")' 2>/dev/null)

# Combine your IP + GitHub IPs
ALL_SOURCES="${MY_PUBLIC_IP}/32,${GITHUB_IPV4}"
echo "   Allowed sources:"
echo "     • You:    ${MY_PUBLIC_IP}/32"
echo "     • GitHub: ${GITHUB_IPV4:0:60}..."

gcloud compute firewall-rules create allow-zuul-port-9000 \
    --network=my-poc-vpc \
    --action=ALLOW \
    --direction=INGRESS \
    --rules=tcp:9000 \
    --target-tags=zuul-server \
    --source-ranges="${ALL_SOURCES}" \
    --description="Allow Zuul: my IP + GitHub webhooks on port 9000" \
    --project=${PROJECT}

echo "✅ Firewall rule created"
echo "   ⚠️  If your IP changes (dynamic IP), re-run this script to update it"

# 4. Ensure VM has the tag
echo ""
echo "4️⃣  Adding 'zuul-server' tag to VM..."
gcloud compute instances add-tags ${VM_NAME} \
    --tags=zuul-server \
    --zone=${ZONE} \
    --project=${PROJECT}

echo "✅ Tag added"

# 5. Verify
echo ""
echo "5️⃣  Verification:"
echo "   Firewall rules:"
gcloud compute firewall-rules list \
    --project=${PROJECT} \
    --filter="name=allow-zuul-port-9000" \
    --format="table(name, allowed, sourceRanges, targetTags)"

echo ""
echo "   VM tags:"
gcloud compute instances describe ${VM_NAME} \
    --zone=${ZONE} \
    --project=${PROJECT} \
    --format="get(tags.items)"

# 6. Test from local
echo ""
echo "6️⃣  Testing connection from local machine..."
sleep 3
if curl -sf --connect-timeout 5 http://${STATIC_IP}:9000/api/info > /dev/null 2>&1; then
    echo "✅ SUCCESS! Zuul is accessible at http://${STATIC_IP}:9000"
else
    echo "⚠️  Still not accessible - check if Zuul is running on the VM:"
    echo "   ssh your-user@${STATIC_IP}"
    echo "   cd ~/zuul-lab && docker compose ps"
fi

echo ""
echo "======================================================================"
