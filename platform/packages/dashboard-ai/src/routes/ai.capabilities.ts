import { createLazyRoute } from '@tanstack/react-router'
import { AiCapabilitiesPage } from '../pages/ai-capabilities'

export const Route = createLazyRoute('/$storeId/ai/capabilities')({
  component: AiCapabilitiesPage,
})
