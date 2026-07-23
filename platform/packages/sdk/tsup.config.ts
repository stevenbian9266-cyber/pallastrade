import { defineConfig } from 'tsup'

export default defineConfig({
  entry: {
    index: 'src/index.ts',
    'types/index': 'src/types/index.ts',
    'zod/index': 'src/zod/index.ts',
    webhooks: 'src/webhooks.ts',
  },
  format: ['cjs', 'esm'],
  dts: { resolve: ['@pallastrade/sdk-core'] },
  splitting: false,
  sourcemap: true,
  clean: true,
  treeshake: true,
  minify: false,
  noExternal: ['@pallastrade/sdk-core'],
  esbuildOptions(options) {
    options.alias = {
      '@/types': './src/types/generated/index.ts',
    }
  },
})
