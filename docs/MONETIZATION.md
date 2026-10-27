# Monetization: Phase 1 (secure foundation)

_2026-10-27. Status: **closed store**. `MonetizationConfig.Enabled = false`, every Id = 0, nothing can be bought for real. Studio test mode is on (Studio only)._

## 1. Audit (before this phase)
| Item | Finding |
|---|---|
| MarketplaceService usage | **None.** No ProcessReceipt, no game-pass checks, no prompts, so there were no conflicting handlers |
| `MonetizationConfig` | Unused plan (Enabled false, Ids 0). Now rewritten as the central catalog |
| Player data | `ProcessedReceipts` field reserved but never written |
| DataStore saves | Two saves for one player could overlap. **Fixed:** saves are serialised per profile; added `SaveNow` and `IsActive` |
| Economy | All cash goes through `ProgressionService.AddCash` (single gateway). Purchased cash is now tracked separately (`Stats.CashPurchased`) |

## 2. Architecture
```
client                         server
──────                         ──────
store UI / test panel ──RequestPurchase(kind,key)──▶ MonetizationService
                                 │ validates key against MonetizationConfig (rate-limited 2/s)
                                 ├─ Live:  MarketplaceService:Prompt…Purchase   (Roblox UI)
                                 └─ Test:  simulated receipt (Studio only)
Roblox ──ProcessReceipt(receipt)──────────▶ ReceiptProcessor (real ledger)
                                 grant + record PurchaseId in ONE profile write
                                 → DataService.SaveNow → "Granted" only if saved
Roblox ──PromptGamePassPurchaseFinished──▶ ownership + UserOwnsGamePassAsync re-check
join ──UserOwnsGamePassAsync──────────────▶ Player attribute Pass_<Key>, OwnsPass(), PassChanged
```
| File | Role |
|---|---|
| `src/shared/Config/MonetizationConfig.luau` | **The only product catalog**: keys, Ids, display prices, grants, VIP benefits, ledger limits, `validate()` |
| `src/server/Monetization/ReceiptProcessor.luau` | Pure, dependency-injected receipt logic (unit-tested) |
| `src/server/Services/MonetizationService.luau` | Roblox integration: the single ProcessReceipt, passes, prompts, test mode |
| `src/server/Services/DataService.luau` | `SaveNow`, `IsActive`, serialised saves, ledgers `ProcessedReceipts` / `TestReceipts` / `PurchaseHistory` |
| `src/client/UI/Screens/DevStorePanel.luau` | Studio-only test buttons |
| `tests/ReceiptProcessor.spec.luau` | 17 unit tests, run by `scripts/check.sh` (Lune) |

## 3. Guarantees (each covered by a unit test)
1. **Never granted twice.** The PurchaseId is recorded in the same profile table, in the same non-yielding step as the reward, so they are always saved together. A duplicate delivery, even after a rejoin on another server, is acknowledged without regranting.
2. **Never acknowledged before it's safe.** `PurchaseGranted` is returned only after `SaveNow` succeeds. If the DataStore fails, the receipt stays pending, and Roblox's retry only re-attempts the save.
3. **Never lost.** Unknown product Ids, absent players, unloaded profiles and players leaving mid-purchase all return `NotProcessedYet`, so Roblox re-delivers later.
4. **No double grant under concurrency.** Two deliveries of one receipt at the same time: one grants, the other waits for the retry.
5. **The client is never trusted.** The client can only *ask* for a prompt. Rewards come only from Roblox's server-side receipt; game passes come from `UserOwnsGamePassAsync` or Roblox's server-side purchase-finished event.
6. **Test and real never mix.** Simulated purchases exist only in Studio, use ids prefixed `TEST-`, go into `TestReceipts` (not `ProcessedReceipts`), are flagged `Test = true` in history, and are written to the Studio-only DataStore (`…_Studio`).

## 4. Studio test mode
The Studio test mode is active when running in Studio **and** `MonetizationConfig.TestMode = true`. Live servers ignore the flag (`RunService:IsStudio()` check). In test mode:
- a gold **🧪 TEST STORE** button appears bottom-left. It lists every product and pass from the catalog.
- product buttons run a simulated receipt through the real `ReceiptProcessor`.
- the pass button simulates ownership via a Workspace attribute (never stored in player data).

Scenario switches, set on **Workspace** in the **Server** view (Test tab → Current: Server):

| Attribute | Type | Effect |
|---|---|---|
| `StoreTest_Decline` | bool | the "player" cancels: nothing granted |
| `StoreTest_FailSave` | bool | every DataStore save in the pipeline fails; the receipt stays pending and is retried every 5 s (4 tries) |
| `StoreTest_Duplicate` | bool | each simulated receipt is delivered twice |
| `StoreTest_DelaySeconds` | number | wait before processing, so you can leave mid-purchase |
| `StoreTest_OwnPass_VIP` | bool | simulated VIP ownership (toggle live) |

To test **Roblox's own** purchase dialog in Studio (no Robux is charged in Studio): create the products (§6), paste their Ids, set `TestMode = false` and `Enabled = true`, then press Play in Studio. Studio shows its "test purchase" dialog and real receipts flow through the real ledger, still in the Studio DataStore.

## 5. Test plan
| # | Scenario | Where it's verified |
|---|---|---|
| T1 | Successful purchase grants and persists | ✅ unit test; 🧪 Studio M-2 |
| T2 | Failed / cancelled purchase grants nothing | 🧪 Studio M-3 |
| T3 | Duplicate receipt never regrants (same server and after rejoin) | ✅ unit tests; 🧪 Studio M-4 |
| T4 | DataStore failure: pending, no double grant, recovers | ✅ unit test; 🧪 Studio M-5 |
| T5 | Player leaves during purchase | ✅ unit tests; 🧪 Studio M-6 |
| T6 | Ownership persists across rejoin | 🧪 Studio M-7 (purchased cash); passes come from Roblox, so real ownership needs a private-experience test (P-2) |
| T7 | Concurrent processing | ✅ unit tests (same receipt, different receipts) |
| T8 | Real Roblox receipts and prompts | 🔒 needs created products: Studio test purchases (§4), then a private experience (P-1) |
| T9 | Live-server ownership via `UserOwnsGamePassAsync` | 🔒 private experience with a real pass (P-2) |

## 6. Going live (only after your approval, item by item)
1. Creator Dashboard → your experience → **Monetization → Developer Products**: create Small, Medium, Large and Mega cash packs at the prices you approve. Copy each Product Id.
2. **Monetization → Passes**: create *VIP Membership*, set it on sale, copy its Pass Id.
3. Paste the Ids into `MonetizationConfig.luau`. `validate()` warns in Output about duplicates or bad values.
4. Studio: `TestMode = false`, `Enabled = true` → run the Roblox test-purchase dialog (§4).
5. Private test experience (as in TESTING §P): run P-1 and P-2.
6. Only then merge to the build you publish. Publishing stays a manual step in Studio; nothing here publishes or changes Dashboard settings.

**Private servers** (Phase 4 topic, documented now): Creator Dashboard → experience → **Monetization → Private Servers** → enable, set the price (or free). No code change is needed for compatibility. Phase 4 will review low-player-count balancing.

## 7. Remaining phases
| Phase | Scope |
|---|---|
| 2 | VIP benefits (name tag, chat tag, aura, lounge, decorations, emotes), cash-pack store, premium store UI with live prices from `GetProductInfo`, owned indicators |
| 3 | Shop themes (6, with preview), character cosmetics (inventory, equip, persistence), emote system and wheel. New grant kinds plug into `grant()` and `Grant` |
| 4 | Seasonal event framework, private-server balancing, daily and weekly challenges, achievements |
| 5 | Analytics (AnalyticsService funnels and economy events), security review, performance and purchase testing |

## 8. Fairness commitments (kept in code review)
- Cash packs only buy what free players earn by playing; nothing is exclusive to payers except cosmetics.
- Prompts open only from a player's own click. There are no automatic popups, no fake timers and no loot boxes.
- Prices on screen come from Roblox (`GetProductInfo`) once Ids exist.
