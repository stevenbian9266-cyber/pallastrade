import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';

// Knowledge sync rules — mirrors AGENTS.md section 7
const SYNC_RULES = [
  {
    codeGlob: /^backend\/app\/models\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-catalog/SKILL.md', 'ai/skills/pallastrade-data-model/SKILL.md'],
    anyOf: true,
    label: 'Model change',
  },
  {
    codeGlob: /^backend\/app\/controllers\/.*\/api\/v3\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-api-v3/SKILL.md'],
    label: 'API endpoint change',
  },
  {
    codeGlob: /^backend\/app\/decorators\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-decorators/SKILL.md'],
    label: 'Decorator change',
  },
  {
    codeGlob: /^backend\/app\/subscribers\/.*\.rb$/,
    docs: ['ai/skills/pallastrade-events-webhooks/SKILL.md'],
    label: 'Subscriber change',
  },
  {
    codeGlob: /^storefront\/src\/components\/.*\.tsx$/,
    docs: ['ai/skills/pallastrade-storefront/SKILL.md'],
    label: 'Storefront component change',
  },
  {
    codeGlob: /^storefront\/src\/app\/.*\.tsx$/,
    docs: ['ai/skills/pallastrade-storefront/SKILL.md'],
    label: 'Storefront page change',
  },
  {
    codeGlob: /\.(css|scss)$|tailwind\.config\./,
    docs: ['ai/skills/pallastrade-storefront/SKILL.md', 'ai/skills/pallastrade-admin/SKILL.md'],
    anyOf: true,
    label: 'Style change',
  },
  {
    codeGlob: /^platform\/packages\/dashboard-ui\/.*\.tsx$/,
    docs: ['ai/skills/pallastrade-admin/SKILL.md'],
    label: 'Dashboard UI component change',
  },
  {
    codeGlob: /^ai\/skills\/.*\/SKILL\.md$/,
    docs: ['harness/scenarios/scenarios.json'],
    label: 'Skill file change',
  },
  {
    codeGlob: /^harness\/policies\/anti-patterns\.json$/,
    docs: ['AGENTS.md'],
    label: 'Policy change',
  },
];

export async function run({ rootDir, args }) {
  const base = args.includes('--base') ? args[args.indexOf('--base') + 1] : 'origin/main';

  // Get changed files
  let changedFiles = [];
  try {
    const diff = execSync(`git diff --name-only ${base}...HEAD`, { cwd: rootDir, encoding: 'utf-8' }).trim();
    changedFiles = diff ? diff.split('\n').filter(Boolean) : [];
  } catch {
    // If git command fails (e.g., no commits), check staged changes
    try {
      const diff = execSync('git diff --name-only --cached', { cwd: rootDir, encoding: 'utf-8' }).trim();
      changedFiles = diff ? diff.split('\n').filter(Boolean) : [];
    } catch {
      console.log('⚠️  Could not determine changed files. Skipping doc-impact check.');
      return;
    }
  }

  if (changedFiles.length === 0) {
    console.log('✅ doc-impact: no changed files to check.');
    return;
  }

  console.log(`Changed files: ${changedFiles.length}\n`);

  // Build list of required docs
  const requiredDocs = new Map(); // doc -> [{ rule, triggerFile }]
  const uncheckedFiles = [...changedFiles];

  for (const rule of SYNC_RULES) {
    const matchedFiles = changedFiles.filter(f => rule.codeGlob.test(f));
    if (matchedFiles.length === 0) continue;

    // Remove matched files from unchecked
    for (const mf of matchedFiles) {
      const idx = uncheckedFiles.indexOf(mf);
      if (idx >= 0) uncheckedFiles.splice(idx, 1);
    }

    for (const doc of rule.docs) {
      if (!requiredDocs.has(doc)) {
        requiredDocs.set(doc, []);
      }
      requiredDocs.get(doc).push({
        rule: rule.label,
        triggers: matchedFiles,
      });
    }
  }

  if (requiredDocs.size === 0) {
    console.log('✅ doc-impact: no knowledge doc updates required for these changes.');
    if (uncheckedFiles.length > 0) {
      console.log(`   (${uncheckedFiles.length} file(s) not matched by any sync rule)`);
    }
    return;
  }

  // Check if required docs exist (were created) or were updated in this PR
  let synced = 0;
  let missing = 0;
  const missingDocs = [];

  for (const [doc, sources] of requiredDocs) {
    const docPath = resolve(rootDir, doc);
    const docExists = existsSync(docPath);
    const docChanged = changedFiles.includes(doc);

    if (docChanged) {
      console.log(`  [✓] ${doc} ← ${sources[0].rule}`);
      synced++;
    } else if (docExists) {
      console.log(`  [?] ${doc} exists but was NOT changed in this PR ← ${sources[0].rule}`);
      missingDocs.push({ doc, exists: true, sources });
      missing++;
    } else {
      console.log(`  [ ] ${doc} MISSING ← ${sources[0].rule}`);
      missingDocs.push({ doc, exists: false, sources });
      missing++;
    }
  }

  console.log(`\n${synced} synced, ${missing} missing or unchanged.`);

  if (missing > 0) {
    console.log('\n📋 The following knowledge docs must be updated:');
    for (const m of missingDocs) {
      const icon = m.exists ? '[?]' : '[ ]';
      console.log(`  ${icon} ${m.doc} — ${m.sources[0].rule} (triggered by: ${m.sources[0].triggers[0]})`);
    }
    console.log('\n❌ PR blocked: docs-required');
    console.log('   Update the listed knowledge documents and push again.');
    process.exit(1);
  }

  console.log('✅ All required knowledge docs are synced.');
}
