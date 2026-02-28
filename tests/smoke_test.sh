#!/bin/bash
# =============================================================
# Smoke test для Nginx AMI
# Запускается внутри VM сразу после установки
# =============================================================

set -uo pipefail

PASS=0
FAIL=0

check() {
  local desc="$1"
  local cmd="$2"
  if eval "$cmd" > /dev/null 2>&1; then
    echo "✅ PASS: $desc"
    ((PASS++))
  else
    echo "❌ FAIL: $desc"
    ((FAIL++))
  fi
}

echo "========================================="
echo "  Nginx AMI Smoke Test"
echo "========================================="

# ── Nginx ─────────────────────────────────────────────────────
check "Nginx binary exists"              "which nginx"
check "Nginx service is running"         "systemctl is-active nginx"
check "Nginx is enabled"                 "systemctl is-enabled nginx"
check "Nginx config is valid"            "sudo nginx -t 2>&1 | grep -q 'successful'"
check "Port 80 is listening"             "ss -tlnp | grep ':80'"
check "HTTP response on localhost"       "curl -sf http://localhost/ -o /dev/null"
check "Health endpoint returns 200"      "curl -sf http://localhost/health -o /dev/null -w '%{http_code}' | grep -q 200"
check "Server version hidden in headers" "! curl -sI http://localhost/ | grep -i 'Server: nginx/'"

# ── Security headers ──────────────────────────────────────────
check "Header X-Frame-Options"           "curl -sI http://localhost/ | grep -q 'X-Frame-Options'"
check "Header X-Content-Type-Options"    "curl -sI http://localhost/ | grep -q 'X-Content-Type-Options'"
check "Header Referrer-Policy"           "curl -sI http://localhost/ | grep -q 'Referrer-Policy'"

# ── UFW ───────────────────────────────────────────────────────
check "UFW is active"                    "sudo ufw status | grep -q 'Status: active'"
check "UFW allows port 80"               "sudo ufw status | grep -q '80'"
check "UFW allows port 443"              "sudo ufw status | grep -q '443'"

# ── OS Hardening ──────────────────────────────────────────────
check "auditd is running"                "systemctl is-active auditd"
check "auditd is enabled"                "systemctl is-enabled auditd"
check "fail2ban is running"              "systemctl is-active fail2ban"
check "fail2ban is enabled"              "systemctl is-enabled fail2ban"

# ── SSH hardening ─────────────────────────────────────────────
check "SSH PermitRootLogin disabled"     "grep -q 'PermitRootLogin no' /etc/ssh/sshd_config"
check "SSH PasswordAuth disabled"        "grep -q 'PasswordAuthentication no' /etc/ssh/sshd_config"
check "SSH X11Forwarding disabled"       "grep -q 'X11Forwarding no' /etc/ssh/sshd_config"

# ── Sysctl ────────────────────────────────────────────────────
check "SYN cookies enabled"              "sysctl net.ipv4.tcp_syncookies | grep -q '= 1'"
check "ASLR enabled"                     "sysctl kernel.randomize_va_space | grep -q '= 2'"
check "IP forwarding disabled"           "sysctl net.ipv4.ip_forward | grep -q '= 0'"
check "Reverse path filtering enabled"   "sysctl net.ipv4.conf.all.rp_filter | grep -q '= 1'"

# ── Cloud-init ────────────────────────────────────────────────
check "cloud-init installed"             "which cloud-init"
# machine-id очищается в cleanup.sh после smoke теста — проверять здесь нет смысла

echo "========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
  echo "SMOKE TEST FAILED"
  exit 1
fi

echo "SMOKE TEST PASSED"
exit 0
