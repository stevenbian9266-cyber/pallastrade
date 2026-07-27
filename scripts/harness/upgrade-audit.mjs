import { readFileSync, existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { execSync } from 'node:child_process';
import { globSync } from 'glob';

export async function audit({ rootDir, args }) {
  const from = args.includes('--from') ? args[args.indexOf('--from') + 1] : 'current';
  const to = args.includes('--to') ? args[args.indexOf('--to') + 1] : 'next';
  const format = args.includes('--format') ? args[args.indexOf('--format') + 1] : 'json';

  // 1. Check for customization manifest
  const manifestFile = resolve(rootDir, '.pallastrade-customization');
  const customizationRoots = existsSync(manifestFile)
    ? ['backend/app/', 'storefront/src/'] // fallback: standard customer directories
    : ['backend/app/', 'storefront/src/'];

  // 2. Load breaking changes
  const bcFile = resolve(rootDir, 'harness', 'versions', `v${to}`, 'breaking-changes.json');
  let breakingChanges = [];
  if (existsSync(bcFile)) {
    breakingChanges = JSON.parse(readFileSync(bcFile, 'utf-8'));
  } else {
    console.log(`⚠️  No breaking-changes.json for v${to}. Using empty list.`);
  }

  // 3. Collect customer files
  const customerFiles = [];
  for (const root of customizationRoots) {
    const fullRoot = resolve(rootDir, root);
    if (existsSync(fullRoot)) {
      const rbFiles = globSync('**/*.rb', { cwd: fullRoot, absolute: false }).map(f => `${root}${f}`);
      customerFiles.push(...rbFiles);
    }
  }

  // 4. Scan
  const findings = [];
  for (const file of customerFiles) {
    const filePath = resolve(rootDir, file);
    if (!existsSync(filePath)) continue;
    const content = readFileSync(filePath, 'utf-8');
    const lines = content.split('\n');

    for (const bc of breakingChanges) {
      const regex = new RegExp(bc.pattern, 'gm');
      for (let i = 0; i < lines.length; i++) {
        if (regex.test(lines[i])) {
          findings.push({
            file,
            line: i + 1,
            severity: bc.severity || 'medium',
            breakingChange: bc.title,
            matchedCode: lines[i].trim().slice(0, 100),
            suggestedFix: bc.fix || 'Manual review required',
            skillReference: bc.skillRef || null,
          });
        }
      }
    }
  }

  // 5. Report
  const report = {
    from, to,
    timestamp: new Date().toISOString(),
    customerFilesScanned: customerFiles.length,
    breakingChangesChecked: breakingChanges.length,
    impactedFiles: [...new Set(findings.map(f => f.file))].length,
    totalImpacts: findings.length,
    findings,
    recommendation: findings.some(f => f.severity === 'critical') ? 'BLOCKED'
      : findings.length > 0 ? 'REVIEW_REQUIRED' : 'SAFE_TO_UPGRADE',
  };

  if (format === 'json') {
    console.log(JSON.stringify(report, null, 2));
  } else {
    console.log(`Upgrade Audit: ${from} → ${to}`);
    console.log(`Files scanned: ${report.customerFilesScanned}`);
    console.log(`Impacts found: ${report.totalImpacts}`);
    console.log(`Recommendation: ${report.recommendation}\n`);
    for (const f of findings) {
      console.log(`  ${f.severity.toUpperCase()} ${f.file}:${f.line}`);
      console.log(`    ${f.breakingChange}`);
      console.log(`    Fix: ${f.suggestedFix}\n`);
    }
  }

  if (report.recommendation === 'BLOCKED') process.exit(1);
}
