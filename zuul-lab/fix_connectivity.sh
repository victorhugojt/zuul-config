#!/bin/bash
# ===========================================================================
# Fix Zuul connectivity - run ON the GCP VM
# ===========================================================================

echo "======================================================================"
echo "🔧 ZUUL CONNECTIVITY FIX"
echo "======================================================================"

# 1. Check containers
echo ""
echo "1️⃣  Container status:"
docker compose ps

# 2. Check port binding
echo ""
echo "2️⃣  Port 9000 binding:"
sudo ss -tlnp | grep 9000 || echo "⚠️  Nothing listening on port 9000!"

# 3. Check UFW
echo ""
echo "3️⃣  UFW firewall status:"
sudo ufw status

# 4. Open port if UFW is active
if sudo ufw status | grep -q "Status: active"; then
    echo ""
    echo "   UFW is active - opening port 9000..."
    sudo ufw allow 9000/tcp
    sudo ufw reload
    echo "   ✅ Port 9000 opened in UFW"
fi

# 5. Test locally
echo ""
echo "4️⃣  Local test:"
if curl -sf http://localhost:9000/api/info > /dev/null 2>&1; then
    echo "✅ Zuul is responding locally on port 9000"
    echo "   → Problem is the GCP firewall - run fix_gcp_firewall.sh on your LOCAL machine"
else
    echo "⚠️  Zuul NOT responding locally"
    echo ""
    echo "   Checking zuul-web logs:"
    docker compose logs zuul-web --tail=20
    echo ""
    echo "   Trying to restart zuul-web..."
    docker compose restart zuul-web
    sleep 10
    if curl -sf http://localhost:9000/api/info > /dev/null 2>&1; then
        echo "✅ Zuul is now responding after restart!"
    else
        echo "❌ Still not responding - check: docker compose logs -f zuul-web"
    fi
fi

echo ""
echo "======================================================================"
