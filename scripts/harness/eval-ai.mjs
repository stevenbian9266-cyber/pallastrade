import { readFileSync, existsSync, readdirSync, statSync } from 'node:fs';
import { resolve, join } from 'node:path';

export async function run({ rootDir, args }) {
  const checkFreshness = args.includes('--check-freshness');

  if (checkFreshness) {
    await checkFreshnessImpl(rootDir);
  }
}

function resolveSmartPath(rootDir, ref) {
  // Try path resolution strategies in order — Skill files may reference
  // paths relative to different "base" directories depending on context.

  const candidates = [];

  // 1. As-is from repository root
  candidates.push(resolve(rootDir, ref));

  // 2. With backend/ prefix (for Rails app paths like config/..., app/...)
  if (!ref.startsWith('backend/') && !ref.startsWith('platform/') && !ref.startsWith('storefront/') && !ref.startsWith('ai/') && !ref.startsWith('harness/') && !ref.startsWith('scripts/') && !ref.startsWith('docs/')) {
    candidates.push(resolve(rootDir, 'backend', ref));
  }

  // 3. Old gem paths → new gem paths
  // pallastrade/admin/... → backend/pallastrade_gems/pallastrade_admin/...
  const gemMatch = ref.match(/^pallastrade\/(\w+)\/(.+)/);
  if (gemMatch) {
    candidates.push(resolve(rootDir, 'backend', 'pallastrade_gems', `pallastrade_${gemMatch[1]}`, gemMatch[2]));
    // Also try without the sub-path (just the gem root)
    candidates.push(resolve(rootDir, 'backend', 'pallastrade_gems', `pallastrade_${gemMatch[1]}`));
  }

  // 4. packages/... → platform/packages/...
  if (ref.startsWith('packages/')) {
    candidates.push(resolve(rootDir, 'platform', ref));
  }

  // 5. types/... → platform/packages/sdk/src/types/... (TypeScript type references)
  if (ref.startsWith('types/')) {
    candidates.push(resolve(rootDir, 'platform', 'packages', 'sdk', 'src', ref));
  }

  // 6. docs/... → platform/docs/ or root docs/
  if (ref.startsWith('docs/')) {
    candidates.push(resolve(rootDir, 'platform', ref));
    candidates.push(resolve(rootDir, ref));
  }

  // Return the first candidate that exists
  for (const c of candidates) {
    if (existsSync(c)) return c;
  }

  return null;
}

function resolveSmartDir(rootDir, ref) {
  // Same logic but for directories
  const candidates = [];
  candidates.push(resolve(rootDir, ref));

  if (!ref.startsWith('backend/') && !ref.startsWith('platform/') && !ref.startsWith('storefront/') && !ref.startsWith('ai/')) {
    candidates.push(resolve(rootDir, 'backend', ref));
  }

  const gemMatch = ref.match(/^pallastrade\/(\w+)\/(.+)/);
  if (gemMatch) {
    candidates.push(resolve(rootDir, 'backend', 'pallastrade_gems', `pallastrade_${gemMatch[1]}`, gemMatch[2]));
  }

  for (const c of candidates) {
    if (existsSync(c) && statSync(c).isDirectory()) return c;
  }

  return null;
}

async function checkFreshnessImpl(rootDir) {
  const skillDir = resolve(rootDir, 'ai', 'skills');
  if (!existsSync(skillDir)) {
    console.log('⚠️  ai/skills/ directory not found. Skipping freshness check.');
    return;
  }

  const skills = readdirSync(skillDir, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => d.name);

  let errors = 0;
  let warnings = 0;

  for (const skill of skills) {
    const skillFile = join(skillDir, skill, 'SKILL.md');
    if (!existsSync(skillFile)) continue;

    const content = readFileSync(skillFile, 'utf-8');

    // Extract path references in backticks that look like file paths
    const pathRefs = content.matchAll(/`([a-z_]+\/[a-z0-9_\/\.\-\[\]\*]+)`/gi);
    for (const m of pathRefs) {
      const ref = m[1];
      if (!ref.includes('/') || ref.startsWith('http') || ref.includes(' ')) continue;
      // Skip build output paths (dist/, node_modules/)
      if (ref.startsWith('dist/') || ref.includes('node_modules/')) continue;
      if (ref.endsWith('.rb') || ref.endsWith('.ts') || ref.endsWith('.tsx') || ref.endsWith('.json') || ref.endsWith('.yml') || ref.endsWith('.yaml') || ref.endsWith('.md') || ref.endsWith('.mjs') || ref.endsWith('.js') || ref.endsWith('.css')) {
        const found = resolveSmartPath(rootDir, ref);
        if (!found) {
          console.log(`❌ ${skill}/SKILL.md: path not found — \`${ref}\``);
          errors++;
        }
      }
    }

    // Check for directory references
    const dirRefs = content.matchAll(/`([a-z_]+\/[a-z0-9_\/\.\-]+)\/`/gi);
    for (const m of dirRefs) {
      const ref = m[1];
      if (!ref.includes(' ') && !ref.startsWith('http')) {
        // Skip build output dirs
        if (ref.startsWith('dist/') || ref.includes('node_modules/')) continue;
        const found = resolveSmartDir(rootDir, ref);
        if (!found) {
          console.log(`❌ ${skill}/SKILL.md: directory not found — \`${ref}/\``);
          errors++;
        }
      }
    }
  }

  if (errors > 0) {
    console.log(`\n❌ ${errors} freshness error(s) — skill files reference non-existent paths.`);
    process.exit(1);
  }

  console.log(`✅ ${skills.length} skills checked, 0 path errors, ${warnings} warning(s).`);
}
