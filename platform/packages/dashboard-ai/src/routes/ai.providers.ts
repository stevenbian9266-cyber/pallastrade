import { createLazyRoute } from '@tanstack/react-router'
import { AiProvidersPage } from '../pages/ai-providers'

export const Route = createLazyRoute('/$storeId/ai/providers')({
  component: AiProvidersPage,
})
