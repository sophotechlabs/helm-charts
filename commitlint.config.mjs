export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    // The two charts, plus the parts of the repo that are not a chart. Derived
    // from what the history actually uses — the first version of this list was
    // guessed and rejected a commit written the same day.
    'scope-enum': [
      2,
      'always',
      ['keycloak', 'keycloak-config', 'ci', 'test', 'deps', ''],
    ],
  },
};
