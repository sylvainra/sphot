"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {
  hashPassword,
  isSuperAdminAccount,
  isValidNewPassword,
  verifyAccountPassword,
  verifyPasswordHash,
} = require("../password_security");

test("password hashing is salted and verifiable", () => {
  const first = hashPassword("Example@9Password");
  const second = hashPassword("Example@9Password");
  assert.notEqual(first, second);
  assert.equal(verifyPasswordHash(first, "Example@9Password"), true);
  assert.equal(verifyPasswordHash(first, "Wrong@9Password"), false);
  assert.equal(verifyPasswordHash("malformed", "Example@9Password"), false);
});

test("hash takes priority over a legacy plaintext password", () => {
  const account = {
    temporaryPassword: "Old@9Password",
    passwordHash: hashPassword("New@9Password"),
  };
  assert.equal(verifyAccountPassword(account, "Old@9Password"), false);
  assert.equal(verifyAccountPassword(account, "New@9Password"), true);
  assert.equal(verifyAccountPassword({temporaryPassword: "legacy123"},
      "legacy123"), true);
});

test("new password policy and Super Admin exclusion", () => {
  assert.equal(isValidNewPassword("MyNew@9Password"), true);
  assert.equal(isValidNewPassword("weakpassword"), false);
  assert.equal(isValidNewPassword("MISSINGLOWER@9"), false);
  assert.equal(isSuperAdminAccount({role: "SUPER_ADMIN"}), true);
  assert.equal(isSuperAdminAccount({fonctions: ["SUPER_ADMIN"]}), true);
  assert.equal(isSuperAdminAccount({role: "SAUVETEUR"}), false);
});
