import { Badge } from '@pallastrade/dashboard-ui'

const STATUS_VARIANTS: Record<string, 'success' | 'destructive' | 'secondary' | 'outline'> = {
  succeeded: 'success',
  failed: 'destructive',
  queued: 'secondary',
  running: 'outline',
  cancelled: 'secondary',
  skipped: 'secondary',
}

const STATUS_LABELS: Record<string, string> = {
  succeeded: 'Succeeded',
  failed: 'Failed',
  queued: 'Queued',
  running: 'Running',
  cancelled: 'Cancelled',
  skipped: 'Skipped',
}

/**
 * Status badge for AI run statuses.
 */
export function StatusBadge({ status }: { status: string }) {
  return (
    <Badge variant={STATUS_VARIANTS[status] ?? 'secondary'}>
      {STATUS_LABELS[status] ?? status}
    </Badge>
  )
}

/**
 * Get the variant for a connection status.
 */
export function connectionStatusVariant(
  status: string | undefined,
): 'success' | 'destructive' | 'secondary' {
  if (status === 'verified') return 'success'
  if (status === 'invalid_credentials') return 'destructive'
  return 'secondary'
}
