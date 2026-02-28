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

# 1. Nginx установлен
check "Nginx binary exists" "which nginx"

# 2. Nginx запущен
check "Nginx service is running" "systemctl is-active nginx"

# 3. Nginx включён в автозапуск
check "Nginx is enabled" "systemctl is-enabled nginx"

# 4. Конфиг валидный — нужен sudo
check "Nginx config is valid" "sudo nginx -t 2>&1 | grep -q 'successful'"

# 5. Порт 80 слушает
check "Port 80 is listening" "ss -tlnp | grep ':80'"

# 6. HTTP ответ на localhost
check "HTTP response on localhost" "curl -sf http://localhost/ -o /dev/null"

# 7. Health endpoint работает
check "Health endpoint returns 200" "curl -sf http://localhost/health -o /dev/null -w '%{http_code}' | grep -q 200"

# 8. Server tokens скрыты
check "Server version hidden in headers" "! curl -sI http://localhost/ | grep -i 'Server: nginx/'"

# 9. UFW активен — нужен sudo
check "UFW is active" "sudo ufw status | grep -q 'Status: active'"

echo "========================================="
echo "  Results: $PASS passed, $FAIL failed"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
  echo "SMOKE TEST FAILED"
  exit 1
fi

echo "SMOKE TEST PASSED"
exit 0
