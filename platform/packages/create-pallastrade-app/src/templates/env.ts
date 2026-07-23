/**
 * The project root `.env`: Rails secret, backend port, image tag, and the
 * persisted sample-data choice (`PALLASTRADE_SAMPLE_DATA`) that first-run setup
 * reads back when it runs deferred (through `pallastrade dev`).
 */
export function envContent(secretKeyBase: string, port: number, sampleData: boolean): string {
  return `SECRET_KEY_BASE=${secretKeyBase}
PALLASTRADE_PORT=${port}
PALLASTRADE_VERSION_TAG=latest
# Whether first-run setup loads demo products and orders.
PALLASTRADE_SAMPLE_DATA=${sampleData}
`
}

export function storefrontEnvContent(port: number, apiKey?: string): string {
  return `PALLASTRADE_API_URL=http://localhost:${port}
PALLASTRADE_PUBLISHABLE_KEY=${apiKey ?? 'pk_REPLACE_ME_AFTER_DOCKER_START'}
`
}
