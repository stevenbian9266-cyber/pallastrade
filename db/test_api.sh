#!/bin/sh
curl -s \
  -H "Authorization: Bearer pk_tY1PEBnvHWVecZgC12kSDkEF" \
  -H "Accept: application/json" \
  "http://localhost:3000/api/v3/store/products?per_page=2" \
  | head -c 500
echo ""
echo "---"
curl -s \
  -H "Authorization: Bearer pk_tY1PEBnvHWVecZgC12kSDkEF" \
  "http://localhost:3000/api/v3/store/products" \
  | head -c 200
