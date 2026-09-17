import { describe, expect, it, vi } from "vitest";

// The module under test imports the real server action; mock it so this stays a
// pure unit test (the action pulls in server-only env handling).
vi.mock("@/lib/data/catalog-events", () => ({
  sendCatalogEvents: vi.fn().mockResolvedValue({ received: 0 }),
}));

import {
  CATALOG_EVENT_MAX_BATCH,
  type CatalogEventInput,
  createCatalogEventQueue,
} from "../catalog-events";

// PRD-20260917-catalog-product-events AC-007 / AC-012
function event(n: number): CatalogEventInput {
  return {
    event_id: `e-${n}`,
    event_name: "impression",
    list_id: "related",
    position: n,
  };
}

describe("createCatalogEventQueue", () => {
  // AC-012: a page view must cost at most one request, because the backend's
  // rate-limit bucket is keyed by the API key the whole store shares.
  it("sends a whole page view as a single request", async () => {
    const send = vi.fn().mockResolvedValue({ received: 5 });
    const queue = createCatalogEventQueue({ send, visitorId: "v-1" });

    for (let i = 0; i < 5; i += 1) queue.track(event(i));

    expect(queue.pending()).toBe(5);
    expect(send).not.toHaveBeenCalled();

    await queue.flush();

    expect(send).toHaveBeenCalledTimes(1);
    expect(send.mock.calls[0][0]).toBe("v-1");
    expect(send.mock.calls[0][1]).toHaveLength(5);
    expect(queue.pending()).toBe(0);
  });

  it("does nothing when there is nothing queued", async () => {
    const send = vi.fn();
    const queue = createCatalogEventQueue({ send, visitorId: "v-1" });

    await queue.flush();

    expect(send).not.toHaveBeenCalled();
  });

  // AC-007: analytics must never surface an error to the user, and must not
  // retry into a rate-limit budget shared with real traffic.
  it("swallows a failing send without throwing or retrying", async () => {
    const send = vi.fn().mockRejectedValue(new Error("503"));
    const queue = createCatalogEventQueue({ send, visitorId: "v-1" });

    queue.track(event(1));

    await expect(queue.flush()).resolves.toBeUndefined();
    expect(send).toHaveBeenCalledTimes(1);
    expect(queue.pending()).toBe(0);
  });

  it("drops the batch when the server action reports failure", async () => {
    const send = vi.fn().mockResolvedValue(null);
    const queue = createCatalogEventQueue({ send, visitorId: "v-1" });

    queue.track(event(1));
    await queue.flush();

    expect(queue.pending()).toBe(0);
  });

  it("flushes on overflow so one page view cannot exceed the batch limit", async () => {
    const send = vi.fn().mockResolvedValue({ received: 0 });
    const queue = createCatalogEventQueue({
      send,
      visitorId: "v-1",
      maxBatch: 3,
    });

    for (let i = 0; i < 3; i += 1) queue.track(event(i));

    await vi.waitFor(() => expect(send).toHaveBeenCalledTimes(1));
    expect(send.mock.calls[0][1]).toHaveLength(3);
  });

  it("keeps events queued during an in-flight flush and sends them afterwards", async () => {
    let releaseFirst: (value: { received: number } | null) => void = () => {};
    const send = vi
      .fn()
      .mockImplementationOnce(
        () =>
          new Promise<{ received: number } | null>((resolve) => {
            releaseFirst = resolve;
          }),
      )
      .mockResolvedValue({ received: 1 });

    const queue = createCatalogEventQueue({ send, visitorId: "v-1" });

    queue.track(event(1));
    const flushing = queue.flush();

    queue.track(event(2));
    expect(queue.pending()).toBe(1);

    releaseFirst({ received: 1 });
    await flushing;

    expect(send).toHaveBeenCalledTimes(2);
    expect(send.mock.calls[1][1]).toHaveLength(1);
  });

  it("matches the backend batch limit", () => {
    expect(CATALOG_EVENT_MAX_BATCH).toBe(100);
  });
});
