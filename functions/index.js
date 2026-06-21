const {setGlobalOptions} = require("firebase-functions");
const {onRequest} = require("firebase-functions/v2/https");
const {onSchedule} = require("firebase-functions/v2/scheduler");
const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");
const nodemailer = require("nodemailer");

admin.initializeApp();

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
          user: "rabreau.sylvain@gmail.com",
          pass: process.env.GMAIL_APP_PASSWORD,
        },
      });

      await transporter.sendMail({
        from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
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
          user: "rabreau.sylvain@gmail.com",
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
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
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
          user: "rabreau.sylvain@gmail.com",
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
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
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
            user: "rabreau.sylvain@gmail.com",
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
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
            user: "rabreau.sylvain@gmail.com",
            pass: process.env.GMAIL_APP_PASSWORD,
          },
        });

        await transporter.sendMail({
          from: "\"SPHOT\" <rabreau.sylvain@gmail.com>",
          to: email,
          subject: "Vos accès SPHOT",
          text:
`Bonjour ${prenom},

Votre compte SPHOT a été créé.

Identifiant : ${identifiant}
Mot de passe provisoire : ${motDePasse}

Nous vous recommandons de modifier votre mot de passe
dès votre première connexion.

Cordialement,
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
