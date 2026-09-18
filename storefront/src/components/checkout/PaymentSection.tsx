"use client";

import type { PaymentMethod } from "@pallastrade/sdk";
import { CreditCard, Wallet } from "lucide-react";
import { useTranslations } from "next-intl";

/**
 * PALLAS-CUSTOM: D7（PRD-20260918-payments-d7-payment-section-express）
 *
 * 支付区「入口级」读模型与共用渲染外壳（cart_ 单页结账 / or_ 订单页 / 抽屉共用）。
 *
 * 红线（pallastrade-storefront SKILL）：
 * - **入口集合与是否出现由服务端决定**（`Availability::Resolver` 与 `PaymentSessions::Start`
 *   同源求值，含 D8 范围规则 / D11 熔断 / D15c 认证闸门）——客户端**不得**按
 *   `kind` / `frontend_kind` 自行隐藏入口，只负责「按形态渲染」。
 * - 旧响应（无 `entries`）必须能跑：回落到「一 provider 一行」（AC-010）。
 */

/** 服务端投影的入口项（`entries[]`）。 */
export interface PaymentEntry {
  option_id: string;
  method_key: string;
  display_name: string;
  /** 渲染形态：`inline`（自绘卡字段）/ `express`（钱包按钮）/ `manual`（线下收款说明）。 */
  frontend_kind: string;
  /** 语义分组：`card` / `wallet` / `redirect` / `manual`。 */
  group: string;
  position: number;
}

export interface PaymentMethodWithEntries
  extends Omit<PaymentMethod, "group" | "position" | "entries"> {
  /**
   * 服务端下发的入口级列表（additive）。
   * 用 `Omit + 可选` 声明：既兼容**已重新生成**的 SDK（`entries` / `group` / `position` 为必填），
   * 也兼容未重新生成、仍是旧类型的消费者（缺字段 → 由 `paymentEntriesFor` 推导单入口）。
   */
  entries?: PaymentEntry[] | null;
  group?: string;
  position?: number;
  /** D15 切片3：本单是否要求 3DS/SCA（服务端权威；仅用于提示，不做筛选）。 */
  requires_authentication?: boolean;
}

/**
 * 入口列表（含**向后兼容回退**）：无 `entries` 的旧响应 → 由 provider 自身字段
 * 合成**单条**入口（与 D16 的展示口径一致：`display_name ?? name`）。
 */
export function paymentEntriesFor(
  method: PaymentMethodWithEntries,
): PaymentEntry[] {
  if (Array.isArray(method.entries) && method.entries.length > 0) {
    return [...method.entries].sort(
      (a, b) => (a.position ?? 0) - (b.position ?? 0),
    );
  }

  return [
    {
      option_id: method.option_id ?? `${method.id}:default`,
      method_key: method.method_key ?? method.kind ?? "default",
      display_name: method.display_name ?? method.name ?? "",
      // 旧响应可能缺 `frontend_kind`：按会话能力推导（会话类 = 自绘卡字段 inline，
      // 否则 = 线下说明 manual），保证回退路径仍渲染到正确的形态槽。
      frontend_kind:
        method.frontend_kind ?? (method.session_required ? "inline" : "manual"),
      group: method.group ?? "card",
      position: method.position ?? 0,
    },
  ];
}

/** 入口图标（仅装饰；形态判定一律走 `frontend_kind`/`group`）。 */
export function entryIconKind(entry: PaymentEntry): "wallet" | "card" {
  if (entry.group === "wallet" || entry.frontend_kind === "express") {
    return "wallet";
  }
  return "card";
}

export interface PaymentEntryRowProps {
  entry: PaymentEntry;
  method: PaymentMethodWithEntries;
  selected: boolean;
  onSelect: (entry: PaymentEntry) => void;
  /** 单选组名（同一页多组时避免串组）。 */
  name?: string;
}

/** 单个入口行（radio + 展示名）。 */
export function PaymentEntryRow({
  entry,
  selected,
  onSelect,
  name = "payment-method",
}: PaymentEntryRowProps) {
  const Icon = entryIconKind(entry) === "wallet" ? Wallet : CreditCard;

  return (
    <label
      data-testid="payment-entry-row"
      data-option-id={entry.option_id}
      data-frontend-kind={entry.frontend_kind}
      className={`flex items-center gap-3 p-3 rounded-lg border cursor-pointer hover:border-indigo-300 ${
        selected ? "border-indigo-400 bg-indigo-50/40" : "border-gray-200"
      }`}
    >
      <input
        type="radio"
        name={name}
        checked={selected}
        onChange={() => onSelect(entry)}
        className="w-4 h-4 text-indigo-600 focus:ring-indigo-500"
      />
      <Icon className="w-4 h-4 text-gray-500" strokeWidth={1.5} />
      <span className="flex-1 font-medium text-gray-900">
        {entry.display_name}
      </span>
    </label>
  );
}

export interface PaymentSectionProps {
  /** 服务端投影的 provider 列表（每个可带 `entries[]`）。 */
  methods: PaymentMethodWithEntries[];
  /** 选中的入口 `option_id`。 */
  selectedOptionId: string | null;
  /** 入口被选中（父级据此决定渲染哪个形态的支付控件）。 */
  onSelect: (entry: PaymentEntry, method: PaymentMethodWithEntries) => void;
  /** 无可用入口时的兜底。 */
  emptyLabel: string;
  /** 认证需求提示（D15c；服务端已过滤入口，这里只解释「为什么只剩这些」）。 */
  authenticationNotice?: string | null;
  /** 其它需要出现在列表下方的说明（如 3DS 提示）。 */
  children?: React.ReactNode;
}

/**
 * 入口级支付列表（共用外壳）：把「一 provider 一行」升级为「一入口一行」，
 * 顺序完全按服务端 `position`（与后台排序一致）。
 */
export function PaymentSection({
  methods,
  selectedOptionId,
  onSelect,
  emptyLabel,
  authenticationNotice,
  children,
}: PaymentSectionProps) {
  const t = useTranslations("checkout");

  const rows = methods.flatMap((method) =>
    paymentEntriesFor(method).map((entry) => ({ entry, method })),
  );

  if (rows.length === 0) {
    return (
      <div
        data-testid="no-payment-method"
        className="rounded-lg border border-amber-200 bg-amber-50 p-3 text-sm text-amber-800"
      >
        {emptyLabel}
      </div>
    );
  }

  return (
    <div data-testid="payment-section">
      <div className="flex flex-col gap-3">
        {rows.map(({ entry, method }) => (
          <PaymentEntryRow
            key={entry.option_id}
            entry={entry}
            method={method}
            selected={selectedOptionId === entry.option_id}
            onSelect={(selected) => onSelect(selected, method)}
          />
        ))}
      </div>

      {authenticationNotice ? (
        <div
          data-testid="authentication-required-notice"
          className="mt-4 rounded-lg border border-indigo-200 bg-indigo-50 p-3 text-sm text-indigo-800"
        >
          {authenticationNotice}
        </div>
      ) : null}

      {rows.some(({ entry }) => entry.frontend_kind === "manual") ? (
        <p
          data-testid="manual-entry-note"
          className="mt-4 text-xs text-gray-500"
        >
          {t("manualPaymentNote")}
        </p>
      ) : null}

      {children}
    </div>
  );
}
