"use strict";
/* eslint-disable require-jsdoc */

const assert = require("node:assert/strict");
const test = require("node:test");
const {checkLoginRateLimit} = require("../login_protection");

test("login rate limit blocks repeated guesses and resets on success",
    async () => {
      const data = new Map();
      class Timestamp {
        constructor(ms) {
          this.value = ms;
        }
        toMillis() {
          return this.value;
        }
        static fromMillis(ms) {
          return new Timestamp(ms);
        }
      }
      const db = {
        collection: (_name) => ({
          doc: (key) => ({
            get: async () => ({
              data: () => data.get(key),
            }),
            set: async (value) => data.set(key, value),
            delete: async () => data.delete(key),
          }),
        }),
        runTransaction: (fn) => fn({
          get: (ref) => ref.get(),
          set: (ref, value) => ref.set(value),
        }),
      };
      const admin = {
        firestore: Object.assign(() => db, {Timestamp}),
      };
      const request = {ip: "203.0.113.5"};
      for (let attempt = 0; attempt < 8; attempt++) {
        const result = await checkLoginRateLimit(
            admin, request, "ADMIN", "user@example.org");
        assert.equal(result.allowed, true);
      }
      const locked = await checkLoginRateLimit(
          admin, request, "ADMIN", "user@example.org");
      assert.equal(locked.allowed, false);
      const otherIp = await checkLoginRateLimit(
          admin, {ip: "203.0.113.6"}, "ADMIN", "user@example.org");
      assert.equal(otherIp.allowed, true);
      await otherIp.clear();
      const retry = await checkLoginRateLimit(
          admin, {ip: "203.0.113.6"}, "ADMIN", "user@example.org");
      assert.equal(retry.allowed, true);
    });
