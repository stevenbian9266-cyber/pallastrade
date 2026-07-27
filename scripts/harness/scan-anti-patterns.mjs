import { readFileSync, existsSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { globSync } from 'glob';

export function scan({ rootDir }) {
  const rulesPath = resolve(rootDir, 'harness', 'policies', 'anti-patterns.json');
  if (!existsSync(rulesPath)) {
    console.log('⚠️  No anti-patterns rules file found. Skipping scan.');
    return;
  }

  const { rules } = JSON.parse(readFileSync(rulesPath, 'utf-8'));
  let totalViolations = 0;
  let errors = 0;
  let warnings = 0;

  for (const rule of rules) {
    try {
      const files = globSync(rule.fileGlob, { cwd: rootDir, ignore: rule.excludeGlob ? [rule.excludeGlob] : [] });

      for (const file of files) {
        const filePath = resolve(rootDir, file);
        if (!existsSync(filePath)) continue;
        // Skip directories — glob may return them for certain patterns
        if (statSync(filePath).isDirectory()) continue;

        const content = readFileSync(filePath, 'utf-8');
        const regex = new RegExp(rule.pattern, 'gm');
        const lines = content.split('\n');

        for (let i = 0; i < lines.length; i++) {
          if (regex.test(lines[i])) {
            const lineNum = i + 1;
            const icon = rule.severity === 'error' ? '❌' : '⚠️';
            console.log(`${icon} ${rule.id} [${rule.severity}] ${file}:${lineNum}`);
            console.log(`   ${rule.message}`);
            console.log(`   Fix: ${rule.fix}`);
            console.log(`   Code: ${lines[i].trim().slice(0, 120)}`);
            console.log('');

            totalViolations++;
            if (rule.severity === 'error') errors++;
            else warnings++;
          }
        }
      }
    } catch (e) {
      console.log(`⚠️  Rule ${rule.id}: error scanning: ${e.message}`);
    }
  }

  if (totalViolations === 0) {
    console.log('✅ No anti-patterns detected.');
  } else {
    console.log(`${totalViolations} violation(s): ${errors} error(s), ${warnings} warning(s).`);
    if (errors > 0) {
      console.log('❌ Anti-pattern scan failed with errors.');
      process.exit(1);
    }
  }
}

// CLI entry
const args = process.argv.slice(2);
if (args.length > 0 && args[0] === 'scan') {
  const rootDir = resolve(import.meta.dirname, '..', '..');
  scan({ rootDir });
}
