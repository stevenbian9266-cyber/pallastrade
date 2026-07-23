import { HttpResponse, http } from 'msw'
import { describe, expect, it } from 'vitest'
import { PallasTradeError } from '../src'
import { createTestClient, TEST_BASE_URL } from './helpers'
import { server } from './mocks/server'

const API_PREFIX = `${TEST_BASE_URL}/api/v3/store`

describe('error handling', () => {
  it('throws PallasTradeError with correct properties on 4xx', async () => {
    server.use(
      http.get(`${API_PREFIX}/products/:id`, () =>
        HttpResponse.json(
          {
            error: {
              code: 'not_found',
              message: 'Product not found',
            },
          },
          { status: 404 },
        ),
      ),
    )

    const client = createTestClient()
    try {
      await client.products.get('nonexistent')
      expect.unreachable('Should have thrown')
    } catch (error) {
      expect(error).toBeInstanceOf(PallasTradeError)
      const pallastradeError = error as PallasTradeError
      expect(pallastradeError.code).toBe('not_found')
      expect(pallastradeError.status).toBe(404)
      expect(pallastradeError.message).toBe('Product not found')
      expect(pallastradeError.name).toBe('PallasTradeError')
    }
  })

  it('throws PallasTradeError with details on 422', async () => {
    server.use(
      http.post(`${API_PREFIX}/customers/me/addresses`, () =>
        HttpResponse.json(
          {
            error: {
              code: 'unprocessable_entity',
              message: 'Validation failed',
              details: {
                address1: ["can't be blank"],
                city: ["can't be blank"],
              },
            },
          },
          { status: 422 },
        ),
      ),
    )

    const client = createTestClient()
    try {
      await client.customer.addresses.create(
        {
          first_name: 'A',
          last_name: 'B',
          address1: '',
          city: '',
          postal_code: '00000',
          country_iso: 'US',
        },
        { token: 'jwt' },
      )
      expect.unreachable('Should have thrown')
    } catch (error) {
      const pallastradeError = error as PallasTradeError
      expect(pallastradeError.status).toBe(422)
      expect(pallastradeError.details).toHaveProperty('address1')
      expect(pallastradeError.details).toHaveProperty('city')
    }
  })

  it('throws PallasTradeError on 500 server error', async () => {
    server.use(
      http.get(`${API_PREFIX}/countries`, () =>
        HttpResponse.json(
          {
            error: {
              code: 'internal_server_error',
              message: 'Something went wrong',
            },
          },
          { status: 500 },
        ),
      ),
    )

    const client = createTestClient()
    try {
      await client.countries.list()
      expect.unreachable('Should have thrown')
    } catch (error) {
      const pallastradeError = error as PallasTradeError
      expect(pallastradeError.status).toBe(500)
      expect(pallastradeError.code).toBe('internal_server_error')
    }
  })

  it('throws PallasTradeError on 401 unauthorized', async () => {
    server.use(
      http.get(`${API_PREFIX}/customers/me`, () =>
        HttpResponse.json(
          {
            error: {
              code: 'unauthorized',
              message: 'You must be logged in',
            },
          },
          { status: 401 },
        ),
      ),
    )

    const client = createTestClient()
    try {
      await client.customer.get()
      expect.unreachable('Should have thrown')
    } catch (error) {
      const pallastradeError = error as PallasTradeError
      expect(pallastradeError.status).toBe(401)
      expect(pallastradeError.code).toBe('unauthorized')
    }
  })

  it('handles 204 No Content responses', async () => {
    const client = createTestClient()
    const result = await client.carts.delete('cart_1', { token: 'jwt' })
    expect(result).toBeUndefined()
  })
})
