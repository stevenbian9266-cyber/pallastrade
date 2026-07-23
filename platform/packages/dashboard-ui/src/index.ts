// @pallastrade/dashboard-ui — PallasTrade Dashboard design system.
//
// Shadcn primitives + headless composed components + design tokens.
// Consumers import flat from this barrel:
//
//     import { Button, Card, PageHeader } from '@pallastrade/dashboard-ui'
//
// Or import a specific file (for forking, lazy-loading, or to skip the barrel):
//
//     import { Button } from '@pallastrade/dashboard-ui/ui/button'
//
// CSS lives at `@pallastrade/dashboard-ui/styles.css` — import once from your Vite app.

export * from './hooks/use-copy-to-clipboard'
export { useIsMobile } from './hooks/use-mobile'
export * from './hooks/use-scrolled'
// ---------------------------------------------------------------------------
// Helpers + hooks
// ---------------------------------------------------------------------------
export { cn } from './lib/utils'
export { requiredMessage } from './lib/validation-messages'
// ---------------------------------------------------------------------------
// PallasTrade composed components — headless, accept data via props
// ---------------------------------------------------------------------------
export * from './pallastrade/address-block'
export * from './pallastrade/back-button'
export * from './pallastrade/bulk-dialog'
export * from './pallastrade/bulk-price-table'
export * from './pallastrade/calculator-summary'
export * from './pallastrade/color-picker'
export * from './pallastrade/confirm-dialog'
export * from './pallastrade/copy-to-clipboard-button'
export * from './pallastrade/country-flag'
export * from './pallastrade/data-grid'
export * from './pallastrade/drag-handle'
export * from './pallastrade/form-actions'

// JsonPreviewDrawer and JsonValueView are intentionally NOT re-exported from
// this barrel: they pull in `@uiw/react-json-view` (~30KB gzip), and
// code-splitting only works when consumers can deep-import via
// `@pallastrade/dashboard-ui/pallastrade/json-preview-drawer` and
// `@pallastrade/dashboard-ui/pallastrade/json-value-view`. Types are available the same
// way — `import { type JsonPreviewDrawerProps } from '@pallastrade/dashboard-ui/pallastrade/json-preview-drawer'`.

export * from './pallastrade/language-menu-items'
export * from './pallastrade/metadata/metadata-card'
export * from './pallastrade/relative-time'
export * from './pallastrade/resource-combobox'
export * from './pallastrade/resource-layout'
export * from './pallastrade/resource-multi-autocomplete'
export * from './pallastrade/resource-name-cell'
export * from './pallastrade/route-error-boundary'
export * from './pallastrade/row-actions'
export * from './pallastrade/row-click-bridge'
export * from './pallastrade/secret-input'
export * from './pallastrade/storefront-visible-switch'
export * from './pallastrade/tag-list'
export * from './pallastrade/theme-provider'
export * from './pallastrade/theme-toggle'
// ---------------------------------------------------------------------------
// UI primitives (shadcn) — see ./ui/*
// ---------------------------------------------------------------------------
export * from './ui/attachment'
export * from './ui/avatar'
export * from './ui/badge'
export * from './ui/breadcrumb'
export * from './ui/button'
export * from './ui/calendar'
export * from './ui/card'
export * from './ui/chart'
export * from './ui/checkbox'
export * from './ui/collapsible'
export * from './ui/combobox'
export * from './ui/command'
export * from './ui/data-table'
export * from './ui/date-picker'
export * from './ui/date-range-picker'
export * from './ui/dialog'
export * from './ui/dropdown-menu'
export * from './ui/empty'
export * from './ui/field'
export * from './ui/input'
export * from './ui/input-group'
export * from './ui/label'
export * from './ui/pagination'
export * from './ui/popover'
export * from './ui/progress'
export * from './ui/radio-group'
export * from './ui/rich-text-editor'
export * from './ui/select'
export * from './ui/separator'
export * from './ui/sheet'
export * from './ui/sidebar'
export * from './ui/skeleton'
export * from './ui/slot'
export * from './ui/sonner'
export * from './ui/switch'
export * from './ui/textarea'
export * from './ui/tooltip'
