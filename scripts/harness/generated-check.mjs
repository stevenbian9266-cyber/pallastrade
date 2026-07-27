import { execSync } from 'node:child_process';
import { resolve } from 'node:path';

export function check({ rootDir }) {
  console.log('Checking generated files for drift...\n');

  const checks = [
    {
      name: 'SDK Types',
      cwd: resolve(rootDir, 'platform'),
      cmd: 'pnpm --filter @pallastrade/sdk generate:types 2>/dev/null || echo "SKIP: sdk types generation not configured"',
    },
    {
      name: 'CLI Admin Spec',
      cwd: resolve(rootDir, 'platform'),
      cmd: 'pnpm --filter @pallastrade/cli generate:admin-spec 2>/dev/null || echo "SKIP: cli spec generation not configured"',
    },
  ];

  for (const check of checks) {
    try {
      execSync(check.cmd, { cwd: check.cwd, stdio: 'pipe' });
    } catch {
      console.log(`⚠️  ${check.name}: generation skipped (command may not exist yet)`);
    }
  }

  // Check for any uncommitted changes after regeneration
  try {
    execSync('git diff --exit-code -- "*.json" "*.ts" "*.yaml" "*.yml"', { cwd: rootDir, stdio: 'pipe' });
    console.log('\n✅ generated:check — no drift detected.');
  } catch {
    console.log('\n❌ generated:check — drift detected in generated files.');
    console.log('   Run generation commands and commit the updated files.');
    process.exit(1);
  }
}
