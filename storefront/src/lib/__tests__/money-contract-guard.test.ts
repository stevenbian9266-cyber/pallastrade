import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

/**
 * PRD-20260913-checkout-money-contract AC-006 守护：
 * storefront 源码不得出现 `parseFloat/Number(...display_*)` 形态的金额逻辑——
 * `display_*` 字符串含货币符号（如 `$8.00`），解析结果恒为 NaN；
 * 逻辑判断必须读 raw 字段（delivery_total / tax_total / discount_total …）。
 */

const SRC_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");

function collectSourceFiles(dir: string, files: string[] = []): string[] {
  for (const entry of readdirSync(dir)) {
    const abs = join(dir, entry);
    if (statSync(abs).isDirectory()) {
      if (entry === "__tests__" || entry === "node_modules") continue;
      collectSourceFiles(abs, files);
    } else if (/\.(ts|tsx)$/.test(entry) && !entry.endsWith(".d.ts")) {
      files.push(abs);
    }
  }
  return files;
}

/** 匹配 parseFloat(…display_…) / Number(…display_…)（同一行内）。 */
const FORBIDDEN = /(?:parseFloat|Number)\s*\([^)]*\bdisplay_[a-z_]+/;

describe("Money contract guard (PRD-20260913-checkout-money-contract AC-006)", () => {
  it("does not parse display_* amount strings for logic", () => {
    const offenders = collectSourceFiles(SRC_ROOT)
      .filter((file) => {
        const lines = readFileSync(file, "utf8").split("\n");
        return lines.some(
          (line) =>
            FORBIDDEN.test(line) &&
            !line.trimStart().startsWith("*") &&
            !line.trimStart().startsWith("//"),
        );
      })
      .map((file) => file.replace(SRC_ROOT, "src"));

    expect(offenders).toEqual([]);
  });
});
