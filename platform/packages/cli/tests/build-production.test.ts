import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import { afterEach, beforeEach, describe, expect, it } from 'vitest'
import { planProductionBuild } from '../src/commands/build.js'

/**
 * Pure planning logic for `pallastrade build --production` — the safety contract:
 * the plan is exactly what `docker build backend/` would run, nothing more.
 */
describe('planProductionBuild', () => {
  let projectDir: string

  beforeEach(() => {
    projectDir = fs.mkdtempSync(path.join(os.tmpdir(), 'pallastrade-prod-build-'))
    fs.mkdirSync(path.join(projectDir, 'backend'))
  })

  afterEach(() => {
    fs.rmSync(projectDir, { recursive: true, force: true })
  })

  function writeDockerfile(content: string) {
    fs.writeFileSync(path.join(projectDir, 'backend', 'Dockerfile'), content)
  }

  it('throws without a backend Dockerfile', () => {
    expect(() => planProductionBuild(projectDir)).toThrow(/backend\/Dockerfile/)
  })

  it('builds the backend image from the Dockerfile', () => {
    writeDockerfile('FROM ruby\n')

    const plan = planProductionBuild(projectDir, 'shop:1')

    expect(plan.args).toEqual([
      'build',
      path.join(projectDir, 'backend'),
      '-f',
      path.join(projectDir, 'backend', 'Dockerfile'),
      '-t',
      'shop:1',
    ])
    // No extra build-args / build-contexts.
    expect(plan.args).not.toContain('--build-arg')
    expect(plan.args).not.toContain('--build-context')
  })

  it('derives a sanitized default tag from the project directory', () => {
    writeDockerfile('FROM ruby\n')

    const plan = planProductionBuild(projectDir)

    expect(plan.imageTag).toMatch(/^[a-z0-9_-]+-pallastrade:latest$/)
  })
})
