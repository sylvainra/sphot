"use strict";

const {test} = require("node:test");
const assert = require("node:assert/strict");
const nodemailer = require("nodemailer");
const {sendSphotMail} = require("../sphot_email_design");

test("Nodemailer transmet le modèle SPHOT et les images", async () => {
  // Le transport JSON vérifie la construction du mail sans en expédier un.
  const transporter = nodemailer.createTransport({jsonTransport: true});
  const info = await sendSphotMail(transporter, {
    from: "\"SPHOT\" <no-reply@sphot.app>",
    to: "test@example.invalid",
    subject: "Vérification interne SPHOT",
    text: "Contrôle de compatibilité du transport e-mail.",
  });
  const message = JSON.parse(info.message);

  assert.equal(message.subject, "Vérification interne SPHOT");
  assert.equal(message.to[0].address, "test@example.invalid");
  assert.match(message.html, /SPHOT/);
  assert.equal(message.attachments.length, 2);
  assert.ok(message.attachments.some(
      (attachment) => attachment.filename === "sphot_title.png"));
  assert.ok(message.attachments.some(
      (attachment) => attachment.filename === "fire_red_icon.png"));
});
