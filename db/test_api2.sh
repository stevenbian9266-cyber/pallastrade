#!/bin/sh
# Test with correct publishable key
TOKEN="pk_XS8iu4pPHbx5QDYDxhJse7nf"
echo "=== Testing with key: $TOKEN ==="
echo ""
echo "--- Products ---"
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v3/store/products?per_page=2" | head -c 300
echo ""
echo ""
echo "--- Categories ---"
curl -s -H "Authorization: Bearer $TOKEN" \
  "http://localhost:3000/api/v3/store/categories?depth_eq=0" | head -c 300
echo ""
