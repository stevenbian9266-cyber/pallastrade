import { afterEach, describe, expect, it, vi } from "vitest";
import { actionResult, withFallback } from "../utils";

afterEach(() => {
  vi.restoreAllMocks();
});

describe("actionResult", () => {
  it("returns { success: true, ...data } when the fn resolves", async () => {
    const result = await actionResult(async () => ({ id: "m1" }), "fallback");
    expect(result).toEqual({ success: true, id: "m1" });
  });

  it("returns { success: false, error: message } when the fn throws an Error", async () => {
    const result = await actionResult(async () => {
      throw new Error("boom");
    }, "fallback");
    expect(result).toEqual({ success: false, error: "boom" });
  });

  it("uses the fallback message for non-Error throws", async () => {
    const result = await actionResult(async () => {
      throw "string-error";
    }, "fallback");
    expect(result).toEqual({ success: false, error: "fallback" });
  });
});

describe("withFallback", () => {
  it("returns the fn result on success", async () => {
    expect(await withFallback(async () => 42, 0)).toBe(42);
  });

  it("logs the error and returns the fallback on failure", async () => {
    const spy = vi.spyOn(console, "error").mockImplementation(() => {});
    const result = await withFallback(async () => {
      throw new Error("downstream");
    }, 0);
    expect(result).toBe(0);
    expect(spy).toHaveBeenCalled();
  });
});
