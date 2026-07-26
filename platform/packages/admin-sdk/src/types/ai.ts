// Admin SDK types for AI module.
// These mirror the backend serializers and are used by the dashboard plugin.
// Placed here so other dashboard packages can reference AI types.

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

export interface AiProvider {
  id: string
  type: string
  active: boolean
  name: string
  key: string
  preferences: Record<string, unknown>
  last_verified_at: string | null
  verification_status: string
  credential: {
    credential_configured: boolean
    credential_hint: string
    credential_rotated_at: string | null
  }
  connection_status: {
    verified_at: string | null
    status: string
  }
  model_count: number
  active_model_count: number
  created_at: string
  updated_at: string
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
  availability: {
    available: boolean
    reason: string | null
  }
  created_at: string
  updated_at: string
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

export interface AiArtifact {
  id: string
  kind: string
  schema_version: string | null
  content_type: string | null
  checksum: string | null
  payload: Record<string, unknown> | null
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

export interface AiUsageByCapability {
  capability_key: string
  count: number
  estimated_cost: string | null
}

export interface AiUsageByProvider {
  provider_type: string
  count: number
  estimated_cost: string | null
}
