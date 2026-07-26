import { createLazyRoute } from '@tanstack/react-router'
import { AiRunsPage } from '../pages/ai-runs'

export const Route = createLazyRoute('/$storeId/ai/runs')({
  component: AiRunsPage,
})
