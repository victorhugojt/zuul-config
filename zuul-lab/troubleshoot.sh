#!/bin/bash
# ===========================================================================
# Zuul Lab Troubleshooting Commands
# ===========================================================================

STATIC_IP="35.239.241.176"

echo "======================================================================"
echo "🔍 ZUUL LAB DIAGNOSTICS"
echo "======================================================================"

echo ""
echo "1️⃣  Service Status:"
docker compose ps

echo ""
echo "2️⃣  Zuul Web API response:"
curl -s http://localhost:9000/api/info | jq . || echo "⚠️  Web not responding"

echo ""
echo "3️⃣  Test webhook endpoint (simulates GitHub ping):"
curl -s -X POST http://localhost:9000/api/connection/github/payload \
  -H "Content-Type: application/json" \
  -H "X-GitHub-Event: ping" \
  -d '{"zen":"test"}' || echo "⚠️  Webhook endpoint issue"

echo ""
echo "4️⃣  Firewall check from external (run from your local machine):"
echo "   nc -zv ${STATIC_IP} 9000"

echo ""
echo "5️⃣  Recent Scheduler logs:"
docker compose logs zuul-scheduler --tail=20

echo ""
echo "6️⃣  Recent Web logs:"
docker compose logs zuul-web --tail=20

echo ""
echo "7️⃣  ZooKeeper health:"
docker compose exec zookeeper zkServer.sh status

echo ""
echo "8️⃣  MySQL check:"
docker compose exec mysql mysqladmin ping -uzuul -pzuul_pass

echo ""
echo "======================================================================"
echo "Common Fixes:"
echo ""
echo "❌ Webhook not received:"
echo "   → Check GCP firewall: gcloud compute firewall-rules describe allow-zuul-webhook"
echo "   → Test connectivity: nc -zv ${STATIC_IP} 9000"
echo "   → Check GitHub App webhook delivery in App settings"
echo ""
echo "❌ Scheduler not connecting to GitHub:"
echo "   → Check app_id and pem file in config/zuul.conf"
echo "   → docker compose logs zuul-scheduler | grep -i github"
echo ""
echo "❌ Jobs not running:"
echo "   → Check config repo has .zuul.yaml"
echo "   → docker compose logs zuul-executor | tail -30"
echo ""
echo "❌ Container keeps restarting:"
echo "   → docker compose logs <service-name> --tail=50"
echo "======================================================================"
