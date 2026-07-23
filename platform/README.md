<p>
  <a href="https://pallastrade.cn">
    <img src="https://pallastrade.cn/wp-content/themes/pallastrade/images/logo.svg" alt="PallasTrade Commerce open source headless eCommerce platform for B2B, Multi-vendor Marketplace, cross-border eCommerce, multi-tenant eCommerce" width="250" />
  </a>
</p>

[Website](https://pallastrade.cn)
·
·
[Next.js Storefront](https://github.com/stevenbian9266-cyber/pallastrade)
·
[Documentation](https://pallastrade.cn/docs/)
·
[API](https://pallastrade.cn/docs/api-reference/)
·
[Roadmap](https://github.com/stevenbian9266-cyber/pallastrade/milestones?direction=asc&sort=due_date&state=open)
·

[![Gem Total Downloads](https://img.shields.io/gem/dt/pallastrade)](https://rubygems.org/gems/pallastrade)
[![codecov](https://codecov.io/gh/stevenbian9266-cyber/pallastrade/graph/badge.svg?token=DPFc7HbJvU)](https://codecov.io/gh/stevenbian9266-cyber/pallastrade)


Headless eCommerce platform with a complete REST API, TypeScript SDK, and a production-ready Next.js storefront. Keep full ownership of your code, data, and infrastructure.

Everything you need to launch cross-border storefronts, B2B wholesale, or a custom commerce backend.

## Getting Started

The fastest way to try PallasTrade is to follow the [local quickstart](https://pallastrade.cn/docs/developer/getting-started/quickstart).

To run PallasTrade locally instead, copy and paste the following command to your terminal to set it up in 5 minutes:

```bash
npx create-pallastrade-app@latest my-store
```

This sets up the PallasTrade Commerce backend, the Admin Dashboard, and the [Next.js storefront](https://github.com/stevenbian9266-cyber/pallastrade) in a single project. The storefront is built with Next.js 16, React 19, Tailwind CSS 4, and TypeScript.

You need to have Node.js (22+) installed and Docker running. Learn more in the [installation docs](https://pallastrade.cn/docs/developer/getting-started/quickstart).

If you like what you see, consider giving PallasTrade a GitHub star ⭐

Thank you for supporting PallasTrade open-source ❤️

### Agentic Development

Building with an AI coding agent? Install the [PallasTrade agent skills](https://github.com/stevenbian9266-cyber/pallastrade) — they teach Claude Code, Cursor, Copilot, and 60+ other tools PallasTrade's conventions and customization patterns:

```bash
npx skills add stevenbian9266-cyber/pallastrade
```

Then connect the [docs MCP server](https://pallastrade.cn/docs/developer/agentic/mcp) and let your agent build with you. Learn more in the [Agentic Development docs](https://pallastrade.cn/docs/developer/agentic/overview).

### PallasTrade CLI

[`@pallastrade/cli`](packages/cli) manages your PallasTrade project from the terminal — boot the stack, run generators and migrations, tail logs — and calls the **Admin API** directly with simple `get`/`post`/`patch`/`delete` commands. It's a fast way to inspect and script your store, and works hands-free for AI agents (zero-config credentials in local dev):

```bash
pallastrade dev                                                            # boot the project (web + worker + db)
pallastrade generate api_resource Brand name:string description:rich_text  #  Creates full API endpoints, models and database schema for a Brand resource
pallastrade api get /orders -q status_eq=complete --limit 10               # query the Admin API
pallastrade api post /products -d '{"name":"Classic Tee","prices":[{"currency":"USD","amount":"29.99"}]}'  # create resources
```

`pallastrade api endpoints` and `pallastrade api schema` explore the full API offline. See the [CLI docs](https://pallastrade.cn/docs/developer/cli/quickstart).

## Features

Everything below ships in this repository.

* **[REST API & TypeScript SDK](https://pallastrade.cn/docs/api-reference/store-api/introduction)** — production-grade REST API, publishable keys, rate limiting, and OpenAPI 3.0 spec. The [TypeScript SDK](https://pallastrade.cn/docs/developer/sdk/quickstart) adds autocomplete and type safety.
* **[PallasTrade CLI](https://pallastrade.cn/docs/developer/cli/quickstart)** — manage projects from the terminal (boot, generate, migrate, upgrade) and call the Admin API directly with `pallastrade api get/post/...` — zero-config in local dev, built for scripts and AI agents.
* **[Next.js Storefront](https://github.com/stevenbian9266-cyber/pallastrade)** — open-source storefront built with Next.js 16, React 19, Tailwind CSS 4, and TypeScript. Full shopping experience, multi-region URL routing, Stripe payments (Apple Pay, Google Pay, Klarna, Affirm), customer accounts, and SEO built in.
* **[Cross-Border Commerce](https://pallastrade.cn/docs/user/settings/markets)** — Markets bundle currency, language, payment methods, and shipping rules per country. Translations Center for bulk product localization. EU Omnibus Directive compliance with automatic 30-day price history.
* **[B2B & Wholesale](https://pallastrade.cn/docs/developer/core-concepts/products#price-lists)** — [Price Lists](https://pallastrade.cn/docs/developer/core-concepts/products#price-lists) for regional, B2B, and wholesale pricing. [Customer Groups](https://pallastrade.cn/docs/user/customers/customer-groups) for segmentation. Companies, company locations, and company contacts for buyer organizations. Catalogs for curated, per-segment product assortments. Gated storefronts via publishable keys.
* **[Sales Channels](https://pallastrade.cn/docs/developer/core-concepts/channels)** — run multiple storefronts, Points of Sale, B2B panels, mobile apps off a single PallasTrade backend, each with its products, pricing, payment methods, and shipping rules
* **[Payment Sessions](https://pallastrade.cn/docs/developer/core-concepts/payments)** — provider-agnostic payment processing. Shipped with [Stripe](https://pallastrade.cn/docs/integrations/payments/stripe), [Adyen](https://pallastrade.cn/docs/integrations/payments/adyen) and [PayPal](https://pallastrade.cn/docs/integrations/payments/paypal) plugins ready to use with Next.js storefront. Add your own with the [Payment Provider SDK](https://pallastrade.cn/docs/developer/how-to/custom-payment-method).
* **[Promotions & Gift Cards](https://pallastrade.cn/docs/user/promotions/create-a-promotion)** — advanced rules-based promotions engine and native [Gift Cards](https://pallastrade.cn/docs/developer/core-concepts/store-credits-gift-cards) support.
* **Products & Catalog** — [Metafields](https://pallastrade.cn/docs/developer/core-concepts/metafields), [CSV importer/exporter](https://pallastrade.cn/docs/user/manage-products/import-products), digital products, product tags, [bulk operations](https://pallastrade.cn/docs/user/manage-products/bulk-product-operations).
* **[MeiliSearch Integration](https://pallastrade.cn/docs/integrations/search/meilisearch)** — typo-tolerant product search and faceted filtering.
* **Admin Dashboard** — built with [Tailwind CSS](https://pallastrade.cn/docs/developer/admin/custom-css) with [role-based permissions](https://pallastrade.cn/docs/developer/customization/permissions).
* **Integrations & Extensibility** — [Event Bus](https://pallastrade.cn/docs/developer/core-concepts/events), [Webhooks 2.0](https://pallastrade.cn/docs/developer/core-concepts/webhooks), native integrations ([GA4](https://pallastrade.cn/docs/integrations/analytics/google-analytics), [GTM](https://pallastrade.cn/docs/integrations/analytics/google-tag-manager), [Klaviyo](https://pallastrade.cn/docs/integrations/marketing/klaviyo)).
* **[Agentic Development](https://pallastrade.cn/docs/developer/agentic/overview)** — [25 agent skills](https://github.com/stevenbian9266-cyber/pallastrade) (`npx skills add stevenbian9266-cyber/pallastrade`) teaching AI coding agents PallasTrade's conventions, a [docs MCP server](https://pallastrade.cn/docs/developer/agentic/mcp), [LLM-ready documentation](https://pallastrade.cn/docs/developer/agentic/llm-docs) (llms.txt, per-page Markdown, offline npm package), and a generated AGENTS.md/CLAUDE.md in every scaffolded project.

## Deployment

You can quickly deploy a PallasTrade store with the button below, or follow our [deployment guide](https://pallastrade.cn/docs/developer/deployment/overview) for detailed instructions on deploying to various platforms.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy?repo=https://github.com/stevenbian9266-cyber/pallastrade)

> **Note**
> This uses Render's free plan for quick evaluation. Free instances spin down after inactivity and may take 30-60s to wake up. For production, see [recommended sizing](https://pallastrade.cn/docs/developer/deployment/render#production-sizing).

## Screenshots

### [Next.js eCommerce Storefront](https://github.com/stevenbian9266-cyber/pallastrade)

A production-ready, open-source storefront built with Next.js 16, React 19, and TypeScript. Fork it, customize it, and deploy it.

<table>
  <tr>
    <td><img src="https://pallastrade.cn/wp-content/uploads/2026/04/PallasTrade-Commerce-Next.js-Storefront-Homepage.webp" alt="PallasTrade Commerce - Next.js Storefront - Home" width="400" /></td>
    <td><img src="https://pallastrade.cn/wp-content/uploads/2026/04/PallasTrade-Commerce-Next.js-Storefront-Product-Detail-Page-PDP.webp" alt="PallasTrade Commerce - Next.js Storefront - Product" width="400" /></td>
    <td><img src="https://pallastrade.cn/wp-content/uploads/2026/04/PallasTrade-Commerce-Next.js-Storefront-PageSpeed-Lighthouse.webp" alt="PallasTrade Commerce - Next.js Storefront - Lighthouse" width="400" /></td>
  </tr>
</table>

### [Cross-border eCommerce](https://pallastrade.cn/multi-region-ecommerce/)

Sell in multiple markets with local currencies, languages, payment methods, and shipping rules. Markets bundle per-country configuration so each customer sees a localized storefront from a single platform.

<img alt="PallasTrade Commerce - Cross-border eCommerce" src="https://pallastrade.cn/wp-content/uploads/2024/07/multi-region-country-shopping-1024x575.webp" width="600" >

### [Wholesale & B2B Pricing](https://pallastrade.cn/use-cases/wholesale-ecommerce/)

Price Lists, Customer Groups, and gated storefronts. Sell to multiple customer segments with the right assortment and pricing per segment.

<img src="https://github.com/stevenbian9266-cyber/pallastrade/assets/12614496/bac1e551-f629-47d6-a983-b385aa65b1bd" alt="PallasTrade Commerce - Wholesale eCommerce Platform" width="600" >

### [Multi-vendor Marketplace](https://pallastrade.cn/marketplace-ecommerce/)

Launch a multi-vendor marketplace with vendor accounts, product catalog curation, split payments, vendor payouts, and commission management. The Enterprise Edition adds automated vendor onboarding (Shopify, WooCommerce sync) and Stripe Connect / Adyen for Platforms integrations.

<img alt="PallasTrade Commerce - Multi-vendor Marketplace eCommerce" src="https://github.com/stevenbian9266-cyber/pallastrade/assets/12614496/c4ddd118-df4c-464e-b1fe-d43862e5cf25" width="600" >

## Support and maintenance

PallasTrade is maintained exclusively by Steven Bian and does not accept
external code contributions or pull requests.

* Use [GitHub Issues](https://github.com/stevenbian9266-cyber/pallastrade/issues)
  for public bug reports and feature requests.
* Report security vulnerabilities privately to
  [stevenbian9266@gmail.com](mailto:stevenbian9266@gmail.com).
* See the [repository maintenance policy](.github/CONTRIBUTING.md) for details.
