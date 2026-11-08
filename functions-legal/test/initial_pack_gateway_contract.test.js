"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const {register} = require("../legal_pack_gateway");
const fakeResponse=()=>{const r={statusCode:200,body:null};r.set=()=>r;r.status=(s)=>{r.statusCode=s;return r;};r.json=(b)=>{r.body=b;return r;};return r;};
const token={role:"SPHOT_SUPER_ADMIN",sphotSuperAdmin:true,
  uid:"sphot-super-admin-"+"a".repeat(32),sphotSaSessionExpiresAt:Date.now()+600000};
const admin={auth:()=>({verifyIdToken:async()=>token}), firestore:()=>{throw new Error("No Firestore reads expected")}};
const onRequest=(_,h)=>h;
test("Initial pack: request without auth is denied",async()=>{
  const handler=register({admin,onRequest});const r=fakeResponse();
  await handler({method:"POST",get:()=>"",body:{action:"status"}},r);
  assert.equal(r.statusCode,401);
});
test("Initial pack: validation locked before any database read",async()=>{
  const handler=register({admin,onRequest});const r=fakeResponse();
  await handler({method:"POST",get:()=>"Bearer testing",body:{action:"validate"}},r);
  assert.equal(r.statusCode,403);assert.equal(r.body.error,"VALIDATION_INITIALE_NON_ACTIVEE");
});
test("Initial pack: publication locked before any database read",async()=>{
  const handler=register({admin,onRequest});const r=fakeResponse();
  await handler({method:"POST",get:()=>"Bearer testing",body:{action:"publish",confirm:true,expectedPackHash:"a".repeat(64),expectedVersion:"1.0"}},r);
  assert.equal(r.statusCode,403);assert.equal(r.body.error,"PUBLICATION_INITIALE_NON_ACTIVEE");
});
