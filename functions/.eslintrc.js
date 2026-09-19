module.exports = {
  env: {
    es6: true,
    node: true,
  },
  parserOptions: {
    "ecmaVersion": 2022,
  },
  extends: [
    "eslint:recommended",
    "google",
  ],
  rules: {
    "no-restricted-globals": [
      "error",
      "name",
      "length",
    ],
    "prefer-arrow-callback": "error",
    "quotes": [
      "error",
      "double",
      {"allowTemplateLiterals": true},
    ],
  },
  overrides: [
    {
      files: ["**/*.spec.*"],
      env: {
        mocha: true,
      },
      rules: {},
    },
    {
      files: ["admin_workflow.js"],
      rules: {
        "require-jsdoc": "off",
        "max-len": "off",
        "quote-props": "off",
      },
    },
  ],
  globals: {},
};
