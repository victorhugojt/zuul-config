#!/bin/bash
# ===========================================================================
# Step 4: Deploy Zuul Lab
# Run this ON the GCP VM inside the zuul-lab directory
# ===========================================================================

set -e

STATIC_IP="35.239.241.176"           # Your GCP static IP
GITHUB_APP_ID="3084515"              # From Step 3 - GitHub App ID
GITHUB_WEBHOOK_SECRET="f0236baaa987218dece53b9de40bfd4f1c8e0199"  # Webhook secret
GITHUB_APP_PEM="config/github-app.pem"  # Already in place

echo "======================================================================"
echo "🚀 Deploying Zuul CI/CD Lab"
echo "======================================================================"

# --- Validate inputs ---
if [ -z "$GITHUB_APP_ID" ] || [ -z "$GITHUB_WEBHOOK_SECRET" ] || [ -z "$GITHUB_APP_PEM" ]; then
    echo ""
    echo "❌ Please fill in the variables at the top of this script first"
    echo "📖 See: 3_github_app.md for instructions"
    exit 1
fi

# --- Ensure PEM file is in place ---
echo "🔑 Checking GitHub App private key..."
if [ ! -f "config/github-app.pem" ]; then
    if [ -f "$GITHUB_APP_PEM" ]; then
        cp "$GITHUB_APP_PEM" config/github-app.pem
        echo "✅ Key copied to config/github-app.pem"
    else
        echo "❌ PEM file not found at: $GITHUB_APP_PEM"
        exit 1
    fi
else
    echo "✅ Key already in place at config/github-app.pem"
fi
chmod 600 config/github-app.pem

# --- Patch zuul.conf with actual values ---
echo ""
echo "⚙️  Configuring zuul.conf..."
sed -i "s|YOUR_STATIC_IP|${STATIC_IP}|g"          config/zuul.conf
sed -i "s|YOUR_GITHUB_APP_ID|${GITHUB_APP_ID}|g"   config/zuul.conf
sed -i "s|YOUR_WEBHOOK_SECRET|${GITHUB_WEBHOOK_SECRET}|g" config/zuul.conf
echo "✅ Configuration updated"

# --- Generate Zuul SSH key ---
echo ""
echo "🔐 Generating SSH key for Zuul executor..."
mkdir -p keys
ssh-keygen -t rsa -b 4096 -f keys/zuul_id_rsa -N "" -q
echo "✅ SSH key generated"

# --- Deploy ---
echo ""
echo "🐳 Starting Docker Compose stack..."
docker compose pull
docker compose up -d

# --- Wait for services ---
echo ""
echo "⏳ Waiting for services to start (30s)..."
sleep 30

# --- Health check ---
echo ""
echo "🩺 Checking service health..."
docker compose ps

# --- Test webhook endpoint ---
echo ""
echo "🔗 Testing Zuul web endpoint..."
if curl -sf http://localhost:9000/api/info > /dev/null; then
    echo "✅ Zuul web is responding!"
else
    echo "⚠️  Zuul web not ready yet - check logs: docker compose logs -f zuul-web"
fi

echo ""
echo "======================================================================"
echo "✅ Zuul Lab Deployed!"
echo ""
echo "📊 Dashboard:     http://${STATIC_IP}:9000"
echo "🔗 Webhook URL:   http://${STATIC_IP}:9000/api/connection/github/payload"
echo ""
echo "🔍 Useful commands:"
echo "   docker compose logs -f zuul-scheduler   # Watch scheduler"
echo "   docker compose logs -f zuul-web         # Watch web/webhooks"
echo "   docker compose logs -f                  # Watch all"
echo "   docker compose ps                       # Check status"
echo "   docker compose down                     # Stop all"
echo "======================================================================"
