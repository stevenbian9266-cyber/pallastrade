import { beforeAll, describe, expect, it } from 'vitest'
import type { Client } from '../src'
import { createTestClient } from './helpers'

// PRD-20260827-checkout-实施-p5 P5b 合并支付收银台
// AC-006：SDK paymentCombinations.create 存在且请求路径正确
describe('paymentCombinations', () => {
  let client: Client
  beforeAll(() => {
    client = createTestClient()
  })
  const opts = { token: 'user-jwt' }

  describe('create', () => {
    it('creates a payment combination for unpaid orders', async () => {
      const result = await client.paymentCombinations.create(
        { order_ids: ['order_1', 'order_2'], payment_method_id: 'pm_1' },
        opts,
      )
      expect(result.id).toBe('pcom_1')
      expect(result.status).toBe('processing')
      expect(result.amount).toBe('99.98')
      expect(result.currency).toBe('USD')
      expect(result.payment_session?.id).toBe('ps_1')
      expect(result.payment_session?.external_data).toHaveProperty('client_secret')
    })
  })
})
