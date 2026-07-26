import { createAdminClient } from '@pallastrade/admin-sdk'

/**
 * AI-specific API client wrapping the admin SDK.
 * All requests are store-scoped via the dashboard context.
 */
export const aiClient = {
  // ── Settings ──
  getSettings: () =>
    createAdminClient().get('/api/v3/admin/ai/settings'),

  updateSettings: (data: Record<string, unknown>) =>
    createAdminClient().patch('/api/v3/admin/ai/settings', data),

  // ── Provider Types ──
  getProviderTypes: () =>
    createAdminClient().get('/api/v3/admin/ai/provider_types'),

  // ── Providers ──
  getProviders: () =>
    createAdminClient().get('/api/v3/admin/ai/providers'),

  getProvider: (id: string) =>
    createAdminClient().get(`/api/v3/admin/ai/providers/${id}`),

  createProvider: (data: Record<string, unknown>) =>
    createAdminClient().post('/api/v3/admin/ai/providers', data),

  updateProvider: (id: string, data: Record<string, unknown>) =>
    createAdminClient().patch(`/api/v3/admin/ai/providers/${id}`, data),

  deleteProvider: (id: string) =>
    createAdminClient().delete(`/api/v3/admin/ai/providers/${id}`),

  testProviderConnection: (id: string) =>
    createAdminClient().post(`/api/v3/admin/ai/providers/${id}/connection_tests`),

  clearProviderCredential: (id: string) =>
    createAdminClient().delete(`/api/v3/admin/ai/providers/${id}/credential`),

  // ── Models ──
  getModels: (providerId?: string) => {
    const params = providerId ? `?provider_id=${providerId}` : ''
    return createAdminClient().get(`/api/v3/admin/ai/models${params}`)
  },

  getModel: (id: string) =>
    createAdminClient().get(`/api/v3/admin/ai/models/${id}`),

  createModel: (data: Record<string, unknown>) =>
    createAdminClient().post('/api/v3/admin/ai/models', data),

  updateModel: (id: string, data: Record<string, unknown>) =>
    createAdminClient().patch(`/api/v3/admin/ai/models/${id}`, data),

  deleteModel: (id: string) =>
    createAdminClient().delete(`/api/v3/admin/ai/models/${id}`),

  // ── Capabilities ──
  getCapabilities: () =>
    createAdminClient().get('/api/v3/admin/ai/capabilities'),

  getCapabilitySettings: () =>
    createAdminClient().get('/api/v3/admin/ai/capability_settings'),

  updateCapabilitySetting: (id: string, data: Record<string, unknown>) =>
    createAdminClient().patch(`/api/v3/admin/ai/capability_settings/${id}`, data),

  // ── Runs ──
  getRuns: (params?: Record<string, string>) =>
    createAdminClient().get('/api/v3/admin/ai/runs', { params }),

  getRun: (id: string) =>
    createAdminClient().get(`/api/v3/admin/ai/runs/${id}`),

  // ── Usage ──
  getUsage: (params?: Record<string, string>) =>
    createAdminClient().get('/api/v3/admin/ai/usage', { params }),
}
