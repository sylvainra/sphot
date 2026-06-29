const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

const SMTP_USER = "admin@sphot.app";
const MAIL_FROM = "\"SPHOT\" <no-reply@sphot.app>";
const SPHOT_LOGIN_URL = "https://sphot.app";


setGlobalOptions({maxInstances: 10});

exports.sendSubscriptionActivatedEmail = onDocumentUpdated(
    {
      document: "subscriptions/{subscriptionId}",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (event) => {
      const before = event.data.before.data();
      const after = event.data.after.data();

      if (before.status === "active") {
        return;
      }

      if (after.status !== "active") {
        return;
      }

      if (after.activationEmailSentAt) {
        return;
      }

      const email = after.billingContactEmail;

      if (!email) {
        console.log(
            "Email facturation absent, aucun email envoyé.",
        );
        return;
      }

      const organisation =
          after.billingOrganisation || "votre organisation";

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      await transporter.sendMail({
        from: MAIL_FROM,
        to: email,
        subject: "Activation de votre abonnement SPHOT",
        text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation} est maintenant actif.

Vous pouvez désormais utiliser les services associés
à votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
      });

      await event.data.after.ref.set(
          {
            activationEmailSentAt:
                admin.firestore.FieldValue.serverTimestamp(),
          },
          {merge: true},
      );

      console.log(
          "Email activation abonnement envoyé à:",
          email,
      );
    },
);

exports.updateSubscriptionStatuses = onSchedule(
    {
      schedule: "0 1 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = admin.firestore.Timestamp.now();

      const trialSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", "<", now)
          .get();

      const activeSnapshot = await db
          .collection("subscriptions")
          .where("status", "==", "active")
          .where("nextInvoiceDate", "<", now)
          .get();

      const batch = db.batch();

      trialSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      activeSnapshot.docs.forEach((doc) => {
        batch.set(
            doc.ref,
            {
              status: "overdue",
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );
      });

      await batch.commit();

      console.log(
          "Statuts abonnements mis à jour:",
          trialSnapshot.size + activeSnapshot.size,
      );
    },
);

exports.sendTrialEndingReminderEmails = onSchedule(
    {
      schedule: "0 9 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();
      const now = new Date();

      const start = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 3,
          0,
          0,
          0,
      );

      const end = new Date(
          now.getFullYear(),
          now.getMonth(),
          now.getDate() + 4,
          0,
          0,
          0,
      );

      const startTimestamp = admin.firestore.Timestamp.fromDate(start);
      const endTimestamp = admin.firestore.Timestamp.fromDate(end);

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "trial")
          .where("trialEndDate", ">=", startTimestamp)
          .where("trialEndDate", "<", endTimestamp)
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.trialReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: "Votre essai SPHOT arrive bientôt à échéance",
          text:
`Bonjour,

Votre période d'essai SPHOT pour ${organisation}
arrive bientôt à échéance.

Pour continuer à utiliser SPHOT sans interruption,
vous pouvez activer votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              trialReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails rappel fin essai envoyés:",
          sentCount,
      );
    },
);

exports.sendOverdueSubscriptionReminderEmails = onSchedule(
    {
      schedule: "0 10 * * *",
      timeZone: "Europe/Paris",
      region: "europe-west1",
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async () => {
      const db = admin.firestore();

      const snapshot = await db
          .collection("subscriptions")
          .where("status", "==", "overdue")
          .get();

      const transporter = nodemailer.createTransport({
        service: "gmail",
        auth: {
          user: SMTP_USER,
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      let sentCount = 0;

      for (const doc of snapshot.docs) {
        const data = doc.data();

        if (data.overdueReminderEmailSentAt) {
          continue;
        }

        const email = data.billingContactEmail;

        if (!email) {
          continue;
        }

        const organisation =
            data.billingOrganisation || "votre organisation";

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: "Votre abonnement SPHOT nécessite une régularisation",
          text:
`Bonjour,

Votre abonnement SPHOT pour ${organisation}
nécessite une régularisation.

Pour éviter toute interruption de service,
merci de régulariser votre abonnement depuis votre espace administrateur.

Cordialement,
L'équipe SPHOT`,
        });

        await doc.ref.set(
            {
              overdueReminderEmailSentAt:
                  admin.firestore.FieldValue.serverTimestamp(),
            },
            {merge: true},
        );

        sentCount += 1;
      }

      console.log(
          "Emails relance abonnements en retard envoyés:",
          sentCount,
      );
    },
);

exports.testEmailSphot = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      try {
        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: MAIL_FROM,
          to: "rabreau.sylvain@gmail.com",
          subject: "Test email SPHOT",
          text: "Test email Firebase Functions SPHOT.",
        });

        response.status(200).send("Email SPHOT envoyé avec succès.");
      } catch (error) {
        console.error("Erreur envoi email SPHOT:", error);
        response.status(500).send("Erreur lors de l'envoi email SPHOT.");
      }
    },
);

exports.sendSauveteurCredentialsEmail = onRequest(
    {
      secrets: ["GMAIL_APP_PASSWORD"],
      cpu: 1,
      memory: "256MiB",
    },
    async (request, response) => {
      try {
        const email = request.query.email;
        const prenom = request.query.prenom || "Sauveteur";
        const identifiant = request.query.identifiant || "";
        const motDePasse = request.query.motdepasse || "";

        if (!email) {
          response.status(400).send("Email manquant.");
          return;
        }

        const transporter = nodemailer.createTransport({
          service: "gmail",
          auth: {
            user: SMTP_USER,
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: MAIL_FROM,
          to: email,
          subject: "Vos accès SPHOT",
          html: `
<div style="margin:0;padding:40px 20px;
background:#eef3f8 url('https://sphot.app/assets/data/images/map_background.jpg')
center center / cover no-repeat;
font-family:Arial,Helvetica,sans-serif;">

    <div style="max-width:620px;margin:auto;
background:rgba(255,255,255,0.94);
border-radius:18px;overflow:hidden;border:1px solid #d9e2ec;
box-shadow:0 4px 12px rgba(0,0,0,.08);">

    <div style="padding:30px 30px 20px 30px;text-align:center;">

      <a href="${SPHOT_LOGIN_URL}">
        <img
          src="https://sphot.app/assets/data/icons/title.png"
          alt="SPHOT"
          style="max-width:320px;width:100%;height:auto;border:0;">
      </a>
      
    </div>

    <div style="padding:0 34px 30px 34px;color:#263238;
font-size:16px;line-height:1.6;">

      <p>Bonjour <strong>${prenom}</strong>,</p>

<p>
  Bienvenue sur SPHOT.
</p>

<p>
  Votre compte a été créé par votre administrateur SPHOT.
</p>

<p>
  Vous trouverez ci-dessous votre identifiant et mot de passe
  pour vous connecter sur SPHOT.
</p>

      <div style="
          margin:28px 0;
          background:#f7f9fc;
          border:1px solid #d9e2ec;
          border-radius:14px;
          padding:22px;">

        <div style="margin-bottom:18px;">
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Identifiant
          </div>

          <div style="font-size:22px;font-weight:bold;color:#1e3a8a;">
            ${identifiant}
          </div>
        </div>

        <div>
          <div style="font-size:13px;color:#607d8b;text-transform:uppercase;">
            Mot de passe temporaire
          </div>

          <div style="font-size:22px;font-weight:bold;color:#d91c1c;">
            ${motDePasse}
          </div>
        </div>

      </div>

      <div style="
          background:#fff8e1;
          border-left:5px solid #ff9800;
          padding:16px;
          border-radius:8px;
          margin-bottom:28px;">

        <strong>Important</strong><br>

        Lors de votre première connexion,
        vous devrez modifier votre mot de passe.

      </div>

      <div style="text-align:center;margin:35px 0;">

        <a
          href="${SPHOT_LOGIN_URL}"
          style="
            background:#d91c1c;
            color:#ffffff;
            text-decoration:none;
            padding:16px 30px;
            border-radius:10px;
            display:inline-block;
            font-size:17px;
            font-weight:bold;">

          SE CONNECTER À SPHOT

        </a>

      </div>

      <p style="margin-top:40px;">
        À bientôt sur SPHOT,<br>
        <strong>L'équipe SPHOT</strong>
      </p>

    </div>

  </div>

</div>
`,
          text:
`Bonjour ${prenom},

Votre compte a été créé par votre administrateur SPHOT.

Identifiant : ${identifiant}
Mot de passe temporaire : ${motDePasse}

Lors de votre première connexion, vous devrez modifier votre mot de passe.

Se connecter à SPHOT :
${SPHOT_LOGIN_URL}

À bientôt sur SPHOT,
L'équipe SPHOT`,
        });

        response.status(200).send("Email d'identifiants envoyé.");
      } catch (error) {
        console.error(
            "Erreur envoi email identifiants SPHOT:",
            error,
        );
        response.status(500).send("Erreur lors de l'envoi.");
      }
    },
);
