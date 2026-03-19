# 1. Upload from your Mac
scp -r /Users/victor.jimenez/development/sh-commands/commands/zuul-lab \
    victor.h.jimenez.t@gmail.com@35.239.241.176:~/zuul-lab

# 2. SSH into the VM
ssh victor.h.jimenez.t@gmail.com@35.239.241.176

# 3. Set correct permissions and move the PEM
cd ~/zuul-lab
chmod +x *.sh
chmod 600 zuul-integration-app.2026-03-13.private-key.pem
mv zuul-integration-app.2026-03-13.private-key.pem config/github-app.pem

# 4. Edit 4_deploy.sh with your values
nano 4_deploy.sh
# Set: GITHUB_APP_ID, GITHUB_WEBHOOK_SECRET
# Set: GITHUB_APP_PEM="config/github-app.pem"

# 5. Run the deploy
bash 4_deploy.sh