import { z } from 'zod'

/**
 * Zod schemas for AI dashboard forms and API validation.
 */

// ── Settings ──
export const aiSettingSchema = z.object({
  active: z.boolean().default(false),
  fallback_enabled: z.boolean().default(false),
  daily_request_limit: z.number().positive().nullable().default(null),
  daily_input_token_limit: z.number().positive().nullable().default(null),
  daily_output_token_limit: z.number().positive().nullable().default(null),
  daily_cost_limit: z.number().positive().nullable().default(null),
  run_retention_days: z.number().int().min(1).max(365).default(30),
  content_logging_mode: z.enum(['none', 'metadata', 'encrypted']).default('none'),
})

export type AiSettingForm = z.infer<typeof aiSettingSchema>

// ── Provider ──
export const aiProviderSchema = z.object({
  api_key: z.string().min(1, 'API key is required').optional(),
  active: z.boolean().default(false),
})

export type AiProviderForm = z.infer<typeof aiProviderSchema>

// ── Model ──
export const aiModelSchema = z.object({
  name: z.string().min(1),
  provider_model_id: z.string().min(1),
  kind: z.enum(['text', 'multimodal', 'embedding', 'image', 'audio']).default('text'),
  active: z.boolean().default(false),
  capabilities: z.array(z.string()).default([]),
  default_parameters: z.record(z.unknown()).default({}),
})

export type AiModelForm = z.infer<typeof aiModelSchema>

// ── Capability Setting ──
export const aiCapabilitySettingSchema = z.object({
  active: z.boolean().default(false),
  primary_model_id: z.string().nullable().default(null),
  fallback_model_id: z.string().nullable().default(null),
  fallback_enabled: z.boolean().default(false),
  parameter_overrides: z.record(z.unknown()).default({}),
  daily_request_limit: z.number().positive().nullable().default(null),
  daily_token_limit: z.number().positive().nullable().default(null),
})

export type AiCapabilitySettingForm = z.infer<typeof aiCapabilitySettingSchema>
