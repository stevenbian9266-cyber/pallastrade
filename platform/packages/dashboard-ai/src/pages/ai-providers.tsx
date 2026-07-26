import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle, Button, Input, Badge } from '@pallastrade/dashboard-ui'
import { PageHeader } from '@pallastrade/dashboard-core'
import { ResourceLayout } from '@pallastrade/dashboard-ui'
import { aiClient } from '../client'
import type { AiProvider, AiProviderType } from '../types'

/**
 * AI Providers page — manage DeepSeek and OpenAI provider configurations,
 * API keys, connection tests, and provider switches.
 */
export function AiProvidersPage() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const [testingId, setTestingId] = useState<string | null>(null)

  const { data: providers, isLoading } = useQuery({
    queryKey: ['ai', 'providers'],
    queryFn: async () => {
      const res = await aiClient.getProviders()
      return res.data as AiProvider[]
    },
  })

  // Safety net: if no provider instances exist yet (pre-lazy-provisioning),
  // show preset provider type cards so the admin can set them up.
  const { data: providerTypes } = useQuery({
    queryKey: ['ai', 'providerTypes'],
    queryFn: async () => {
      const res = await aiClient.getProviderTypes()
      return res.data as AiProviderType[]
    },
    enabled: (providers?.length ?? 0) === 0,
  })

  const createProvider = useMutation({
    mutationFn: (providerType: string) =>
      aiClient.createProvider({ provider_type: providerType }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'providers'] }),
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) =>
      aiClient.updateProvider(id, { active }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'providers'] }),
  })

  const testConnection = useMutation({
    mutationFn: (id: string) => aiClient.testProviderConnection(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'providers'] }),
  })

  const clearCredential = useMutation({
    mutationFn: (id: string) => aiClient.clearProviderCredential(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'providers'] }),
  })

  if (isLoading) {
    return <div className="p-6 text-muted-foreground">Loading…</div>
  }

  const displayCards = (providers?.length ?? 0) > 0
    ? providers!
    : (providerTypes ?? []).map((pt) => ({
        id: `preset-${pt.key}`,
        key: pt.key,
        name: pt.display_name,
        active: false,
        credential: { credential_configured: false, credential_hint: '—', credential_rotated_at: null },
        connection_status: { status: 'unconfigured', verified_at: null },
        model_count: 0,
        active_model_count: 0,
        _isPreset: true as const,
      }))

  return (
    <ResourceLayout
      header={<PageHeader title={t('admin.ai.menu.providers')} />}
      main={
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          {displayCards.map((provider) => (
            <Card key={provider.id}>
              <CardHeader className="flex flex-row items-center justify-between">
                <CardTitle>
                  {provider.key === 'deepseek'
                    ? t('admin.ai.provider.deepseek')
                    : t('admin.ai.provider.openai')}
                </CardTitle>
                {'_isPreset' in provider && provider._isPreset ? (
                  <Button
                    size="sm"
                    onClick={() => createProvider.mutate(provider.key)}
                    disabled={createProvider.isPending}
                  >
                    {t('admin.ai.provider.setup')}
                  </Button>
                ) : (
                  <label className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={(provider as AiProvider).active}
                      onChange={(e) =>
                        toggleMutation.mutate({ id: provider.id, active: e.target.checked })
                      }
                      className="toggle"
                    />
                  </label>
                )}
              </CardHeader>
              <CardContent className="space-y-4">
                {/* Credential Status */}
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">
                    {provider.credential?.credential_configured
                      ? t('admin.ai.provider.key_configured')
                      : t('admin.ai.provider.key_not_configured')}
                  </span>
                  <Badge variant={provider.credential?.credential_configured ? 'success' : 'secondary'}>
                    {provider.credential?.credential_hint || '—'}
                  </Badge>
                </div>

                {/* Connection Status */}
                <div className="flex items-center justify-between">
                  <span className="text-sm text-muted-foreground">
                    {t('admin.ai.provider.connection_status')}
                  </span>
                  <Badge
                    variant={
                      provider.connection_status?.status === 'verified'
                        ? 'success'
                        : 'secondary'
                    }
                  >
                    {provider.connection_status?.status ?? t('admin.ai.provider.unverified')}
                  </Badge>
                </div>

                {/* Model Count */}
                <div className="text-sm text-muted-foreground">
                  {provider.active_model_count}/{provider.model_count} models active
                </div>

                {/* Actions — only for provisioned providers */}
                {!('_isPreset' in provider) && (
                  <div className="flex gap-2">
                    <Button
                      variant="outline"
                      size="sm"
                      disabled={testingId === provider.id || !provider.credential?.credential_configured}
                      onClick={() => {
                        setTestingId(provider.id)
                        testConnection.mutate(provider.id, {
                          onSettled: () => setTestingId(null),
                        })
                      }}
                    >
                      {testingId === provider.id ? 'Testing…' : t('admin.ai.provider.test_connection')}
                    </Button>
                    <Button
                      variant="outline"
                      size="sm"
                      onClick={() => clearCredential.mutate(provider.id)}
                      disabled={!provider.credential?.credential_configured}
                    >
                      {t('admin.ai.provider.clear_key')}
                    </Button>
                  </div>
                )}
              </CardContent>
            </Card>
          ))}
        </div>
      }
    />
  )
}
