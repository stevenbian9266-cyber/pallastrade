import {
  adminClient,
  ExportButton,
  ResourceTable,
  resourceSearchSchema,
} from '@pallastrade/dashboard-core'
import { Button } from '@pallastrade/dashboard-ui'
import { createFileRoute, Link } from '@tanstack/react-router'
import { PlusIcon } from 'lucide-react'
import '../../../../tables/orders'

export const Route = createFileRoute('/_authenticated/$storeId/orders/')({
  validateSearch: resourceSearchSchema,
  component: OrdersPage,
})

function OrdersPage() {
  const searchParams = Route.useSearch()
  const { storeId } = Route.useParams()

  return (
    <ResourceTable
      tableKey="orders"
      queryKey="orders"
      queryFn={(params) => adminClient.orders.list(params)}
      searchParams={searchParams}
      defaultParams={{ complete: 1, expand: ['channel'] }}
      actions={(ctx) => (
        <>
          <ExportButton type="PallasTrade::Exports::Orders" {...ctx} />
          <Button size="sm" className="h-[2.125rem]" asChild>
            <Link to="/$storeId/orders/new" params={{ storeId }}>
              <PlusIcon className="size-4" />
              New Order
            </Link>
          </Button>
        </>
      )}
    />
  )
}
