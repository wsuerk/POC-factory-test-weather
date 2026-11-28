/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: 'no-circular',
      severity: 'error',
      comment: 'Modules must not depend on each other in a cycle.',
      from: {},
      to: { circular: true },
    },
    {
      name: 'no-app-to-bootstrap',
      severity: 'error',
      comment: 'Application code must not import the bootstrap entry point.',
      from: { path: '^src/app/' },
      to: { path: '^src/main\.ts$' },
    },
    {
      name: 'not-to-spec',
      severity: 'error',
      comment: 'Production code must not import test files.',
      from: { pathNot: '\.spec\.ts$' },
      to: { path: '\.spec\.ts$' },
    },
    {
      name: 'not-to-unresolvable',
      severity: 'error',
      comment: 'Every import must resolve.',
      from: {},
      to: { couldNotResolve: true },
    },
  ],
  options: {
    doNotFollow: { path: 'node_modules' },
    tsConfig: { fileName: 'tsconfig.json' },
    tsPreCompilationDeps: true,
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require", "node", "default", "types"],
      mainFields: ["module", "main", "types", "typings"],
    },
  },
};
