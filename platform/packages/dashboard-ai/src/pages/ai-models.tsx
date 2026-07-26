import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { Card, CardContent, CardHeader, CardTitle, Button, Badge } from '@pallastrade/dashboard-ui'
import { PageHeader } from '@pallastrade/dashboard-core'
import { ResourceLayout } from '@pallastrade/dashboard-ui'
import { aiClient } from '../client'
import type { AiModel } from '../types'

/**
 * AI Models page — view, enable/disable, create, and delete model configurations.
 */
export function AiModelsPage() {
  const { t } = useTranslation()
  const queryClient = useQueryClient()

  const { data: models, isLoading } = useQuery({
    queryKey: ['ai', 'models'],
    queryFn: async () => {
      const res = await aiClient.getModels()
      return res.data as AiModel[]
    },
  })

  const toggleMutation = useMutation({
    mutationFn: ({ id, active }: { id: string; active: boolean }) =>
      aiClient.updateModel(id, { model: { active } }),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'models'] }),
  })

  const deleteMutation = useMutation({
    mutationFn: (id: string) => aiClient.deleteModel(id),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: ['ai', 'models'] }),
  })

  if (isLoading) {
    return <div className="p-6 text-muted-foreground">Loading…</div>
  }

  return (
    <ResourceLayout
      header={<PageHeader title={t('admin.ai.model.title')} />}
      main={
        <div className="space-y-3">
          {(models ?? []).map((model: AiModel) => (
            <Card key={model.id}>
              <CardHeader className="flex flex-row items-center justify-between pb-2">
                <div>
                  <CardTitle className="text-base">{model.name}</CardTitle>
                  <p className="text-xs text-muted-foreground font-mono">{model.provider_model_id}</p>
                </div>
                <div className="flex items-center gap-3">
                  <Badge variant={model.built_in ? 'outline' : 'secondary'}>
                    {model.built_in ? t('admin.ai.model.catalog') : t('admin.ai.model.custom')}
                  </Badge>
                  <Badge variant={model.active ? 'success' : 'secondary'}>
                    {model.active ? 'Active' : 'Inactive'}
                  </Badge>
                  <label className="flex items-center gap-2">
                    <input
                      type="checkbox"
                      checked={model.active}
                      onChange={(e) =>
                        toggleMutation.mutate({ id: model.id, active: e.target.checked })
                      }
                      className="toggle"
                    />
                  </label>
                </div>
              </CardHeader>
              <CardContent>
                <div className="flex items-center justify-between text-sm">
                  <div className="flex gap-4">
                    <span>
                      Kind: <code>{model.kind}</code>
                    </span>
                    <span>
                      Used by: {model.capability_count ?? 0} capabilities
                    </span>
                    {model.last_used_at && (
                      <span className="text-muted-foreground">
                        Last used: {new Date(model.last_used_at).toLocaleDateString()}
                      </span>
                    )}
                  </div>
                  {!model.built_in && (
                    <Button
                      variant="destructive"
                      size="sm"
                      onClick={() => deleteMutation.mutate(model.id)}
                    >
                      Delete
                    </Button>
                  )}
                </div>
              </CardContent>
            </Card>
          ))}

          {(!models || models.length === 0) && (
            <Card>
              <CardContent className="py-8 text-center text-muted-foreground">
                No models configured. Use the Provider catalog to add models.
              </CardContent>
            </Card>
          )}
        </div>
      }
    />
  )
}
