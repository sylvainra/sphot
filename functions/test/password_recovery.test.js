"use strict";
/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const test = require("node:test");
const {registerPasswordRecovery, digest} =
  require("../password_recovery");
const {verifyAccountPassword} = require("../password_security");

class FakeTimestamp {
  constructor(ms) {
    this.ms = ms;
  }
  toMillis() {
    return this.ms;
  }
  static fromMillis(ms) {
    return new FakeTimestamp(ms);
  }
}

function fakeFirebase() {
  const docs = new Map();
  const deleted = Symbol("deleted");
  const serverTimestamp = () => new FakeTimestamp(Date.now());
  const field = {delete: () => deleted, serverTimestamp};
  const applyFields = (existing, change) => {
    const merged = {...existing};
    for (const [key, value] of Object.entries(change)) {
      if (value === deleted) delete merged[key];
      else merged[key] = value;
    }
    return merged;
  };
  function reference(name, id) {
    const key = `${name}/${id}`;
    return {
      async get() {
        return {exists: docs.has(key), data: () => docs.get(key)};
      },
      async set(value, options) {
        docs.set(key, applyFields(options?.merge ? docs.get(key) : {}, value));
      },
      async update(value) {
        if (!docs.has(key)) throw new Error("Document does not exist");
        docs.set(key, applyFields(docs.get(key), value));
      },
    };
  }
  const db = {
    collection: (name) => ({doc: (id) => reference(name, id)}),
    runTransaction: (callback) => callback({
      get: (ref) => ref.get(),
      set: (ref, value, options) => ref.set(value, options),
      update: (ref, value) => ref.update(value),
    }),
  };
  const admin = {
    firestore: Object.assign(() => db, {
      Timestamp: FakeTimestamp,
      FieldValue: field,
    }),
    auth: () => ({revokeRefreshTokens: async () => {}}),
  };
  return {admin, docs};
}

async function invoke(handler, body) {
  const result = {statusCode: 200, body: null};
  const response = {
    set: () => response,
    status(code) {
      result.statusCode = code; return response;
    },
    json(value) {
      result.body = value; return response;
    },
    send: () => response,
  };
  await handler({method: "POST", body}, response);
  return result;
}

test("recovery uses a hashed single-use token and excludes Super Admin",
    async () => {
      const {admin, docs} = fakeFirebase();
      const emails = [];
      const routes = registerPasswordRecovery({
        admin,
        onRequest: (_options, callback) => callback,
        sendSphotMail: async (_transport, message) => {
          emails.push(message);
          return {success: true};
        },
        mailFrom: "SPHOT <no-reply@sphot.app>",
        smtpUser: "admin@sphot.app",
        baseUrl: "https://sphot.app",
      });

      docs.set("adminAccounts/admin@example.org", {
        email: "admin@example.org",
        role: "ADMIN",
        accountStatus: "ACTIVE",
        temporaryPassword: "Old@9Password",
        mainCouranteSessionHash: "a".repeat(64),
      });
      const requested = await invoke(routes.requestSphotPasswordRecovery, {
        login: "admin@example.org", audience: "ADMIN",
      });
      assert.equal(requested.statusCode, 200);
      assert.equal(emails.length, 1);
      const token = emails[0].text.match(/token=([a-f0-9]{64})/)[1];
      assert.equal(docs.has(`passwordRecoveryTokens/${digest(token)}`), true);
      assert.equal(docs.has(`passwordRecoveryTokens/${token}`), false);

      const completed = await invoke(routes.completeSphotPasswordRecovery, {
        token, newPassword: "New@9Password",
      });
      assert.equal(completed.statusCode, 200);
      const account = docs.get("adminAccounts/admin@example.org");
      assert.equal(account.temporaryPassword, undefined);
      assert.equal(account.mainCouranteSessionHash, undefined);
      assert.equal(docs.get("institutionalMainCouranteAccess/" +
          "a".repeat(64)).enabled, false);
      assert.equal(verifyAccountPassword(account, "New@9Password"), true);
      assert.equal(verifyAccountPassword(account, "Old@9Password"), false);
      const replay = await invoke(routes.completeSphotPasswordRecovery, {
        token, newPassword: "Again@9Password",
      });
      assert.equal(replay.statusCode, 400);

      docs.set("sauveteurAccounts/super-admin", {
        email: "super@example.org",
        role: "SUPER_ADMIN",
        accountStatus: "ACTIVE",
        temporaryPassword: "Unchanged@9Password",
      });
      const excluded = await invoke(routes.requestSphotPasswordRecovery, {
        login: "super-admin", audience: "SAUVETEUR",
      });
      assert.equal(excluded.statusCode, 200);
      assert.equal(emails.length, 2); // Request and confirmation for the Admin.
      assert.equal(docs.get("sauveteurAccounts/super-admin").temporaryPassword,
          "Unchanged@9Password");
    });

test("pilot recovers only the allowlisted Sauveteur with isolated tokens",
    async () => {
      const {admin, docs} = fakeFirebase();
      const emails = [];
      let enabled = true;
      const dependencies = {
        admin,
        onRequest: (_options, callback) => callback,
        sendSphotMail: async (_transport, message) => {
          emails.push(message);
          return {success: true};
        },
        mailFrom: "SPHOT <no-reply@sphot.app>",
        smtpUser: "admin@sphot.app",
        baseUrl: "https://sphot.app",
      };
      const pilot = registerPasswordRecovery({
        ...dependencies,
        pilotConfig: () => enabled ? {
          login: "pilote-sauveteur",
          baseUrl: "https://sphot-advertiser-test--password-pilot-1.web.app",
        } : null,
      });
      const production = registerPasswordRecovery(dependencies);

      for (const login of ["pilote-sauveteur", "autre-sauveteur"]) {
        docs.set(`sauveteurAccounts/${login}`, {
          email: `${login}@example.org`,
          accountStatus: "ACTIVE",
          temporaryPassword: "Old@9Password",
        });
      }
      await invoke(pilot.requestSphotPasswordRecovery, {
        login: "autre-sauveteur", audience: "SAUVETEUR",
      });
      await invoke(pilot.requestSphotPasswordRecovery, {
        login: "pilote-sauveteur", audience: "ADMIN",
      });
      assert.equal(emails.length, 0);

      const request = await invoke(pilot.requestSphotPasswordRecovery, {
        login: "pilote-sauveteur", audience: "SAUVETEUR",
      });
      assert.equal(request.statusCode, 200);
      assert.equal(emails.length, 1);
      assert.match(emails[0].text, /sphot-advertiser-test--password-pilot/);
      const token = emails[0].text.match(/token=([a-f0-9]{64})/)[1];
      assert.equal(docs.has(`passwordRecoveryPilotTokens/${digest(token)}`),
          true);
      assert.equal(docs.has(`passwordRecoveryTokens/${digest(token)}`), false);

      const productionRejectsPilotToken = await invoke(
          production.completeSphotPasswordRecovery,
          {token, newPassword: "New@9Password"});
      assert.equal(productionRejectsPilotToken.statusCode, 400);

      enabled = false;
      const disabled = await invoke(pilot.completeSphotPasswordRecovery,
          {token, newPassword: "New@9Password"});
      assert.equal(disabled.statusCode, 400);
      enabled = true;

      const completed = await invoke(pilot.completeSphotPasswordRecovery,
          {token, newPassword: "New@9Password"});
      assert.equal(completed.statusCode, 200);
      assert.equal(verifyAccountPassword(
          docs.get("sauveteurAccounts/pilote-sauveteur"), "New@9Password"),
      true);
      assert.equal(verifyAccountPassword(
          docs.get("sauveteurAccounts/autre-sauveteur"), "Old@9Password"),
      true);
      const replay = await invoke(pilot.completeSphotPasswordRecovery,
          {token, newPassword: "Again@9Password"});
      assert.equal(replay.statusCode, 400);
    });
