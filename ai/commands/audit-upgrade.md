---
description: Audit this PallasTrade app for upgrade readiness — breaking changes vs your code, manifest plan, SDK drift — without changing anything
argument-hint: [target-version]
allowed-tools: Task, Bash, Read, Grep, Glob, WebFetch
---

# PallasTrade upgrade-readiness audit

Target version: `$ARGUMENTS` — if blank, detect the installed version (step 1) and target the next minor.

This command is **read-only/advisory**: never run `pallastrade upgrade`, `bundle update`, or migrations from here. The output is a readiness report; the user runs the upgrade.

Flavor note: on a classic Rails app (PallasTrade gems at the repo root, no Docker/CLI), read `Gemfile.lock` instead of `backend/Gemfile.lock`, get the plan with `DRY_RUN=1 bundle exec rake pallastrade:upgrade` instead of `pallastrade upgrade --plan`, and the closing recommendation becomes the native sequence: `bundle update <pallastrade gems>`, `bin/rake pallastrade:install:migrations && bin/rails db:migrate`, `bin/rake pallastrade:upgrade`.

## Steps

1. **Determine the version hop.** Installed: the `pallastrade_core` entry in `backend/Gemfile.lock` (monorepo edge projects resolve gems via path — read the version from the monorepo's gemspec instead). Target: `$ARGUMENTS` or the next minor.

2. **Read the official upgrade doc for that hop.** Local first: `node_modules/@pallastrade/docs/dist/developer/upgrades/<from>-to-<to>.md`; fall back to `https://pallastrade.cn/docs/developer/upgrades/<from>-to-<to>`. Extract three lists: (a) the data-backfill steps the rake manifest automates, (b) required post-upgrade configuration the manifest does NOT cover (cron jobs, env), (c) breaking changes that may require code edits.

3. **Spawn the `pallastrade-expert` agent** (Task tool, `subagent_type: pallastrade-expert`) with a charter built from the breaking-changes list, for example:

   > Audit this codebase for the PallasTrade <from> → <to> upgrade. For each breaking change below, find concrete usages with file:line evidence — or state it's not used: <enumerate the breaking changes>. Check specifically: decorators in `backend/app/` referencing renamed or removed PallasTrade classes/methods; storefront code (`apps/storefront/`) string-matching wire formats that changed; custom subscribers/services touching changed models. Also report the `@pallastrade/sdk` version declared in `apps/storefront/package.json` and whether it matches the target PallasTrade version's compatibility row. Return findings only — no fixes.

4. **Get the manifest plan.** If the stack is running, run `pallastrade upgrade --plan` and capture the step list. If the stack is down, note that and reconstruct the steps from the upgrade doc instead.

5. **Synthesize the readiness report:**
   - **Verdict:** READY / READY WITH CHANGES / BLOCKED
   - **Findings table:** severity | file:line | what breaks | the fix
   - **Automated steps:** the manifest plan from step 4 (these run via `pallastrade upgrade`)
   - **Manual checklist:** everything from step 2(b) and 2(c) the manifest won't do — cron scheduling, SDK bump (with the exact `npm install @pallastrade/sdk@^X` command and where), behavior changes to review
   - **Remediation order:** what to fix before upgrading, then the closing line: run `pallastrade upgrade` when the list is clear.
