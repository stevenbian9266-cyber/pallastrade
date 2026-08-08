import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';

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
    docs: ['backend/public/api-docs/store.yaml', 'backend/public/api-docs/admin.yaml', 'platform/docs/api-reference/store.yaml', 'platform/docs/api-reference/admin.yaml'],
    anyOf: true,
    label: 'API endpoint change → API docs sync',
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
    codeGlob: /^ai\/skills\/.*\/SKILL\.md$/,
    docs: ['harness/scenarios/scenarios.json'],
    label: 'Skill file change',
  },
  {
    codeGlob: /^harness\/policies\/(anti-patterns|task-rules)\.json$/,
    docs: ['AGENTS.md', '.github/copilot-instructions.md'],
    anyOf: true,
    label: 'Policy change → agent docs sync',
  },
  {
    codeGlob: /^harness\/policies\/prd-categories\.json$/,
    docs: ['ai/skills/pallastrade-prd/SKILL.md', 'docs/prd/README.md'],
    anyOf: true,
    label: 'PRD category change',
  },
  {
    codeGlob: /^docs\/standards\//,
    docs: ['AGENTS.md'],
    label: 'Standards index change → navigation map sync',
  },
  {
    codeGlob: /^docs\/prd\//,
    docs: ['ai/skills/pallastrade-prd/SKILL.md'],
    label: 'PRD doc change',
  },
  {
    codeGlob: /^ai\/commands\/|^ai\/agents\//,
    docs: ['ai/README.md'],
    label: 'AI command/agent change → ai README sync',
  },
  {
    codeGlob: /^platform\/packages\/(cli|sdk|create-pallastrade-app)\//,
    docs: ['platform/README.md', 'platform/packages/README.md'],
    anyOf: true,
    label: 'Platform package change → README sync',
  },
  {
    codeGlob: /^scripts\/harness\//,
    docs: ['AGENTS.md', 'ai/skills/pallastrade-prd/SKILL.md', 'harness/scenarios/scenarios.json'],
    anyOf: true,
    label: 'Harness change → workflow docs sync',
  },
];

export async function run({ rootDir, args }) {
  const base = args.includes('--base') ? args[args.indexOf('--base') + 1] : 'origin/main';

  // Get changed files: committed (vs base) + staged + unstaged.
  const { files: changedFiles, errors } = await import('./git-files.mjs').then(m => m.getChangedFiles(rootDir, base));
  if (errors.length > 0) {
    console.log(`⚠️  git: ${errors.join('; ')}`);
  }

  if (changedFiles.length === 0) {
    console.log('✅ doc-impact: no changed files to check.');
    return;
  }

  console.log(`Changed files: ${changedFiles.length}\n`);

  // Build list of mandatory docs and anyOf (one-of) groups.
  const requiredDocs = new Map(); // doc -> [{ rule, triggers }]
  const anyOfGroups = []; // { label, docs, triggers }
  const uncheckedFiles = [...changedFiles];

  for (const rule of SYNC_RULES) {
    const matchedFiles = changedFiles.filter(f => rule.codeGlob.test(f));
    if (matchedFiles.length === 0) continue;

    // Remove matched files from unchecked
    for (const mf of matchedFiles) {
      const idx = uncheckedFiles.indexOf(mf);
      if (idx >= 0) uncheckedFiles.splice(idx, 1);
    }

    if (rule.anyOf) {
      // anyOf: changing ANY one of the listed docs satisfies the rule.
      anyOfGroups.push({ label: rule.label, docs: rule.docs, triggers: matchedFiles });
    } else {
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
  }

  if (requiredDocs.size === 0 && anyOfGroups.length === 0) {
    console.log('✅ doc-impact: no knowledge doc updates required for these changes.');
    if (uncheckedFiles.length > 0) {
      console.log(`   (${uncheckedFiles.length} file(s) not matched by any sync rule)`);
    }
    return;
  }

  // Check if required docs were updated in this PR.
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

  // anyOf groups — any one changed doc satisfies the whole group.
  for (const group of anyOfGroups) {
    const changedDoc = group.docs.find(doc => changedFiles.includes(doc));
    if (changedDoc) {
      console.log(`  [✓] (anyOf) ${group.label} ← ${changedDoc}`);
      synced++;
    } else {
      console.log(`  [ ] (anyOf) ${group.label} — none of ${group.docs.join(' / ')} changed ← ${group.triggers[0]}`);
      missingDocs.push({ doc: group.docs.join(' | '), exists: true, sources: [{ rule: group.label, triggers: group.triggers }], anyOf: true });
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
