/**
 * AI dashboard type definitions.
 */

export interface AiSetting {
  id: string
  active: boolean
  fallback_enabled: boolean
  daily_request_limit: number | null
  daily_input_token_limit: number | null
  daily_output_token_limit: number | null
  daily_cost_limit: string | null
  run_retention_days: number
  content_logging_mode: 'none' | 'metadata' | 'encrypted'
  default_model_id: string | null
  created_at: string
  updated_at: string
}

export interface AiProviderType {
  key: string
  display_name: string
  default_base_url: string | null
  secret_fields: string[]
  non_secret_settings: Record<string, unknown>
  supported_parameters: string[]
  supported_capabilities: string[]
  recommended_models: AiCatalogModel[]
}

export interface AiCatalogModel {
  provider_model_id: string
  name: string
  kind: string
  capabilities: string[]
  default_parameters: Record<string, unknown>
  description: string
  pricing: AiModelPricing
}

export interface AiModelPricing {
  input_per_1k_tokens: number
  output_per_1k_tokens: number
  cached_input_per_1k_tokens: number
  currency: string
  effective_date: string
}

export interface AiProvider {
  id: string
  type: string
  active: boolean
  name: string
  key: string
  preferences: Record<string, unknown>
  last_verified_at: string | null
  verification_status: string
  credential: AiCredentialSummary
  connection_status: AiConnectionStatus
  model_count: number
  active_model_count: number
  created_at: string
  updated_at: string
}

export interface AiCredentialSummary {
  credential_configured: boolean
  credential_hint: string
  credential_rotated_at: string | null
}

export interface AiConnectionStatus {
  verified_at: string | null
  status: string
}

export interface AiModel {
  id: string
  name: string
  provider_model_id: string
  kind: string
  active: boolean
  built_in: boolean
  catalog_version: string | null
  capabilities: string[]
  default_parameters: Record<string, unknown>
  position: number | null
  capability_count: number
  last_used_at: string | null
  created_at: string
  updated_at: string
}

export interface AiCapability {
  key: string
  display_name: string
  description: string
  version: string
  execution_mode: 'sync' | 'async'
  required_model_capabilities: string[]
  allowed_parameters: string[]
  data_classification: string
  configured: boolean
  active: boolean
  setting_id: string | null
  primary_model_id: string | null
  fallback_model_id: string | null
  fallback_enabled: boolean
}

export interface AiCapabilitySetting {
  id: string
  capability_key: string
  active: boolean
  fallback_enabled: boolean
  parameter_overrides: Record<string, unknown>
  daily_request_limit: number | null
  daily_token_limit: number | null
  orphaned: boolean
  primary_model_id: string | null
  fallback_model_id: string | null
  availability: AiAvailability
  created_at: string
  updated_at: string
}

export interface AiAvailability {
  available: boolean
  reason: string | null
}

export interface AiRun {
  id: string
  capability_key: string | null
  capability_version: string | null
  provider_type: string | null
  provider_model_id: string | null
  status: 'queued' | 'running' | 'succeeded' | 'failed' | 'cancelled' | 'skipped'
  mode: 'sync' | 'async'
  unavailable_reason: string | null
  fallback_from_model_id: string | null
  input_tokens: number
  cached_input_tokens: number
  output_tokens: number
  reasoning_tokens: number
  estimated_cost: string | null
  latency_ms: number | null
  attempts: number
  error_code: string | null
  error_message: string | null
  queued_at: string | null
  started_at: string | null
  completed_at: string | null
  created_at: string
  updated_at: string
}

export interface AiUsageSummary {
  total_runs: number
  succeeded: number
  failed: number
  skipped: number
  total_input_tokens: number
  total_output_tokens: number
  total_reasoning_tokens: number
  total_estimated_cost: string | null
  avg_latency_ms: number | null
}

export interface AiUsageBreakdown {
  capability_key: string
  count: number
  estimated_cost: string | null
}

export interface AiUsageResponse {
  summary: AiUsageSummary
  by_capability: AiUsageBreakdown[]
  by_provider: AiUsageBreakdown[]
}
