# PallasTrade Legacy API v2

> **⚠️ DEPRECATED**: This gem provides the legacy API v2 endpoints for PallasTrade Commerce. We recommend using **API v3**.

## Overview

This gem contains the legacy Storefront API v2 and Platform API v2 endpoints that were previously part of `pallastrade_api`. These APIs are now deprecated in favor of the new API v3, which is much simpler, faster and more secure.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'pallastrade_legacy_api_v2'
```

And run the following command:

```bash
bundle exec rake pallastrade_legacy_api_v2:install
```

This will install the database migrations and run them.

## Migration Guide

### Storefront API

The new Store API v3 provides similar functionality with improved consistency:

| Legacy v2 Endpoint | New v3 Endpoint |
|-------------------|-----------------|
| `GET /api/v2/storefront/products` | `GET /api/v3/store/products` |
| `GET /api/v2/storefront/cart` | `GET /api/v3/store/orders/:id` |
| `POST /api/v2/storefront/cart/add_item` | `POST /api/v3/store/orders/:id/line_items` |
| `GET /api/v2/storefront/account` | `GET /api/v3/store/customers` |

### Key Differences

1. **Serialization**: API v3 uses Alba serializers (faster, simpler) instead of JSONAPI::Serializer
2. **Response Format**: API v3 returns simple JSON objects instead of JSONAPI format
3. **Authentication**: API v3 requires publishable key authentication for Store API and uses JWT tokens for user authentication
4. **TypeScript Types**: API v3 automatically generates TypeScript types via Typelizer
