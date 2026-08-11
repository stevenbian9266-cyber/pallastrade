import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("@/lib/pallastrade", () => ({
  getAccessToken: vi.fn(),
  isJwtExpired: vi.fn(),
}));

import { getAccessToken, isJwtExpired } from "@/lib/pallastrade";
import { isAuthenticated } from "../cookies";

beforeEach(() => {
  vi.mocked(getAccessToken).mockReset();
  vi.mocked(isJwtExpired).mockReset();
});

describe("isAuthenticated", () => {
  it("returns false when there is no access token", async () => {
    vi.mocked(getAccessToken).mockResolvedValue(undefined);
    expect(await isAuthenticated()).toBe(false);
    expect(isJwtExpired).not.toHaveBeenCalled();
  });

  it("returns false when the token is expired", async () => {
    vi.mocked(getAccessToken).mockResolvedValue("jwt-token");
    vi.mocked(isJwtExpired).mockReturnValue(true);
    expect(await isAuthenticated()).toBe(false);
    expect(isJwtExpired).toHaveBeenCalledWith("jwt-token", 30);
  });

  it("returns true when the token is present and not expired", async () => {
    vi.mocked(getAccessToken).mockResolvedValue("jwt-token");
    vi.mocked(isJwtExpired).mockReturnValue(false);
    expect(await isAuthenticated()).toBe(true);
  });
});
