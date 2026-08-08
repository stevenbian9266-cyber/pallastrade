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
      'api-key': 'pallastrade api-key',
    },
    dependencies: {
      '@pallastrade/cli': process.env.PALLASTRADE_CLI_VERSION ?? '^2.4.4',
      '@pallastrade/docs': 'latest',
    },
  }

  return `${JSON.stringify(pkg, null, 2)}\n`
}
