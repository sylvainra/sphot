"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");
const {registerSauveteurManagementPilot} =
  require("../sauveteur_management_pilot");

const TEST_LOGIN = "psphottest2026";
const ADMIN_LOGIN = "admin-pilot@example.test";

/**
 * @param {Object} overrides Account values to override.
 * @return {Object} Isolated mock functions and fake responses.
 */
function createFixture(overrides = {}) {
  const calls = [];
  let pilot = {
    accounts: {ADMIN: ADMIN_LOGIN},
    testSauveteurLogin: TEST_LOGIN,
  };
  const exports = registerSauveteurManagementPilot({
    onRequest: (_options, handler) => handler,
    activePasswordPilot: () => pilot,
    verifiedTerritoryAdmin: async (request) =>
      request.authenticated ? {
        adminUid: "uid-test", territoireId: "territoire-test",
      } : null,
    isSuperAdminAccount: (data) => data.role === "SUPER_ADMIN",
    admin: {firestore: () => ({
      collection: (name) => {
        assert.equal(name, "adminAccounts");
        return {
          doc: (login) => {
            assert.equal(login, ADMIN_LOGIN);
            return {get: async () => ({
              exists: true,
              data: () => ({
                role: overrides.role || "ADMIN",
                accountStatus: overrides.accountStatus || "ACTIVE",
                adminUid: "uid-test", territoireId: "territoire-test",
              }),
            })};
          },
        };
      },
    })},
    handlers: {
      upsert: async () => calls.push("upsert"),
      sendEmail: async () => calls.push("sendEmail"),
      remove: async () => calls.push("remove"),
      changePassword: async () => calls.push("changePassword"),
    },
  });
  const response = () => ({
    statusCode: 0,
    set() {
      return this;
    },
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(body) {
      this.body = body;
      return this;
    },
    send(body) {
      this.body = body;
      return this;
    },
  });
  return {exports, calls, response, disable: () => {
    pilot = null;
  }};
}

test("pilot management rejects other accounts and disabled pilot", async () => {
  const fixture = createFixture();
  const other = fixture.response();
  await fixture.exports.upsertSauveteurAccountPilot({
    method: "POST", authenticated: true, body: {login: "unrelated"},
  }, other);
  assert.equal(other.statusCode, 403);
  assert.deepEqual(fixture.calls, []);

  fixture.disable();
  const disabled = fixture.response();
  await fixture.exports.deleteSauveteurAccountPilot({
    method: "POST", authenticated: true, body: {login: TEST_LOGIN},
  }, disabled);
  assert.equal(disabled.statusCode, 403);
  assert.deepEqual(fixture.calls, []);
});

test("only authenticated matching territory Admin can manage test account",
    async () => {
      const fixture = createFixture();
      const unauthorized = fixture.response();
      await fixture.exports.upsertSauveteurAccountPilot({
        method: "POST", authenticated: false, body: {login: TEST_LOGIN},
      }, unauthorized);
      assert.equal(unauthorized.statusCode, 403);
      assert.deepEqual(fixture.calls, []);

      const authorized = fixture.response();
      await fixture.exports.upsertSauveteurAccountPilot({
        method: "POST", authenticated: true, body: {login: TEST_LOGIN},
      }, authorized);
      assert.deepEqual(fixture.calls, ["upsert"]);
    });

test("pilot email, delete and first password change use only test login",
    async () => {
      const fixture = createFixture();
      await fixture.exports.sendSauveteurCredentialsEmailPilot({
        method: "POST", authenticated: true,
        body: {identifiant: TEST_LOGIN},
      }, fixture.response());
      await fixture.exports.deleteSauveteurAccountPilot({
        method: "POST", authenticated: true, body: {login: TEST_LOGIN},
      }, fixture.response());
      await fixture.exports.changeSauveteurPasswordPilot({
        method: "POST", body: {login: TEST_LOGIN},
      }, fixture.response());
      assert.deepEqual(fixture.calls,
          ["sendEmail", "remove", "changePassword"]);

      const wrong = fixture.response();
      await fixture.exports.sendSauveteurCredentialsEmailPilot({
        method: "POST", authenticated: true,
        body: {identifiant: "someone-else"},
      }, wrong);
      assert.equal(wrong.statusCode, 403);
      assert.equal(fixture.calls.length, 3);
    });

test("Super Admin is rejected even when a valid token is supplied",
    async () => {
      const fixture = createFixture({role: "SUPER_ADMIN"});
      const response = fixture.response();
      await fixture.exports.deleteSauveteurAccountPilot({
        method: "POST", authenticated: true, body: {login: TEST_LOGIN},
      }, response);
      assert.equal(response.statusCode, 403);
      assert.deepEqual(fixture.calls, []);
    });

test("CORS preflight succeeds without executing an operation", async () => {
  const fixture = createFixture();
  const response = fixture.response();
  await fixture.exports.sendSauveteurCredentialsEmailPilot({
    method: "OPTIONS", body: {},
  }, response);
  assert.equal(response.statusCode, 204);
  assert.deepEqual(fixture.calls, []);
});
