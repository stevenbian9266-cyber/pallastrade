import { afterEach, describe, expect, it, vi } from "vitest";
import {
  dispatchLocalEvent,
  readLocalValue,
  writeLocalValue,
} from "@/lib/utils/local-store";

describe("local-store", () => {
  afterEach(() => {
    vi.restoreAllMocks();
    window.localStorage.clear();
  });

  it("round-trips a value and returns null for a missing key", () => {
    expect(readLocalValue("pt.test")).toBeNull();

    writeLocalValue("pt.test", "value");

    expect(readLocalValue("pt.test")).toBe("value");
  });

  it("degrades silently when storage throws (private mode / quota)", () => {
    vi.spyOn(Storage.prototype, "getItem").mockImplementation(() => {
      throw new Error("denied");
    });
    vi.spyOn(Storage.prototype, "setItem").mockImplementation(() => {
      throw new Error("quota");
    });

    expect(readLocalValue("pt.test")).toBeNull();
    expect(() => writeLocalValue("pt.test", "value")).not.toThrow();
  });

  it("dispatches the same-page event used to sync the rails", () => {
    const listener = vi.fn();
    window.addEventListener("pt:test", listener);

    dispatchLocalEvent("pt:test");

    expect(listener).toHaveBeenCalledTimes(1);
    window.removeEventListener("pt:test", listener);
  });

  it("never throws when event dispatch fails", () => {
    vi.spyOn(window, "dispatchEvent").mockImplementation(() => {
      throw new Error("boom");
    });

    expect(() => dispatchLocalEvent("pt:test")).not.toThrow();
  });
});
