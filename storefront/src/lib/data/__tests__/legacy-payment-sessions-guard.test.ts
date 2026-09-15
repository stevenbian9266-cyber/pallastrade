import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const SRC_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "../../..");

function collectSourceFiles(dir: string, acc: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    if (entry === "node_modules" || entry === ".next") continue;
    const full = join(dir, entry);
    if (statSync(full).isDirectory()) {
      collectSourceFiles(full, acc);
    } else if (/\.(ts|tsx)$/.test(entry)) {
      acc.push(full);
    }
  }
  return acc;
}

/** 去掉整行注释，避免把“说明为何不用 legacy”的注释误判为调用。 */
function isCommentLine(line: string) {
  const trimmed = line.trim();
  return (
    trimmed.startsWith("//") ||
    trimmed.startsWith("*") ||
    trimmed.startsWith("/*") ||
    trimmed.startsWith("*/")
  );
}

/**
 * 回归守护（PRD-20260915-checkout B4 FR-011 / AC-013）：
 * 收银前端在钱包或结账页都不允许再出现 legacy 的
 * `carts.paymentSessions.create|complete`，也禁止回退到已删除的
 * `/confirm-payment` 页面与 `lib/data/payment.ts` 适配层。
 */
describe("legacy payment-session consumers are gone", () => {
  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-013
  it("keeps zero cart-domain payment-session calls in the storefront source", () => {
    const offenders = collectSourceFiles(SRC_ROOT)
      .map((file) => ({
        file: relative(SRC_ROOT, file),
        hits: readFileSync(file, "utf8")
          .split(/\r?\n/)
          .map((line, index) => ({ line, index: index + 1 }))
          .filter(
            ({ line }) =>
              !isCommentLine(line) && /carts\s*\.\s*paymentSessions/.test(line),
          ),
      }))
      .filter(({ hits }) => hits.length > 0);

    expect(offenders).toEqual([]);
  });

  // PRD-20260915-checkout-checkout-收尾收敛-b4-express-钱包-canonicalize-legacy-会话-transacti AC-012
  it("keeps the deleted legacy surfaces deleted", () => {
    const removed = [
      `src/lib/data/payment.ts`,
      `src/app/[country]/[locale]/(checkout)/confirm-payment`,
    ];

    for (const target of removed) {
      expect(() => statSync(join(SRC_ROOT, "..", target))).toThrow();
    }
  });
});
