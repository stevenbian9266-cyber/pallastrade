import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { execa } from 'execa'
import { CANONICAL_BRANCH, CANONICAL_REPOSITORY, COMPONENT_PATHS } from './constants.js'

export type CanonicalComponent = keyof typeof COMPONENT_PATHS

export async function cloneCanonicalRepository(): Promise<string> {
  const tempRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'pallastrade-canonical-'))
  const checkoutDir = path.join(tempRoot, 'repository')

  try {
    await execa(
      'git',
      [
        'clone',
        '--depth',
        '1',
        '--branch',
        CANONICAL_BRANCH,
        '--single-branch',
        CANONICAL_REPOSITORY,
        checkoutDir,
      ],
      { stdio: 'ignore' },
    )
    return checkoutDir
  } catch (error) {
    fs.rmSync(tempRoot, { recursive: true, force: true })
    throw error
  }
}

export function copyCanonicalComponent(
  checkoutDir: string,
  component: CanonicalComponent,
  destination: string,
): void {
  const source = path.join(checkoutDir, COMPONENT_PATHS[component])
  if (!fs.statSync(source, { throwIfNoEntry: false })?.isDirectory()) {
    throw new Error(`Canonical repository is missing ${COMPONENT_PATHS[component]}/`)
  }
  fs.cpSync(source, destination, { recursive: true, errorOnExist: true })
}

export function removeCanonicalRepository(checkoutDir: string): void {
  fs.rmSync(path.dirname(checkoutDir), { recursive: true, force: true })
}
