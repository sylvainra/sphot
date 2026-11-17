"""SPHOT ADMIN Odoo 20: multitranches, facture unique, preuve Stripe.

Module distinct du checkout PUBLICITAIRE installé sur Windows.
Pas de contrôleur public, d'encaissement, de validation administrative ou
d'écriture Firestore ici. Les méthodes RPC sont réservées au compte technique
du groupe déjà existant « SPHOT - Passerelle commandes et factures ».
"""

import re
from decimal import Decimal, ROUND_HALF_UP

from psycopg2 import IntegrityError

from odoo import _, api, models
from odoo.exceptions import AccessError, UserError


ORDER_CONTRACT = "sphot_admin_atomic_order_v1"
INVOICE_CONTRACT = "sphot_admin_atomic_invoice_v1"
STRIPE_CONTRACT = "sphot_admin_stripe_evidence_v1"
REFERENCE_RE = re.compile(r"^SPHOT-ADM-TEST-[A-F0-9]{16}$")
FINGERPRINT_RE = re.compile(r"^[a-f0-9]{64}$")
LINE_RE = re.compile(r"^SPHOT ADMIN / Tranche ([1-4]) / Tarif (FR_ADMIN-V\d+)$")


def _cents(amount):
    return int(Decimal(str(amount)).quantize(
        Decimal("0.01"), rounding=ROUND_HALF_UP) * 100)


def _positive_int(value):
    return type(value) is int and value > 0


def _assert_reference(reference, fingerprint):
    if not (isinstance(reference, str) and REFERENCE_RE.fullmatch(reference)
            and isinstance(fingerprint, str)
            and FINGERPRINT_RE.fullmatch(fingerprint)):
        raise UserError(_("Référence ou empreinte ADMIN invalide."))


class SphotAdminCheckout(models.Model):
    _name = "sphot.admin.checkout"
    _description = "Passerelle technique SPHOT ADMIN - commandes et factures"

    @api.model
    def _require_gateway(self):
        if not self.env.user.has_group(
                "sphot_advertiser_checkout.group_sphot_checkout_gateway"):
            raise AccessError(_("Accès à la passerelle ADMIN refusé."))

    @api.model
    def _validate_order_values(self, reference, order_values):
        if not (isinstance(order_values, dict) and set(order_values) == {
                "partner_id", "client_order_ref", "origin", "order_line"}):
            raise UserError(_("Champs de commande ADMIN inattendus."))
        if not (order_values["client_order_ref"] == reference and
                isinstance(order_values["origin"], str) and
                re.fullmatch(r"SPHOT FR_ADMIN-V\d+", order_values["origin"])):
            raise UserError(_("Origine ADMIN invalide."))
        if not _positive_int(order_values["partner_id"]):
            raise UserError(_("Client Odoo ADMIN non configuré."))

        partner = self.env["res.partner"].browse(
            order_values["partner_id"]).exists()
        if not (partner and partner.is_company and partner.active and
                partner.country_id and partner.street and partner.zip and
                partner.city):
            raise UserError(_("Partenaire de facturation ADMIN incomplet."))

        commands = order_values["order_line"]
        if not isinstance(commands, list) or not 1 <= len(commands) <= 4:
            raise UserError(_("Une à quatre tranches ADMIN sont requises."))

        product_ids = set()
        tiers = []
        discounts = set()
        for command in commands:
            if not (isinstance(command, (list, tuple)) and len(command) == 3
                    and command[0] == 0 and command[1] == 0
                    and isinstance(command[2], dict)):
                raise UserError(_("Commande de tranche ADMIN invalide."))
            line = command[2]
            if set(line) != {"product_id", "product_uom_qty", "price_unit",
                             "discount", "name"}:
                raise UserError(_("Champs de tranche ADMIN inattendus."))
            match = (LINE_RE.fullmatch(line["name"])
                     if isinstance(line["name"], str) else None)
            if not (match and
                    order_values["origin"] == "SPHOT " + match.group(2) and
                    _positive_int(line["product_id"]) and
                    _positive_int(line["product_uom_qty"]) and
                    line["product_uom_qty"] <= 10000 and
                    type(line["price_unit"]) is int and
                    line["price_unit"] > 0 and
                    type(line["discount"]) is int and
                    0 <= line["discount"] <= 90):
                raise UserError(_("Tarif ou quantité de tranche ADMIN invalide."))
            product_id = line["product_id"]
            tier = int(match.group(1))
            if product_id in product_ids or tier in tiers:
                raise UserError(_("Tranche ou produit ADMIN en doublon."))
            product_ids.add(product_id)
            tiers.append(tier)
            discounts.add(line["discount"])

            product = self.env["product.product"].browse(product_id).exists()
            if not (product and product.active and product.type == "service"
                    and product.invoice_policy == "order"):
                raise UserError(_("Produit ADMIN : service facturable à la commande requis."))
        if tiers != sorted(tiers) or len(discounts) != 1:
            raise UserError(_("Tranches ADMIN non ordonnées ou remise variable."))

    @api.model
    def _assert_order(self, order, reference, fingerprint, order_values,
                      expected_untaxed_cents, expected_total_cents):
        incoming = [command[2] for command in order_values["order_line"]]
        actual = order.order_line.filtered(lambda line: line.product_id)
        if not (order.x_sphot_reference == reference and
                order.x_sphot_fingerprint == fingerprint and
                order.client_order_ref == reference and
                order.state in ("draft", "sent", "sale") and
                order.partner_id.id == order_values["partner_id"] and
                order.currency_id.name == "EUR" and
                len(order.order_line) == len(incoming) and
                len(actual) == len(incoming) and
                _cents(order.amount_untaxed) == expected_untaxed_cents and
                _cents(order.amount_total) == expected_total_cents and
                _cents(order.amount_tax) ==
                expected_total_cents - expected_untaxed_cents):
            raise UserError(_("Commande ADMIN différente des conditions figées."))
        for line, item in zip(actual, incoming):
            if not (line.product_id.id == item["product_id"] and
                    line.product_uom_qty == item["product_uom_qty"] and
                    _cents(line.price_unit) == _cents(item["price_unit"]) and
                    line.discount == item["discount"]):
                raise UserError(_("Ligne ADMIN différente du devis serveur."))

    @api.model
    def _order_dict(self, order):
        return order.read([
            "id", "name", "state", "client_order_ref", "partner_id",
            "currency_id", "amount_untaxed", "amount_tax", "amount_total",
            "order_line", "invoice_ids", "x_sphot_reference",
            "x_sphot_fingerprint",
        ])[0]

    @api.model
    def _invoice_dict(self, invoice):
        return invoice.read([
            "id", "name", "invoice_origin", "partner_id", "currency_id",
            "move_type", "state", "payment_state", "amount_untaxed",
            "amount_tax", "amount_total", "amount_residual",
            "matched_payment_ids", "x_sphot_reference",
            "x_sphot_fingerprint", "x_sphot_sale_order_id",
        ])[0]

    @api.model
    def create_or_get_draft_order(self, sphot_reference, sphot_fingerprint,
                                  expected_untaxed_cents,
                                  expected_total_cents, order_values):
        """Create or retrieve exactly one Odoo order with a unique SPHOT ref."""
        self._require_gateway()
        _assert_reference(sphot_reference, sphot_fingerprint)
        if not (_positive_int(expected_untaxed_cents) and
                _positive_int(expected_total_cents) and
                expected_total_cents >= expected_untaxed_cents):
            raise UserError(_("Montants ADMIN invalides."))
        self._validate_order_values(sphot_reference, order_values)

        orders = self.env["sale.order"]
        existing = orders.search([
            ("x_sphot_reference", "=", sphot_reference)], limit=2)
        if existing:
            if len(existing) != 1:
                raise UserError(_("Référence ADMIN dupliquée dans Odoo."))
            self._assert_order(existing, sphot_reference, sphot_fingerprint,
                               order_values, expected_untaxed_cents,
                               expected_total_cents)
            return self._order_result(existing, "existing", sphot_reference,
                                      sphot_fingerprint)

        try:
            with self.env.cr.savepoint():
                order = orders.create({
                    **order_values,
                    "x_sphot_reference": sphot_reference,
                    "x_sphot_fingerprint": sphot_fingerprint,
                })
                order.flush_recordset()
        except IntegrityError:
            self.env.invalidate_all()
            existing = orders.search([
                ("x_sphot_reference", "=", sphot_reference)], limit=2)
            if len(existing) != 1:
                raise
            self._assert_order(existing, sphot_reference, sphot_fingerprint,
                               order_values, expected_untaxed_cents,
                               expected_total_cents)
            return self._order_result(existing, "existing", sphot_reference,
                                      sphot_fingerprint)

        self._assert_order(order, sphot_reference, sphot_fingerprint,
                           order_values, expected_untaxed_cents,
                           expected_total_cents)
        return self._order_result(order, "created", sphot_reference,
                                  sphot_fingerprint)

    @api.model
    def _order_result(self, order, outcome, reference, fingerprint):
        return {"contract": ORDER_CONTRACT, "outcome": outcome,
                "reference": reference, "fingerprint": fingerprint,
                "order": self._order_dict(order)}

    @api.model
    def _assert_invoice(self, order, invoice, reference, fingerprint,
                        expected_total_cents):
        if not (len(order.invoice_ids) == 1 and
                invoice in order.invoice_ids and
                invoice.x_sphot_reference == reference and
                invoice.x_sphot_fingerprint == fingerprint and
                invoice.x_sphot_sale_order_id == order and
                invoice.invoice_origin == order.name and
                invoice.partner_id == order.partner_id and
                invoice.company_id == order.company_id and
                invoice.currency_id.name == "EUR" and
                invoice.move_type == "out_invoice" and
                invoice.state == "posted" and
                invoice.payment_state in ("not_paid", "in_payment", "partial", "paid") and
                _cents(invoice.amount_untaxed) == _cents(order.amount_untaxed) and
                _cents(invoice.amount_tax) == _cents(order.amount_tax) and
                _cents(invoice.amount_total) == expected_total_cents and
                0 <= _cents(invoice.amount_residual) <= expected_total_cents):
            raise UserError(_("Facture ADMIN absente, dupliquée ou altérée."))
        if (invoice.payment_state == "paid" and
                _cents(invoice.amount_residual) != 0):
            raise UserError(_("Facture ADMIN non rapprochée."))

    @api.model
    def _invoice_result(self, order, invoice, outcome, reference, fingerprint):
        return {"contract": INVOICE_CONTRACT, "outcome": outcome,
                "reference": reference, "fingerprint": fingerprint,
                "order": self._order_dict(order),
                "invoice": self._invoice_dict(invoice)}

    @api.model
    def confirm_and_post_one_invoice(self, sphot_reference,
                                     sphot_fingerprint, sale_order_id,
                                     expected_total_cents):
        """One serialised confirmation and invoice, no payment creation."""
        self._require_gateway()
        _assert_reference(sphot_reference, sphot_fingerprint)
        if not (_positive_int(sale_order_id) and
                _positive_int(expected_total_cents)):
            raise UserError(_("Commande ou total ADMIN invalide."))

        self.env["sale.order"].flush_model(["x_sphot_reference"])
        self.env.cr.execute(
            "SELECT id FROM sale_order WHERE id = %s FOR UPDATE",
            (sale_order_id,),
        )
        if not self.env.cr.fetchone():
            raise UserError(_("Commande ADMIN Odoo absente."))
        order = self.env["sale.order"].browse(sale_order_id)
        order.invalidate_recordset()
        if not (order.x_sphot_reference == sphot_reference and
                order.x_sphot_fingerprint == sphot_fingerprint and
                order.client_order_ref == sphot_reference and
                order.currency_id.name == "EUR" and
                order.state in ("draft", "sent", "sale") and
                _cents(order.amount_total) == expected_total_cents and
                1 <= len(order.order_line) <= 4 and
                len(order.order_line.filtered(lambda line: line.product_id)) ==
                len(order.order_line)):
            raise UserError(_("Commande ADMIN modifiée avant facturation."))

        invoices = order.invoice_ids
        if invoices:
            if len(invoices) != 1:
                raise UserError(_("Plusieurs factures sur commande ADMIN."))
            self._assert_invoice(order, invoices, sphot_reference,
                                 sphot_fingerprint, expected_total_cents)
            return self._invoice_result(order, invoices, "existing",
                                        sphot_reference, sphot_fingerprint)

        if order.state in ("draft", "sent"):
            order.action_confirm()
            if order.invoice_ids:
                raise UserError(_("Facturation automatique externe détectée."))
        created = order._create_invoices()
        if len(created) != 1:
            raise UserError(_("Odoo ne peut créer la facture ADMIN unique."))
        created.write({
            "x_sphot_reference": sphot_reference,
            "x_sphot_fingerprint": sphot_fingerprint,
            "x_sphot_sale_order_id": order.id,
        })
        created.action_post()
        order.invalidate_recordset()
        self._assert_invoice(order, created, sphot_reference,
                             sphot_fingerprint, expected_total_cents)
        if (created.payment_state != "not_paid" or
                _cents(created.amount_residual) != expected_total_cents):
            raise UserError(_("Nouvelle facture ADMIN déjà réglée."))
        return self._invoice_result(order, created, "created",
                                    sphot_reference, sphot_fingerprint)

    @api.model
    def read_stripe_checkout_evidence(self, sphot_reference,
                                      sphot_fingerprint, invoice_id):
        """Read strictly invoice-scoped payment data after validating ownership."""
        self._require_gateway()
        _assert_reference(sphot_reference, sphot_fingerprint)
        if not _positive_int(invoice_id):
            raise UserError(_("Facture ADMIN invalide."))

        orders = self.env["sale.order"].search([
            ("x_sphot_reference", "=", sphot_reference)], limit=2)
        if len(orders) != 1:
            raise UserError(_("Commande ADMIN introuvable ou dupliquée."))
        order = orders
        invoices = order.invoice_ids
        if len(invoices) != 1 or invoices.id != invoice_id:
            raise UserError(_("Facture ADMIN non liée à la commande."))
        invoice = invoices
        if not (order.state == "sale" and
                order.x_sphot_fingerprint == sphot_fingerprint and
                order.client_order_ref == sphot_reference and
                invoice.x_sphot_reference == sphot_reference and
                invoice.x_sphot_fingerprint == sphot_fingerprint and
                invoice.x_sphot_sale_order_id == order and
                invoice.invoice_origin == order.name and
                invoice.partner_id == order.partner_id and
                invoice.company_id == order.company_id and
                invoice.currency_id == order.currency_id and
                invoice.move_type == "out_invoice" and
                invoice.state == "posted"):
            raise UserError(_("Lien commande/facture ADMIN incohérent."))

        providers = self.env["payment.provider"].sudo()
        company_id = invoice.company_id.id
        stripe = providers.search([
            ("code", "=", "stripe"), ("is_live", "=", False),
            ("company_id", "=", company_id),
        ], limit=2)
        demo = providers.search([
            ("code", "=", "demo"), ("company_id", "=", company_id),
        ], limit=2)
        transactions = self.env["payment.transaction"].sudo().search([
            ("invoice_ids", "in", [invoice_id]),
        ], order="id desc", limit=20)
        if len(transactions) == 20:
            raise UserError(_("Historique Stripe ADMIN ambigu."))

        return {
            "contract": STRIPE_CONTRACT,
            "reference": sphot_reference,
            "fingerprint": sphot_fingerprint,
            "invoice_id": invoice_id,
            "stripe_providers": [{
                "id": provider.id, "code": provider.code,
                "is_live": provider.is_live,
                "is_published": provider.is_published,
            } for provider in stripe],
            "demo_providers": [{
                "id": provider.id, "code": provider.code,
                "is_published": provider.is_published,
            } for provider in demo],
            "transactions": [{
                "id": transaction.id,
                "reference": transaction.reference,
                "state": transaction.state,
                "provider_code": transaction.provider_code,
                "provider_id": transaction.provider_id.id,
                "amount": transaction.amount,
                "currency_id": transaction.currency_id.id,
                "invoice_ids": transaction.invoice_ids.ids,
            } for transaction in transactions],
        }
