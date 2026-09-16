# PallasTrade PRD 鏂囨。搴?
> 涓€鍙ヨ瘽闇€姹?鈫?璇︾粏 PRD 鈫?harness 闂ㄧ瀹炴柦 鈫?娴嬭瘯楠屾敹 鈫?鐭ヨ瘑鍚屾銆傛湰鐩綍涓?PRD 缁熶竴瀛樻斁澶勩€?
## 鐩綍缁撴瀯

```
docs/prd/
鈹溾攢鈹€ README.md            # 鏈储寮曪紙AI 姣忔鍙樻洿鍚庤嚜鍔ㄦ洿鏂帮級
鈹溾攢鈹€ _TEMPLATE.md         # PRD 鏂囨。妯℃澘锛堝繀鐢級
鈹溾攢鈹€ catalog/             # 鍟嗗搧 / 绫荤洰 / 鎼滅储
鈹溾攢鈹€ checkout/            # 璐墿杞?/ 缁撶畻 / 璁㈠崟
鈹溾攢鈹€ payments/            # 鏀粯 / 閫€娆?鈹溾攢鈹€ promotions/          # 淇冮攢 / 浼樻儬鍒?鈹溾攢鈹€ pricing/             # 浠锋牸 / 澶氬竵绉?鈹溾攢鈹€ shipping/            # 鐗╂祦 / 搴撳瓨 / 灞ョ害
鈹溾攢鈹€ admin/               # 绠＄悊鍚庡彴
鈹溾攢鈹€ storefront/          # 鍟嗗煄鍓嶇
鈹溾攢鈹€ api/                 # 鎺ュ彛 / API 瑙勮寖
鈹溾攢鈹€ platform/            # SDK / CLI / 骞冲彴鑳藉姏
鈹溾攢鈹€ security/            # 瀹夊叏
鈹溾攢鈹€ i18n/                # 澶氳瑷€
鈹溾攢鈹€ harness/             # 宸ョ▼鏈哄埗
鈹溾攢鈹€ infra/               # 閮ㄧ讲 / 鍩虹璁炬柦
鈹斺攢鈹€ other/               # 鍏朵粬
```

## 鍛藉悕瑙勫垯

```
PRD-{YYYYMMDD}-{category}-{slug}.md
渚嬶細PRD-20260808-catalog-bulk-import.md
```

鍒嗙被鐢?`harness/policies/prd-categories.json` 鍏抽敭璇嶈鍒欒嚜鍔ㄥ垽瀹氾紝AI 鍙涔夊井璋冦€?
## PRD 鍒楄〃

| 鐘舵€?| PRD | 鍒嗙被 | 鏃ユ湡 | 鍏宠仈 REQ |
|---|---|---|---|---|
| done | PRD-20260914-checkout-quote-confirmation-loop | checkout | 2026-09-14 | REQ-20260914-checkout-quote-confirmation-loop.md |
| done | PRD-20260914-admin-disputes-evidence-params-whitelist | admin | 2026-09-14 | REQ-20260914-admin-disputes-evidence-params-whitelist.md |
| done | PRD-20260914-shipping-category-name-i18n-fallback | shipping | 2026-09-14 | REQ-20260914-shipping-category-name-i18n-fallback.md |
| done | PRD-20260913-checkout-billing-mode | checkout | 2026-09-13 | REQ-20260913-checkout-billing-mode.md |
| done | PRD-20260913-checkout-txn-error-routing | checkout | 2026-09-13 | REQ-20260913-checkout-error-routing-and-money-contract.md |
| done | PRD-20260913-checkout-money-contract | checkout | 2026-09-13 | REQ-20260913-checkout-error-routing-and-money-contract.md |
| done | PRD-20260913-payments-dsp-p7-9-partial-and-multi-dispute-semantics | payments | 2026-09-13 | REQ-20260913-dsp-p7-9-partial-and-multi-dispute-semantics.md |
| done | PRD-20260913-payments-dsp-p7-8-dispute-dangerous-actions-and-evidence-submission | payments | 2026-09-13 | REQ-20260913-dsp-p7-8-dispute-dangerous-actions.md |
| done | PRD-20260913-payments-dsp-p7-7-admin-disputes-console | payments | 2026-09-13 | REQ-20260913-dsp-p7-7-admin-disputes-console.md |
| done | PRD-20260912-payments-dsp-p7-6-dispute-recovery | payments | 2026-09-12 | REQ-20260912-dsp-p7-6-dispute-recovery.md |
| done | PRD-20260912-payments-dsp-p7-5-dispute-deadline-sweep | payments | 2026-09-12 | REQ-20260912-dsp-p7-5-dispute-deadline-sweep.md |
| done | PRD-20260912-payments-dsp-p7-4-dispute-evidence-snapshot | payments | 2026-09-12 | REQ-20260912-dsp-p7-4-dispute-evidence-snapshot.md |
| done | PRD-20260912-payments-dsp-p7-3-dispute-posting-and-reconcile | payments | 2026-09-12 | REQ-20260912-dsp-p7-3-dispute-posting-and-reconcile.md |
| done | PRD-20260911-payments-dsp-p7-2-dispute-fact-resolution | payments | 2026-09-11 | REQ-20260911-dsp-p7-2-dispute-fact-resolution.md |
| done | PRD-20260911-payments-dsp-p7-1-durable-dispute-model-and-provider-event-ingestion | payments | 2026-09-11 | REQ-20260911-dsp-p7-1-dispute-model-and-event-ingestion.md |
| done | PRD-20260911-payments-dsp-p7-0-dispute-semantic-audit-and-data-model-freeze | payments | 2026-09-11 | REQ-20260911-dsp-p7-0-dispute-semantic-audit.md |
| done | PRD-20260911-promotions-promo-batch6-pr-p9-cleanup | promotions | 2026-09-11 | REQ-20260911-promo-batch6-pr-p9-cleanup.md |
| done | PRD-20260911-promotions-promo-batch5b-permission-single-source | promotions | 2026-09-11 | REQ-20260911-promo-batch5b-permission-single-source.md |
| done | PRD-20260910-promotions-promo-batch5a-definition-registry | promotions | 2026-09-10 | REQ-20260910-promo-batch5a-definition-registry.md |
| done | PRD-20260910-promotions-promo-batch4b-refund-allocation | promotions | 2026-09-10 | REQ-20260910-promo-batch4b-refund-allocation.md |
| done | PRD-20260910-promotions-promo-batch4a-orderpromotion-snapshot | promotions | 2026-09-10 | REQ-20260910-promo-batch4a-orderpromotion-snapshot.md |
| done | PRD-20260910-promotions-promo-batch3c-redemption-readonly | promotions | 2026-09-10 | REQ-20260910-promo-batch3c-redemption-readonly.md |
| done | PRD-20260910-promotions-promo-batch3b-redemption-hardening | promotions | 2026-09-10 | REQ-20260910-promo-batch3b-redemption-hardening.md |
| done | PRD-20260910-promotions-promo-batch3a-redemption-ledger | promotions | 2026-09-10 | REQ-20260910-promo-batch3a-redemption-ledger.md |
| done | PRD-20260909-promotions-promo-batch2-discount-projection-unified | promotions | 2026-09-09 | REQ-20260910-promo-batch2-discount-projection-unified.md |
| done | PRD-20260909-promotions-promo-batch1-invariants-and-code-uniqueness | promotions | 2026-09-09 | REQ-20260909-promo-batch1-invariants-and-code-uniqueness.md |
| done | PRD-20260909-payments-rev-p6-8j-ordercancellation-state-machine | payments | 2026-09-09 | REQ-20260909-rev-p6-8j-ordercancellation-state-machine.md |
| done | PRD-20260909-payments-瀛ゅ効閫€娆捐ˉ璁?backfill-refunds-backfillproviderrefund-rake-dry-run- | payments | 2026-09-09 | REQ-20260909-rev-p6-8m-orphan-refund-backfill.md |
| done | PRD-20260909-payments-admin-api-v3-鍙绔偣-payment_combinations-index-show-refunds-sh | payments | 2026-09-09 | REQ-20260909-rev-p6-8l-admin-api-v3-readonly.md |
| done | PRD-20260908-payments-rev-p6-8i-recover-auto-scheduling | payments | 2026-09-08 | REQ-20260908-rev-p6-8i-recover-auto-scheduling.md |
| done | PRD-20260908-payments-rev-p6-8h-orphan-amounts-payment-ops | payments | 2026-09-08 | REQ-20260908-rev-p6-8h-orphan-amounts-payment-ops.md |
| done | PRD-20260908-payments-rev-p6-8g-combination-visibility-rails-admin | payments | 2026-09-08 | REQ-20260908-rev-p6-8g-combination-visibility.md |
| done | PRD-20260908-payments-rev-p6-8f-combination-level-cancel-orchestration | payments | 2026-09-08 | REQ-20260908-rev-p6-8f-combination-level-cancel.md |
| done | PRD-20260908-payments-rev-p6-8e-reverse-commerce-recover-cross-domain | payments | 2026-09-08 | REQ-20260908-rev-p6-8e-reverse-commerce-recover.md |
| done | PRD-20260908-payments-rev-p6-8d-provider-orphan-refund-pairing | payments | 2026-09-08 | REQ-20260908-rev-p6-8d-provider-orphan-refund-pairing.md |
| done | PRD-20260908-payments-rev-p6-8c-reimbursement-async-chain-durable-requested-executejob | payments | 2026-09-08 | REQ-20260908-rev-p6-8c-reimbursement-async-chain.md |
| done | PRD-20260908-payments-rev-p6-8b-refund-manual-review-retry-浜哄伐瑁佸喅涓庣‘瀹氭€ч噸璇?鍗遍櫓鎿嶄綔 | payments | 2026-09-08 | REQ-20260908-rev-p6-8b-refund-manual-review-retry.md |
| done | PRD-20260908-payments-rev-p6-8a-refund-admin-ops-鍙鎬?閫€娆剧姸鎬佸垪琛?璇︽儏-rails-admin | payments | 2026-09-08 | REQ-20260908-rev-p6-8a-refund-admin-ops-visibility.md |
| done | PRD-20260908-storefront-灏忓睆涓嬩釜浜轰腑蹇冨叆鍙ｅ彲瑙佷笌绉诲姩鑿滃崟search寮瑰嚭鎼滅储妗?| storefront | 2026-09-08 | REQ-20260908-storefront-mobile-account-and-menu-search.md |
| done | PRD-20260908-checkout-鍟嗗煄鍓嶅彴-order-妯″潡-璁㈠崟鍒楄〃鎺掑簭鎸夎鍗曞垱寤烘椂闂寸敱杩戝埌杩滄帓搴?| checkout | 2026-09-08 | REQ-20260908-store-order-list-created-at-desc.md |
| done | PRD-20260908-payments-rev-p6-7-financial-convergence-refund-posting | payments | 2026-09-08 | REQ-20260908-rev-p6-7-financial-convergence.md |
| done | PRD-20260908-payments-rev-p6-6-refund-reverse-recovery-recover-recoverjob-recovers | payments | 2026-09-08 | REQ-20260908-rev-p6-6-refund-reverse-recovery.md |
| done | PRD-20260907-shipping-rev-p6-5-return-restock-decision-exactly-once-restock-accept | shipping | 2026-09-07 | REQ-20260907-rev-p6-5-return-restock-exactly-once.md |
| done | PRD-20260907-payments-rev-p6-4-cancellation-orchestration-鍙栨秷涓氬姟鍐崇瓥涓婃敹-unpaid-void-pai | payments | 2026-09-07 | REQ-20260907-rev-p6-4-cancellation-orchestration.md |
| done | PRD-20260907-payments-rev-p6-3-partial-combination-refund-allocation-缁勫悎閫€娆?ownershi | payments | 2026-09-07 | REQ-20260907-rev-p6-3-partial-combination-refund-allocation.md |
| done | PRD-20260906-payments-rev-p6-2-refund-execution-orchestration-refunds-request-asyn | payments | 2026-09-06 | REQ-20260906-rev-p6-2-refund-execution.md |
| done | PRD-20260906-payments-rev-p6-1-durable-refund-lifecycle-foundation-閫€娆?durable-鐢熷懡鍛ㄦ湡 | payments | 2026-09-06 | REQ-20260906-rev-p6-1-durable-refund-lifecycle.md |
| done | PRD-20260906-admin-core-p5-8-operational-hardening-legacy-璺緞浣跨敤璁℃暟-杩愯惀鎸囨爣鍩嬬偣 | admin | 2026-09-06 | REQ-20260906-cp5-8-operational-hardening.md |
| done | PRD-20260906-payments-fin-p4-8-repair-legacy-operations | payments | 2026-09-06 | REQ-20260906-fin-p4-8.md |
| done | PRD-20260906-payments-fin-p4-7-transaction-reconciliation | payments | 2026-09-06 | REQ-20260906-fin-p4-7.md |
| done | PRD-20260906-payments-fin-p4-6-source-reconciliation | payments | 2026-09-06 | REQ-20260906-fin-p4-6.md |
| done | PRD-20260906-payments-fin-p4-5-stripe-provider-financial-facts | payments | 2026-09-06 | REQ-20260906-fin-p4-5.md |
| done | PRD-20260906-payments-fin-p4-4-allocation-integrity | payments | 2026-09-06 | REQ-20260906-fin-p4-4.md |
| done | PRD-20260906-payments-fin-p4-3-payment-refund-posting | payments | 2026-09-06 | REQ-20260906-fin-p4-3.md |
| done | PRD-20260905-payments-fin-p4-2-immutable-financial-journal | payments | 2026-09-05 | REQ-20260906-fin-p4-2.md |
| done | PRD-20260905-payments-fin-p4-1-鏀粯璧勯噾璐︽湰-commercetransaction-绾?immutable-financial-jo | payments | 2026-09-05 | REQ-20260906-fin-p4-1.md |
| done | PRD-20260905-shipping-搴撳瓨浜嬪姟闆嗘垚涓庨鐣欑敓鍛藉懆鏈?p3-stockreservation-鎺ュ叆-commercetransaction-res | shipping | 2026-09-05 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260905-checkout-paymentcombination-txn-鍖?缁勫悎浜ゆ槗鏀舵暃鍒?transactions-finalize-recov | checkout | 2026-09-05 | REQ-20260905-paymentcombination-txn.md |
| done | PRD-20260905-checkout-txn-p2-6-杞?-storefront-transaction-first-杩佺Щ-checkout-start-b | checkout | 2026-09-05 | REQ-20260905-txn-p2-6-storefront-transaction-first.md |
| done | PRD-20260905-payments-txn-p2-6-contract-snapshot | payments | 2026-09-05 | REQ-20260905-txn-p2-6-contract-snapshot.md |
| done | PRD-20260905-other-txn-p2-closure-report-and-store-serializer | other | 2026-09-05 | REQ-20260905-txn-p2-closure.md |
| done | PRD-20260905-payments-txn-p2-7-operational-hardening-backend-slice | payments | 2026-09-05 | REQ-20260905-txn-p2-7.md |
| done | PRD-20260904-payments-txn-p2-5-unified-finalization-transactions-finalize-onpaymentsuccess | payments | 2026-09-04 | REQ-20260904-txn-p2-5.md |
| done | PRD-20260904-payments-txn-p2-4-recovery-engine-recovery-required-鏉冨▉鐘舵€佽В鏋?recover | payments | 2026-09-04 | REQ-20260904-txn-p2-4.md |
| done | PRD-20260904-payments-txn-p2-3-payment-fact-resolver-provider-鍙鐘舵€佸绾?璧勯噾浜嬪疄鍒ゅ畾 | payments | 2026-09-04 | REQ-20260904-txn-p2-3.md |
| done | PRD-20260904-api-txn-p2-2-transactions-start-resume-浜嬪姟鍚姩骞傜瓑-quote-consent-sess | api | 2026-09-04 | REQ-20260904-txn-p2-2.md |
| done | PRD-20260904-checkout-txn-p2-1-commercetransaction-core-transactions-transaction_o | checkout | 2026-09-04 | REQ-20260904-txn-p2-1.md |
| done | PRD-20260902-payments-payment-p0-foundation-hardening-paymentsession-payment-姝ｅ紡鍏宠仈- | payments | 2026-09-02 | REQ-20260902-payment-p0.md |
| done | PRD-20260831-harness-瀹炴柦-harness-token-浼樺寲-瀹夸富渚?| harness | 2026-08-31 | REQ-20260831-harness-token-optimization-host.md |
| done | PRD-20260830-checkout-涓嬪崟閾捐矾瑙勮寖鍖栫粺涓€鍖?鍦烘櫙a-b缁熶竴涓嬪崟椤?鍦烘櫙c鏀堕摱鍙板脊绐?鍙傝€冮樋閲屽浗闄呯珯 | checkout | 2026-08-30 | REQ-20260901-positive-checkout-payment-flow-hardening.md |
| done | PRD-20260830-other-淇-skill-鏉冨▉璺緞 | other | 2026-08-30 | REQ-20260830-fix-skill-authority-paths.md |
| done | PRD-20260829-checkout-璁㈠崟妯″潡-鍗曠瑪璧扮幇鏈塩heckout-澶氱瑪璧扮粍鍚堟敮浠樻柊娴佺▼-鏀惰揣淇℃伅鐙珛濉啓 | checkout | 2026-08-29 | REQ-20260830-order-module-single-combined-payment.md |
| done | PRD-20260829-checkout-璁㈠崟娴佺▼鏍囧噯鐢靛晢鏀归€?璐墿杞︿笌璁㈠崟鍒嗚〃-璁㈠崟纭-鎻愪氦璁㈠崟-checkout绾敮浠?鑷湁鍖栧幓涓婃父鍝佺墝鍖?| checkout | 2026-08-29 | REQ-20260830-order-flow-standard-ecommerce-p1.md |
| done | PRD-20260828-checkout-p8-鍓嶇疆鏍￠獙-搴撳瓨-椋庢帶-璁㈠崟鏈嶅姟澧炲己-flag-鐏板害 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p8.md |
| done | PRD-20260828-checkout-p7-閫嗗悜閾捐矾鍞悗鐖跺瓙鍗曞寲-flag-鐏板害 | checkout | 2026-08-28 | REQ-20260828-order-lifecycle-p7.md |
| done | PRD-20260828-admin-p6-admin-鎵嬪姩鎷嗗崟-鐖跺瓙鏍?ui-flag-鐏板害 | admin | 2026-08-28 | REQ-20260828-order-lifecycle-p6.md |
| done | PRD-20260827-checkout-瀹炴柦-p5-checkout-闆嗘垚-鑷姩鎷嗗崟-鍚堝苟鏀粯鏀堕摱鍙?buy-now-flag-鐏板害 | checkout | 2026-08-27 | REQ-20260827-order-lifecycle-p5.md |
| done | PRD-20260827-payments-瀹炴柦-p4-鍚堝苟鏀粯杞戒綋-paymentcombination-鏈嶅姟灞?webhook-骞傜瓑瀹屾垚 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p4.md |
| done | PRD-20260827-payments-瀹炴柦-p3-鐖跺瓙鍗曢噾棰濅笌鏀粯鐘舵€佹淳鐢?combined_total-payment-shipment_state-鑱氬悎 | payments | 2026-08-27 | REQ-20260827-order-lifecycle-p3.md |
| done | PRD-20260826-checkout-瀹炴柦-p2-缁熶竴鎷嗗崟寮曟搸-orders-splitter-绛栫暐鍒嗙粍-璋冩暣鍒嗘憡-骞傜瓑 | checkout | 2026-08-26 | REQ-20260826-order-lifecycle-p2.md |
| done | PRD-20260826-payments-瀹炴柦-p1-鏁版嵁妯″瀷涓庤涔夋柟娉?鐖跺瓙鍗?parent_id-paymentcombination-paymentspli | payments | 2026-08-26 | REQ-20260826-order-lifecycle-p1.md |
| done | PRD-20260818-catalog-p0-4-浜у搧璇勮 | catalog | 2026-08-18 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260818-other-p0-3-閭欢鑷姩鍖?寮冨崟鎭㈠ | other | 2026-08-18 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260817-other-绉婚櫎鏍?package-json-鏃犵敤鐨?glob-寮冪敤渚濊禆 | other | 2026-08-17 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260817-admin-鏂板缓搴楅摵琛ㄥ崟-璐у竵璇█閫夋嫨鍣ㄤ笌閭棰勮 | admin | 2026-08-17 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260817-admin-澶氬簵閾虹鐞?搴楅摵鍒楄〃-鏂板缓-鍒囨崲 | admin | 2026-08-17 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260817-admin-鑿滃崟閰嶇疆鏀舵暃-缁撴瀯浠ｇ爜鍖?鍙鍖栧彧璇诲睍绀?鏉冮檺閰嶇疆渚濇嵁 | admin | 2026-08-17 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260816-admin-鍚庡彴鍙鍖栬彍鍗曢厤缃ā鍧?瑙掕壊鏉冮檺浣撶郴-鑿滃崟-鏁版嵁-鍔熻兘鏉冮檺 | admin | 2026-08-16 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260816-admin-绠＄悊鍚庡彴瀵艰埅鏋舵瀯缁熶竴閲嶆瀯-甯告樉鍘熷垯-闈㈠寘灞戣嚜鍔ㄦ帹瀵?鍗曚竴甯冨眬 | admin | 2026-08-16 | REQ-20260816-admin-nav-architecture |
| done | PRD-20260816-admin-绠＄悊鍚庡彴瀵艰埅涓€鑷存€?涓诲尯鎸?email-妯″紡-璁剧疆鍖烘寜-settings-妯″紡缁熶竴 | admin | 2026-08-16 | REQ-20260816-admin-nav-consistency |
| done | PRD-20260813-admin-绉婚櫎绠＄悊鍚庡彴-integrations-鑿滃崟鍙婄浉鍏抽€昏緫 | admin | 2026-08-13 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260808-admin-鍘绘帀绠＄悊鍚庡彴宸︿晶鑿滃崟鐨勫崌绾ч€昏緫-community-edition-鍗囩骇鎻愮ず | admin | 2026-08-08 | REQ-20260808-remove-enterprise-notice |
| done | PRD-20260808-admin-ai-tools-page-optimization | admin | 2026-08-08 | REQ-20260808-ai-tools-page-optimization |
| done | PRD-20260808-api-瀹炴柦-ai-tools-妯″潡浼樺寲-p0-locale淇-娣诲姞provider-p1-棰勮鍙-寮曞-p2-api鏂囨。- | api | 2026-08-08 | REQ-20260808-ai-tools-optimization |
| done | PRD-20260808-harness-l4-promotion | harness | 2026-08-08 | REQ-20260808-harness-l4-promotion |
| done | PRD-20260809-infra-aliyun-dev-prod-deploy | infra | 2026-08-09 | REQ-20260809-infra-aliyun-dev-prod-deploy |
| done | PRD-20260809-infra-oss-storage | infra | 2026-08-09 | REQ-20260809-oss-storage |
| merged | PRD-20260809-infra-oss-cache-control | infra | 2026-08-09 | REQ-20260809-oss-cache-control |
| done | PRD-20260809-harness-prd-dedupe-update | harness | 2026-08-09 | REQ-20260809-harness-prd-dedupe-update |
| done | PRD-20260809-storefront-brand-assets | storefront | 2026-08-09 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260809-catalog-鍒涘缓鍏旂嫴鍝佺墝鍥剧墖璧勬簮濂椾欢 | catalog | 2026-08-09 | REQ-20260810-pallas-cat-brand-assets |
| done | PRD-20260810-storefront-鍟嗗煄鍓嶅彴鎺ュ叆tawk-to浣滀负瀹㈡湇宸ュ叿 | storefront | 2026-08-10 | REQ-20260810-tawk-to-widget |
| done | PRD-20260810-storefront-瀵瑰晢鍩庡墠鍙拌繘琛岄噸鏂拌鍒?| storefront | 2026-08-10 | REQ-20260810-storefront-redesign |
| done | PRD-20260812-storefront-鍟嗗煄鍓嶅彴娉ㄥ唽闈㈡澘鎺ュ叆-turnstile-鐪熶汉楠岃瘉 | storefront | 2026-08-12 | REQ-20260812-turnstile-verification |
| done | PRD-20260812-storefront-鍟嗗煄鍓嶅彴鏂板cookie鍔熻兘 | storefront | 2026-08-12 | REQ-20260812-storefront-cookie-consent |
| done | PRD-20260813-storefront-瑁佸壀-admin-storefront-椤甸潰-vercel-闆嗘垚-ui-骞朵紭鍖栧凡杩炴帴-origins-灞曠ず | storefront | 2026-08-13 | REQ-20260814-trim-admin-storefront-vercel |
| 鉀斿簾寮?| PRD-20260814-admin-绠＄悊鍚庡彴缁熶竴閰嶇疆涓績-闆嗕腑绠＄悊鍏抽敭鍙傛暟涓?secret-env-浠庢ā鍧楀彇鏁?| admin | 2026-08-14 | REQ-20260814-admin-config-center |
| done | PRD-20260814-catalog-seo-娣卞害澧炲己-鍟嗗搧-鍒嗙被绾у厓鏁版嵁-json-ld-301-閲嶅畾鍚?| catalog | 2026-08-14 | REQ-20260815-seo-301-redirects |
| done | PRD-20260814-catalog-鍥剧墖-cdn-鍔ㄦ€佸彉鎹?resize-format-webp-鍝嶅簲寮忓浘鐗?| catalog | 2026-08-14 | REQ-20260815-image-cdn-transform |
| done | PRD-20260815-storefront-redirects-绠＄悊椤甸潰澧炲姞鍔熻兘璇存槑鏂囨 | storefront | 2026-08-15 | REQ-20260815-redirects-intro-copy |
| done | PRD-20260816-other-鏂板cms鍗氬 | other | 2026-08-16 | REQ-20260816-cms-blog |
| done | PRD-20260815-catalog-redirect-椤甸潰灞曠ず鍟嗗搧-url-鍙樻洿娓呭崟骞跺紩瀵煎垱寤洪噸瀹氬悜 | catalog | 2026-08-15 | REQ-20260815-redirects-url-change-list |
| done | PRD-20260815-other-redirect-澧炲姞鏍囬涓庢弿杩板瓧娈?| other | 2026-08-15 | REQ-20260815-redirect-title-description |
| done | PRD-20260815-shipping-琛ヨ揣閫氱煡-back-in-stock | shipping | 2026-08-15 | 璁㈤槄鈫掕ˉ璐т簨浠垛啋Resend 閭欢 delivered 楠岃瘉閫氳繃 |
| done | PRD-20260815-catalog-閭欢绠＄悊鏁村悎-email-涓€绾ц彍鍗?閰嶇疆-妯℃澘-璁板綍-鍒嗙被-鍥炲寮€鍏?| catalog | 2026-08-15 | REQ-20260815-email-management-integration |
| done | PRD-20260829-payments-鍗囩骇-stripe-鏀粯浠?payment-intents-杩佺Щ鍒?checkout-sessions-api-ui_m | payments | 2026-08-29 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260831-payments-stripe-鑷粯鍗℃敮浠樿〃鍗?paymentintent-妯″紡 | payments | 2026-08-31 | REQ-20260831-stripe-鑷粯鍗℃敮浠樿〃鍗?md |

| done | PRD-20260903-checkout-chk-p1-1a-read-only-checkoutview | checkout | 2026-09-03 | REQ-20260903-chk-p1-1a.md |
| done | PRD-20260903-checkout-chk-p1-1-order-checkout-application-layer-checkoutview | checkout | 2026-09-03 | REQ-20260903-chk-p1-{1b,2,3,4,4b,4c,5}.md 路 REQ-20260904-chk-p1-4c4.md |
| done | PRD-20260904-r1-contract-generation-infra | api | 2026-09-04 | REQ-20260904-r1-contract-generation.md |
| done | PRD-20260905-other-txn-p2-6-sdk-consumption | other | 2026-09-05 | REQ-20260905-txn-p2-6-sdk-consumption.md |
| done | PRD-20260831-infra-閮ㄧ讲鑴氭湰鍥哄寲涓庡閿?deploy-sf-鍥哄寲-pull-deploy-纾佺洏棰勬涓?flock-瓒呮椂-deploy-rea | infra | 2026-08-31 | REQ-20260831-閮ㄧ讲鑴氭湰鍥哄寲涓庡閿?md |
| merged | PRD-20260828-other-p7-閫嗗悜閾捐矾鍞悗鐖跺瓙鍗曞寲-flag-鐏板害 | other | 2026-08-28 | 锛堜笌 checkout-p7 鍚岄渶姹傦細鍘嗗彶鍓湰锛屾寮忎互 checkout 渚т负鍑嗭級 |
| done | PRD-20260913-harness-prd-鐘舵€佷竴鑷存€ф鏌ュ櫒-readme-绱㈠紩-鏂囦欢澶寸姸鎬佽嚜鍔ㄥ悓姝?寮曟搸鍙ｅ緞褰掍竴-ci-lefthook-婕傜Щ鍗冲け璐?| harness | 2026-09-13 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260913-payments-浜夎鏈湴杩愯惀澧炲己涓?stripe-娣卞寲-瑙勬牸-68-杈圭晫-c-璇佹嵁绱犳潗搴?鎻愪氦鍓嶆牎楠?璇佹嵁鐗堟湰鍥炴墽-瀹℃壒澶嶆牳-杩愯惀鎶ヨ〃- | payments | 2026-09-13 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-cart-discount-codes-canonical | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-other-prefixedid-ownership-validation | other | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-other-paymentsource-prefix-disambiguation | other | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-placeholder-controls-governance | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-cart-gift-cards-canonical | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-cart-store-credits-canonical | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-checkout-鏀跺熬鏀舵暃-b1-checkoutview-鎵╁睍-credits-capabilities-availa | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260914-checkout-checkout-鏀跺熬鏀舵暃-b2-璐墿杞﹂〉搴楅摵浣欓鍏ュ彛涓庤鍗曟憳瑕佷笁鍚堜竴 | checkout | 2026-09-14 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-checkout-checkout-鏀跺熬鏀舵暃-b3-搴撳瓨閿欒鍥涙€佷笌灞ョ害缁撴灉椤?recovery-璇箟-shipment-groups | checkout | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-checkout-checkout-鏀跺熬鏀舵暃-b4-express-閽卞寘-canonicalize-legacy-浼氳瘽-transacti | checkout | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-checkout-checkout-鏀跺熬鏀舵暃-b5-legacy-绔偣娌荤悊-usage-metric-鏀跺彛涓庨浂鏂板璋冪敤瀹堟姢 | checkout | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-admin-绠＄悊鍚庡彴-ui-b6-1-鍝佺墝鑹?token-璇箟-token-涓庡瘑搴﹀彉閲忓熀纭€灞?| admin | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-checkout-鍗曢〉涓ゆ璇箟-prepare-浜у嚭-order-鏉冨▉鎶ヤ环-椤靛唴鎶ヤ环纭 | checkout | 2026-09-15 | PRD-20260915-checkout-鍗曢〉涓ゆ璇箟 |

## 浣跨敤娴佺▼锛堟憳瑕侊紝璇﹁ `ai/skills/pallastrade-prd/SKILL.md`锛?
1. 鐢ㄦ埛涓€鍙ヨ瘽闇€姹?鈫?AI 鏌ラ噸 + 鍒嗙被 + 鐢熸垚 PRD锛坉raft锛?2. 鐢ㄦ埛纭 鈫?approved
3. `harness gate` 鈫?鐢熸垚 REQ 鈫?瀹炴柦 鈫?娴嬭瘯
4. 楠岃瘉 鈫?done 鈫?鐭ヨ瘑鍚屾闂紙鏇存柊鏈储寮曪級
| done | PRD-20260915-admin-绠＄悊鍚庡彴鏀粯閰嶇疆閫夐」鍖?鏀粯鍟?鏀粯鏂瑰紡-鍓嶅彴鍏ュ彛 | admin | 2026-09-15 | N/A |
| done | PRD-20260915-catalog-pdp-state-correctness | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-admin-bulk-operations-2 | admin | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-payments-d8-鏀粯閫傜敤鑼冨洿寮曟搸-鏀粯鍟?鏀粯鏂瑰紡-甯傚満-鍥藉-zone-甯佺-鍓嶅彴鍏ュ彛杩囨护 | payments | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-admin-catalog-health-v1 | admin | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-c1-discovery | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-c2-sku-back-in-stock | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-d1-product-history | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-d2-duplicate-detection | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-payments-d9-鏀粯鍑嵁涓庣幆澧?| payments | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-payments-d10-client-config | payments | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-e1-ai-copilot | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-payments-d12-webhook-governance | payments | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260915-catalog-batch-e2-ai-translate-missing | catalog | 2026-09-15 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260916-payments-d16-payment-method-presentation | payments | 2026-09-16 | 鍚庣璇绘ā鍨?+ 濂戠害涓夊瓧娈?+ 鍓嶅彴鏂规硶琛屾覆鏌擄紱`d16-payment-presentation-rspec` + `storefront-test` 缁?|
| done | PRD-20260916-payments-d13-reconciliation-cases | payments | 2026-09-16 | 瀹炴柦锛氭渚嬮槦鍒楋紙2 琛級+ SyncCases锛堝箓绛?鑷姩閿€妗?绛惧悕鍙栦唬锛? sweeper 鎺ュ叆 + 鍚庡彴宸ヤ綔鍙帮紙鎸囨淳/澶囨敞/鍏冲崟/CSV锛夛紱`d13-reconciliation-cases-rspec` |
| done | PRD-20260916-payments-d11-circuit-breaker-health | payments | 2026-09-16 | 瀹炴柦锛氱啍鏂姸鎬佹満 + 鍋ュ悍鎸囨爣 + 鍒ゅ畾/鎭㈠ + 姣忓皬鏃跺贰妫€ + Resolver 鍚屾簮闂ㄧ + 鍚庡彴銆岀啍鏂笌鍋ュ悍銆嶅崱锛堝師鍥犲繀濉?绮樻€?瀹¤锛夛紱`d11-circuit-breaker-rspec` |
| done | PRD-20260916-catalog-batch-e3-ai-fix-suggestion | catalog | 2026-09-16 | 锛堝疄鏂芥椂鍥炲～锛?|
| done | PRD-20260916-catalog-batch-f1-reviews | catalog | 2026-09-16 | 瀹炴柦锛氳瘎鍒嗗垎甯?+ 鍒嗛〉 Load more + 鍥剧墖璇勮锛堚墹3 寮?鐩翠紶/鏈鏍镐笉澶栨硠锛? 鍚庡彴鍥剧墖鍒楋紱`reviews-f1-rspec`锛堝悗绔?31 渚嬶級+ `storefront-test`锛?4 渚嬶級缁?|
| done | PRD-20260916-catalog-batch-f2-stock-shipping | catalog | 2026-09-16 | 瀹炴柦锛氬簱瀛樺垎妗讹紙涓?in_stock? 鍚屾簮銆佷笉涓嬪彂鏁板瓧锛? 閰嶉€佷及绠楄妯″瀷/绔偣 + PDP 寰界珷涓庨厤閫佸尯鍧?+ 鍗＄墖寰界珷锛沗f2-stock-shipping-rspec` + 鍓嶅彴 30 渚嬬豢 |
| done | PRD-20260916-catalog-batch-f3-review-bulk-moderation | catalog | 2026-09-16 | 瀹炴柦锛氳瘎璁哄鏍告壒閲忛€氳繃/鎷掔粷锛堥€愭潯鐘舵€佹満 + 閫愭潯閴存潈 + 鍥涜鏁版姤鍛?+ 50 鏉′笂闄愶紝澶嶇敤 B-1 妯℃€侊紝闆跺绾﹀彉鏇达級锛沗f3-review-bulk-rspec` 10 渚嬬豢 |
| done | PRD-20260916-catalog-batch-f4-review-sorting | catalog | 2026-09-16 | 瀹炴柦锛氳瘎璁烘帓搴忥紙`?sort=` 鐧藉悕鍗?+ 绋冲畾 tie-break + `meta.sort` + PDP 涓嬫媺鍒囨崲閲嶇疆棣栧睆 + 5 璇█锛夛紱鍚庣 10 渚?+ 鍓嶅彴 30 渚嬬豢锛宍generated:check` 鏃犳紓绉?|
| done | PRD-20260916-payments-d13b-payout-ledger | payments | 2026-09-16 | 瀹炴柦锛氱粨绠楀彴璐︼紙2 琛級+ CSV 瀵煎叆锛堝箓绛?閿欒鏀堕泦锛? 鍖归厤閿氱偣/瀹瑰樊 + 宸紓琛岃繘闃熷垪锛堣嚜鍔ㄩ攢妗堬級+ 鍚庡彴鍙拌处椤碉紙绛涢€?姹囨€?璇︽儏/瀵煎叆/閲嶅尮閰嶏級锛沗d13b-payouts-rspec`锛?2 渚嬶級缁?|
| done | PRD-20260916-payments-d14-refund-approval | payments | 2026-09-16 | 瀹炴柦锛氶€€娆剧瓥鐣ラ槇鍊硷紙鈮?鑷姩 / > 闇€绗簩浜烘壒鍑嗭級+ 骞傜瓑璇锋眰閿?+ 瀹℃壒宸ヤ綔鍙帮紙涓嶈兘鑷壒锛? Admin API 绛栫暐闂ㄤ笌 `approval_status` 濂戠害瀛楁锛沗d14-refund-approval-rspec`锛?4 渚嬶級缁匡紱鏈熼檺鎻愰啋涓庢嫆浠樼巼鐪嬫澘鐣欏垏鐗?/3 |
| done | PRD-20260916-payments-d14b-dispute-deadlines | payments | 2026-09-16 | 瀹炴柦锛堝垏鐗?锛夛細T-3/T-1 鍒嗘。骞傜瓑鍛婅锛堝彴璐﹀敮涓€閿?+ 璺虫。琛ラ綈锛? 瓒呮湡绛栫暐鍖栬嚜鍔?lost锛堥粯璁ゅ叧闂?+ 鍗曡疆涓婇檺 + 瀹¤锛? 鍚庡彴鍒嗘。鐪嬫澘/鍒?鎻愰啋鍘嗗彶锛沗d14b-dispute-deadlines-rspec`锛?1 渚嬶紝鍚?DSP-P7-5 鍥炲綊锛夌豢锛涢浂璧勯噾鍓綔鐢紱鎷掍粯鐜囩湅鏉跨暀鍒囩墖3 |
| done | PRD-20260916-catalog-batch-f5-helpful-vote | catalog | 2026-09-16 | 瀹炴柦锛氳瘎璁?Helpful Vote锛埪у崄 **鏈€鍚庝竴椤?*锛夆€斺€旀柊琛?`pallastrade_review_votes`锛堜竴浜轰竴绁ㄥ敮涓€绱㈠紩锛? `helpful_votes_count` 璁℃暟鍣?+ 2 涓姇绁ㄧ鐐?+ 璇绘ā鍨嬶紙璁℃暟鍏紑 / 鏈汉鐘舵€佷粎鐧诲綍锛? `most_helpful` 鎺掑簭 + 鍓嶅彴鎸夐挳涓庣櫥褰曞紩瀵?+ 鍚庡彴 Helpful 鍒楋紱鍚庣 29 渚?+ 鍓嶅彴 6 渚嬬豢锛宍f5-helpful-vote-rspec` |
