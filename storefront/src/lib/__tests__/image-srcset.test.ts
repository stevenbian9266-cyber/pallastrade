import { describe, expect, it } from "vitest";
import { buildImageSrcSet } from "@/lib/image-srcset";

describe("buildImageSrcSet", () => {
  it("builds a srcset from available sized URLs", () => {
    const media = {
      small_url: "https://cdn.example.com/small.webp",
      medium_url: "https://cdn.example.com/medium.webp",
      large_url: "https://cdn.example.com/large.webp",
      xlarge_url: "https://cdn.example.com/xlarge.webp",
    };

    expect(buildImageSrcSet(media)).toBe(
      "https://cdn.example.com/small.webp 256w, " +
        "https://cdn.example.com/medium.webp 400w, " +
        "https://cdn.example.com/large.webp 720w, " +
        "https://cdn.example.com/xlarge.webp 2000w",
    );
  });

  it("skips missing sized URLs", () => {
    const media = {
      small_url: null,
      medium_url: "https://cdn.example.com/medium.webp",
      large_url: null,
      xlarge_url: "https://cdn.example.com/xlarge.webp",
    };

    expect(buildImageSrcSet(media)).toBe(
      "https://cdn.example.com/medium.webp 400w, " +
        "https://cdn.example.com/xlarge.webp 2000w",
    );
  });

  it("returns undefined for null media", () => {
    expect(buildImageSrcSet(null)).toBeUndefined();
    expect(buildImageSrcSet(undefined)).toBeUndefined();
  });

  it("returns undefined when no sized URLs are present", () => {
    const media = {
      small_url: null,
      medium_url: null,
      large_url: null,
      xlarge_url: null,
    };
    expect(buildImageSrcSet(media)).toBeUndefined();
  });
});
