export default {
  extends: ['@commitlint/config-conventional'],
  rules: {
    'scope-enum': [
      2,
      'always',
      ['keycloak', 'keycloak-config', 'ci', 'deps', ''],
    ],
  },
};
