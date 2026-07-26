import { createLazyRoute } from '@tanstack/react-router'
import { AiModelsPage } from '../pages/ai-models'

export const Route = createLazyRoute('/$storeId/ai/models')({
  component: AiModelsPage,
})
