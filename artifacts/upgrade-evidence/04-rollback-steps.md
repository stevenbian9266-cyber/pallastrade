# Rollback Steps
Generated: 2026-07-27T04-16-53-592Z
Commit: 6de7a06

## Quick Rollback (automated)
```bash
harness upgrade:rollback
```

## Manual Rollback
1. Git: `git reset --hard <pre-upgrade-commit>`
2. Database: `cd backend && bundle exec rails db:rollback`
3. Assets: `cd backend && bundle exec rails assets:precompile`
4. Verify: `harness doctor`
