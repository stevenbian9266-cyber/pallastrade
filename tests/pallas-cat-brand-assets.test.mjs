import assert from "node:assert/strict";
import { readFile, readdir, stat } from "node:fs/promises";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import sharp from "sharp";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const assetDir = path.join(repoRoot, "pallastrade-brand-assets");
const prdId = "PRD-20260809-catalog-创建兔狲品牌图片资源套件";

const expectedAssets = [
  "favicon-16x16.png",
  "favicon-32x32.png",
  "favicon-48x48.png",
  "favicon.ico",
  "pallastrade-logo-email.png",
  "pallastrade-logo.svg",
  "pallastrade-og.png",
];

async function cornerAlpha(file) {
  const pixel = await sharp(file)
    .ensureAlpha()
    .extract({ left: 0, top: 0, width: 1, height: 1 })
    .raw()
    .toBuffer();
  return pixel[3];
}

function readIcoSizes(buffer) {
  assert.equal(buffer.readUInt16LE(0), 0);
  assert.equal(buffer.readUInt16LE(2), 1);
  const count = buffer.readUInt16LE(4);
  return Array.from({ length: count }, (_, index) => {
    const offset = 6 + index * 16;
    const width = buffer[offset] || 256;
    const height = buffer[offset + 1] || 256;
    return [width, height];
  }).sort((left, right) => left[0] - right[0]);
}

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-001
test(`${prdId}: delivery folder contains the complete image set`, async () => {
  const actual = (await readdir(assetDir)).sort();
  assert.deepEqual(actual, expectedAssets);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-002
test(`${prdId}: shared SVG is a transparent 90x32 vector source`, async () => {
  const svg = await readFile(path.join(assetDir, "pallastrade-logo.svg"), "utf8");
  assert.match(svg, /<svg[\s\S]*?width="90"[\s\S]*?height="32"/);
  assert.match(svg, /viewBox="0 0 281\.25 100"/);
  assert.match(svg, />PallasTrade<\/text>/);
  assert.doesNotMatch(svg, /<image\b/);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-003
test(`${prdId}: email logo is transparent 225x80 PNG below 200KB`, async () => {
  const file = path.join(assetDir, "pallastrade-logo-email.png");
  const [metadata, fileStat, alpha] = await Promise.all([
    sharp(file).metadata(),
    stat(file),
    cornerAlpha(file),
  ]);
  assert.deepEqual([metadata.width, metadata.height], [225, 80]);
  assert.equal(metadata.hasAlpha, true);
  assert.equal(alpha, 0);
  assert.ok(fileStat.size <= 200_000, `email logo is ${fileStat.size} bytes`);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-004
test(`${prdId}: Open Graph image is an opaque 1200x630 PNG`, async () => {
  const file = path.join(assetDir, "pallastrade-og.png");
  const [metadata, alpha] = await Promise.all([
    sharp(file).metadata(),
    cornerAlpha(file),
  ]);
  assert.deepEqual([metadata.width, metadata.height], [1200, 630]);
  assert.equal(metadata.format, "png");
  assert.equal(alpha, 255);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-005
test(`${prdId}: favicon PNGs and ICO contain 16, 32 and 48 pixel sizes`, async () => {
  for (const size of [16, 32, 48]) {
    const metadata = await sharp(
      path.join(assetDir, `favicon-${size}x${size}.png`),
    ).metadata();
    assert.deepEqual([metadata.width, metadata.height], [size, size]);
  }
  const ico = await readFile(path.join(assetDir, "favicon.ico"));
  assert.deepEqual(readIcoSizes(ico), [
    [16, 16],
    [32, 32],
    [48, 48],
  ]);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-006
test(`${prdId}: 16px mark preserves opaque silhouette and accent contrast`, async () => {
  const { data, info } = await sharp(path.join(assetDir, "favicon-16x16.png"))
    .ensureAlpha()
    .raw()
    .toBuffer({ resolveWithObject: true });
  let opaquePixels = 0;
  let darkPixels = 0;
  let amberPixels = 0;
  const colors = new Set();
  for (let offset = 0; offset < data.length; offset += info.channels) {
    const [red, green, blue, alpha] = data.subarray(offset, offset + 4);
    if (alpha < 96) continue;
    opaquePixels += 1;
    colors.add(`${red},${green},${blue},${alpha}`);
    if (red < 85 && green < 85 && blue < 85) darkPixels += 1;
    if (red > 160 && green > 95 && blue < 95) amberPixels += 1;
  }
  assert.ok(opaquePixels >= 90, `only ${opaquePixels} opaque pixels remain`);
  assert.ok(darkPixels >= 10, `only ${darkPixels} dark outline pixels remain`);
  assert.ok(amberPixels >= 2, `only ${amberPixels} amber eye pixels remain`);
  assert.ok(colors.size >= 20, `only ${colors.size} visible colors remain`);
});

// PRD-20260809-catalog-创建兔狲品牌图片资源套件 AC-007
test(`${prdId}: delivery remains isolated from existing storefront assets`, async () => {
  for (const name of expectedAssets) {
    const relative = path.relative(repoRoot, path.join(assetDir, name));
    assert.ok(relative.startsWith(`pallastrade-brand-assets${path.sep}`));
  }
  const currentStorefrontLogo = await readFile(
    path.join(repoRoot, "storefront", "public", "pallastrade-logo.svg"),
    "utf8",
  );
  assert.doesNotMatch(currentStorefrontLogo, /pallas-cat-mark/);
});
