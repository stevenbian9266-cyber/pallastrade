export function rootPackageJsonContent(name: string): string {
  const pkg = {
    name,
    private: true,
    scripts: {
      dev: 'pallastrade dev',
      stop: 'pallastrade stop',
      down: 'docker compose down',
      update: 'pallastrade update',
      eject: 'pallastrade eject',
      logs: 'pallastrade logs',
      'logs:worker': 'pallastrade logs worker',
      seed: 'pallastrade seed',
      'load-sample-data': 'pallastrade sample-data',
      console: 'pallastrade console',
      api: 'pallastrade api',
      auth: 'pallastrade auth',
      'api-key': 'pallastrade api-key',
    },
    dependencies: {
      // The floor matches the CLI behavior this scaffold relies on (the
      // --quiet delegation, dev co-run, first-run setup) — an older resolve
      // would reject the flags and silently drop the dashboard phase.
      // PALLASTRADE_CLI_VERSION overrides the spec for testing unreleased CLIs —
      // a range, or a `file:`/`link:` path to a packed tarball / checkout
      // (mirrors the starter Dockerfile's ARG of the same name).
      '@pallastrade/cli': process.env.PALLASTRADE_CLI_VERSION ?? '^2.4.4',
      '@pallastrade/docs': 'latest',
    },
  }

  return `${JSON.stringify(pkg, null, 2)}\n`
}
