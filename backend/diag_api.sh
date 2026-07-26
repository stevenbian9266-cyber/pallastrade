#!/bin/bash
curl -s http://localhost:3000/api/v3/admin/ai/settings > /tmp/ai_err.html 2>&1
echo "SIZE=$(wc -c < /tmp/ai_err.html)"
echo "---ERROR---"
grep -oP 'class="message">[^<]+' /tmp/ai_err.html
echo "---TRACE---"
grep 'pallastrade_ai' /tmp/ai_err.html | head -3
