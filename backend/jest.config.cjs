module.exports = {
  rootDir: 'src',
  testEnvironment: 'node',
  transformIgnorePatterns: ['node_modules/.pnpm/(?!@nestjs\\+)'],
  testRegex: '.*\\.spec\\.ts$',
  transform: {
    '^.+\\.(t|j)s$': [
      '@swc/jest',
      {
        swcrc: false,
        jsc: {
          parser: { syntax: 'typescript', decorators: true },
          transform: { legacyDecorator: true, decoratorMetadata: true },
        },
        module: { type: 'commonjs' },
      },
    ],
  },
};
