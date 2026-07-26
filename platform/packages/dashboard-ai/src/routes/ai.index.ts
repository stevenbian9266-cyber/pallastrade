import { createLazyRoute } from '@tanstack/react-router'
import { AiOverviewPage } from '../pages/ai-overview'

export const Route = createLazyRoute('/$storeId/ai')({
  component: AiOverviewPage,
})
