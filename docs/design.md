# shippingrules: research and proposed design

Status: proposal, nothing beyond the installable module shell is implemented. Open questions are at the end; the design is not final until they are answered.

## 1. What PrestaShop 9.1 already does (reuse, don't rebuild)

Verified in the 9.1.5 source of the dev store (`classes/Cart.php`, `classes/Carrier.php`) unless marked otherwise.

| Native feature | Where | Use it for |
|---|---|---|
| Zones, countries, states | Shipping › Zones/Countries | Destination grouping. Rates key on `id_zone`; no own zone model. |
| Carriers with weight or price ranges per zone, out-of-range behaviour, tax rules group, handling fee, free flag | `Carrier`, `range_weight`, `range_price`, `delivery` | Simple rates stay native. Our module only covers what ranges can't express. |
| Carrier max width/height/depth/weight | `Carrier::getAvailableCarrierList()` drops a carrier for a product that exceeds them (weight × quantity and cart weight too) | Hard size limits per carrier (e.g. parcel couriers can't take a 9' board). |
| Product ↔ carrier restriction | product Shipping tab, `product_carrier` (by `id_reference`) | Manual per-product carrier lists. |
| Per-product `additional_shipping_cost` | added × quantity in `getPackageShippingCostValue()` | Stays as-is; our module receives the cost including it. |
| Free shipping by order total / weight | `PS_SHIPPING_FREE_PRICE`, `PS_SHIPPING_FREE_WEIGHT`, cart rules with free shipping | Global thresholds. Note: when the threshold applies the cost is 0 **but a carrier module is still asked** (`Cart.php` ~3924), so a module can exclude bulky goods from free shipping. |
| Packages | `Cart::getPackageList()` groups products by the intersection of their allowed carriers | If no single carrier can take everything, legacy PrestaShop splits the order into one order per carrier. 9.1 has an experimental **Improved shipment** feature flag (`improved_shipment`) that keeps one order with several shipments ([announcement](https://build.prestashop-project.org/news/2026/introducing-shipments/)). Not production-ready; design must work with the flag off. |

Extension points:

- **Carrier module** (`extends CarrierModule`, [docs](https://devdocs.prestashop-project.org/9/modules/carrier/)). For carriers with `shipping_external=1` and `external_module_name=<us>`, core calls `getPackageShippingCost($cart, $shippingCost, $products)` per package (falls back to `getOrderShippingCost`). With `need_range=1` the incoming `$shippingCost` already contains the native range price + handling + additional costs, so native ranges can be a fallback. Returning `false` removes the carrier (`Carrier::getCarriersForOrder()` unsets carriers with price `false`). The return is pre-tax; core applies the carrier's tax rule afterwards. Called twice per carrier per package (with and without tax) → memoise per request.
- **`actionCartGetPackageShippingCost`** (by-reference `shippingCost`, runs after *every* carrier's price, including other modules' API prices). The hook for adjusting third-party carriers without replacing them.
- **`actionFilterDeliveryOptionList`** (by-reference option list): hide or relabel options.
- `actionDeliveryPriceByWeight` / `actionDeliveryPriceByPrice`: override the native range lookup; `actionOverrideShippingFreePrice` / `actionOverrideShippingFreeWeight`: per-zone free thresholds.
- Carrier ids change on every BO edit; always key on `id_reference` and listen to `actionCarrierUpdate`.

## 2. How the industry models it

- **WooCommerce shipping classes + Table Rate Shipping** ([docs](https://woocommerce.com/document/table-rate-shipping/)): products get a *shipping class*; per zone, rate rows match on weight / item count / price / class and compute per order, per item, per line or per class, with base cost + per-item + per-kg + %, min/max, row priority and "abort/break" rows.
- **Shopify shipping profiles**: products are grouped into profiles; each profile has its own zones and rates (flat, weight- or price-conditional, or carrier-calculated). A cart with several profiles pays the sum of each profile's rate.
- **Magento table rates**: one CSV table, condition = weight *or* subtotal *or* item count vs destination; import/export as CSV.
- **Carrier-calculated (API) rates** (Packlink, Sendcloud, national DPD/GLS/Pošta modules): price comes from parcel weight and dimensions. The shop's job is correct product weight/dimensions; the module's job is not to fight them.
- **Courier limits** (why boards and sails are special): DPD Classic max 31.5 kg, length 175 cm, length + 2·width + 2·height ≤ 300 cm ([DPD](https://www.dpd.com/dpd-lu/wp-content/uploads/sites/243/2020/06/DPD-Classic-infofiche_MKT_EN_052020.pdf)); GLS max 200 × 80 × 60 cm ([GLS](http://gls-czech.eu/AT/en/faq/sending-parcels)). Surfboards (6'–9' ≈ 183–275 cm) and rolled sails exceed parcel limits → freight, a bulky service, or pickup. Volumetric weight is L·W·H / divisor; the divisor (4000/5000/6000) differs per carrier, so it is configuration, not code.

## 3. Recommendation: shipping classes, category is one way to assign them

Pure per-category shipping is fragile: products sit in several categories, a fin or leash in "Surf" is not a board, and a category reorganisation (which we just did on live) silently changes shipping prices. The standard model is a **shipping class per product**; category is the most convenient way to assign it.

**Class resolution** (first match wins, each step optional, order configurable):
1. Product override (explicit class on the product).
2. Category rule: class mapped to a category, inherited by subcategories; for products in several categories the default category wins, else the highest-priority class.
3. Measure rule: e.g. longest side > 175 cm or weight > 31.5 kg → "Bulky" (catches products with no mapping).
4. Default class.

The BO shows *why* a product got its class (which rule), and lists products with missing weight/dimensions.

**Class settings** (all data, presets offered as one-click helpers, never hardcoded):
- Allowed carriers (by `id_reference`) and/or required carrier size limits.
- Packing: items per package (2 boards per board bag/box → `ceil(qty / 2)` packages), optional package tare and dimensions.
- Consolidation: "rides along with class X" (a wetsuit in the same order as a board ships in the board box at no extra cost), else its own package.
- Free-shipping eligibility (exclude bulky from the global threshold), handling fee.

**Rate tables** (Woo/Magento style) per carrier reference × zone × class, rows with:
- basis: weight, volumetric/chargeable weight, quantity, package count, or subtotal; `from`/`to` range;
- price: base + per unit beyond the start (per kg / item / package) + %; min/max;
- "first package X, each additional Y" is base + per-package.
- CSV import/export for bulk editing.

**Combining classes in one cart** (setting): sum per class (Shopify), highest class + additional items of others (Woo "most expensive class"), or highest only. Consolidation rules apply first.

**Carrier modes**:
- *Own carriers*: module-owned carriers (`CarrierModule`, `need_range=1`) priced by the tables; native ranges remain the fallback.
- *Adjust third-party carriers* (API modules) via `actionCartGetPackageShippingCost`: per class surcharge or markup, rounding, block a class (return `false`), optional fallback table price when the API returns no price. Never replaces an API price unless configured to.

**Resilience**:
- Pricing is a pure function in `src/` (input snapshot: products with class, weight, dims, qty; zone; carrier reference; config) with unit tests; PrestaShop adapters stay thin.
- Any exception → log once per cart + configured failure behaviour (native range price or hide carrier); checkout never fatals.
- Per-request memo (core asks twice per carrier per package).
- Config export/import as JSON for staging → live.

## 4. Open questions for the user

1. Which carriers/shipping modules run on live (Pošta Slovenije, GLS, DPD, Packlink, Sendcloud, own delivery, pickup)? Which destinations (SI only, EU)?
2. How are boards and sails shipped today, and at what cost (examples: 1 board to SI, 2 boards, board + wetsuit, 1 sail)?
3. Mixed carts: one shipment where small items ride in the board box, or separate packages?
4. Is splitting an order across carriers acceptable, or must one carrier take the whole cart (only carriers allowed for every class in the cart)?
5. Live PrestaShop exact version, and whether the Improved shipment flag is on.
6. Module name: `shippingrules` is a working name; rename is cheap before the first release.
