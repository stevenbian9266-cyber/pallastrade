import { afterEach, describe, expect, it, vi } from "vitest";
import { createFetchWithTimeout } from "../config";

// # 修复：storefront API 请求缺超时导致预渲染挂起/构建失败
describe("createFetchWithTimeout", () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  it("attaches an AbortSignal to every request", () => {
    const innerFetch = vi.fn(
      (_input: RequestInfo | URL, _init?: RequestInit) =>
        Promise.resolve(new Response("{}", { status: 200 })),
    );
    const fetchWithTimeout = createFetchWithTimeout(
      8000,
      innerFetch as typeof fetch,
    );

    void fetchWithTimeout("https://api.example.com/products", {
      method: "GET",
    });

    expect(innerFetch).toHaveBeenCalledTimes(1);
    const [url, init] = innerFetch.mock.calls[0];
    expect(url).toBe("https://api.example.com/products");
    expect(init?.signal).toBeInstanceOf(AbortSignal);
    expect(init?.signal?.aborted).toBe(false);
  });

  it("aborts the request when the timeout elapses (fast failure, no hang)", async () => {
    // Inner fetch never resolves until the signal aborts — simulating an
    // unreachable API that would otherwise hang indefinitely.
    const innerFetch = vi.fn(
      (_input: RequestInfo | URL, init?: RequestInit) =>
        new Promise((_resolve, reject) => {
          const signal = init?.signal as AbortSignal | undefined;
          if (signal?.aborted) {
            reject(
              new DOMException("The operation was aborted.", "AbortError"),
            );
            return;
          }
          signal?.addEventListener("abort", () =>
            reject(new DOMException("The operation was aborted.", "AbortError")),
          );
        }),
    );
    const fetchWithTimeout = createFetchWithTimeout(
      50,
      innerFetch as typeof fetch,
    );

    await expect(
      fetchWithTimeout("https://api.example.com/products"),
    ).rejects.toThrow("aborted");
  });

  it("still injects a signal when the default timeout is used", () => {
    const innerFetch = vi.fn(
      (_input: RequestInfo | URL, _init?: RequestInit) =>
        Promise.resolve(new Response("{}", { status: 200 })),
    );
    const fetchWithTimeout = createFetchWithTimeout(
      undefined,
      innerFetch as typeof fetch,
    );

    void fetchWithTimeout("https://api.example.com/products");

    const init = innerFetch.mock.calls[0]?.[1];
    expect(init?.signal).toBeInstanceOf(AbortSignal);
    expect(init?.signal?.aborted).toBe(false);
  });
});
