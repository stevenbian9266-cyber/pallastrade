#!/bin/sh
TOKEN="pk_9edDTtUyY6SxuugSVNDCbcTE"
echo "=== Testing with all headers ==="
echo "Products:"
curl -s \
  -H "X-PallasTrade-Api-Key: $TOKEN" \
  -H "X-PallasTrade-Currency: USD" \
  -H "X-PallasTrade-Locale: en" \
  -H "X-PallasTrade-Country: US" \
  "http://localhost:3000/api/v3/store/products?per_page=2" | head -c 500
echo ""
echo ""
echo "Categories:"
curl -s \
  -H "X-PallasTrade-Api-Key: $TOKEN" \
  -H "X-PallasTrade-Currency: USD" \
  -H "X-PallasTrade-Locale: en" \
  -H "X-PallasTrade-Country: US" \
  "http://localhost:3000/api/v3/store/categories?depth_eq=0" | head -c 500
echo ""
