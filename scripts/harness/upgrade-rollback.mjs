import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

export async function rollback({ rootDir }) {
  // 1. Find pre-upgrade tag
  let tag = '';
  try {
    tag = execSync('git tag --list "pre-upgrade-*" --sort=-creatordate | head -1', { cwd: rootDir, encoding: 'utf-8' }).trim();
  } catch { /* no tags */ }

  if (!tag) {
    console.error('❌ No pre-upgrade tag found.');
    console.error('   Before upgrading, create a safety tag:');
    console.error('   git tag pre-upgrade-$(date +%Y%m%d_%H%M%S)');
    console.error('   git push origin --tags');
    process.exit(1);
  }

  console.log(`⚠️  Rolling back to ${tag}...`);
  console.log('');

  // 2. Git rollback
  console.log('1/4 Rolling back code...');
  execSync(`git reset --hard ${tag}`, { cwd: rootDir, stdio: 'inherit' });

  // 3. DB rollback (best effort)
  console.log('2/4 Rolling back database...');
  try {
    execSync('cd backend && bundle exec rails db:rollback STEP=1', { cwd: rootDir, stdio: 'pipe' });
    console.log('   Database rollback attempted.');
  } catch {
    console.log('   ⚠️  Database rollback failed — may need manual intervention.');
  }

  // 4. Asset rebuild
  console.log('3/4 Rebuilding assets...');
  try {
    execSync('cd backend && bundle exec rails assets:clean assets:precompile', { cwd: rootDir, stdio: 'pipe' });
    console.log('   Assets rebuilt.');
  } catch {
    console.log('   ⚠️  Asset rebuild skipped (Docker may not be running).');
  }

  // 5. Verify
  console.log('4/4 Verifying rollback...');
  try {
    execSync('node scripts/harness/cli.mjs doctor', { cwd: rootDir, stdio: 'inherit' });
    console.log('\n✅ Rollback complete. System at pre-upgrade state.');
  } catch {
    console.log('\n⚠️  Rollback executed but verification showed issues. Review manually.');
    process.exit(1);
  }
}
