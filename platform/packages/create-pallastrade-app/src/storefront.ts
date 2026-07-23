import fs from 'node:fs'
import path from 'node:path'
import { execa } from 'execa'
import { copyCanonicalComponent } from './repository.js'
import { storefrontEnvContent } from './templates/env.js'
import type { PackageManager } from './types.js'
import { installCommand } from './utils.js'

export async function downloadStorefront(projectDir: string, checkoutDir: string): Promise<void> {
  const storefrontDir = path.join(projectDir, 'apps', 'storefront')
  fs.mkdirSync(path.dirname(storefrontDir), { recursive: true })
  copyCanonicalComponent(checkoutDir, 'storefront', storefrontDir)
}

export async function installRootDeps(projectDir: string, pm: PackageManager): Promise<void> {
  const [cmd, ...args] = installCommand(pm).split(' ')
  await execa(cmd, args, { cwd: projectDir, stdio: 'ignore' })
}

export async function installStorefrontDeps(projectDir: string, pm: PackageManager): Promise<void> {
  const storefrontDir = path.join(projectDir, 'apps', 'storefront')
  const [cmd, ...args] = installCommand(pm).split(' ')
  await execa(cmd, args, { cwd: storefrontDir, stdio: 'ignore' })
}

export function writeStorefrontEnv(projectDir: string, port: number, apiKey?: string): void {
  const envPath = path.join(projectDir, 'apps', 'storefront', '.env.local')
  fs.writeFileSync(envPath, storefrontEnvContent(port, apiKey))
}
