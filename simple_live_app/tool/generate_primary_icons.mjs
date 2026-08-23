// Fills every platform's *primary* launcher icon slot with the Modern
// (SimpleLive brand master) artwork, for both simple_live_app and
// simple_live_tv_app.
//
// The Modern-specific alternates (ic_launcher_simplelive*,
// AppIconSimpleLive.appiconset) are produced by generate_brand_masters.mjs and
// are intentionally left untouched here.
//
// Requires sharp. Run from simple_live_app:
//   node tool/generate_primary_icons.mjs

import { readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const sharp = require('sharp');

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(toolDirectory, '..');
const repoRoot = resolve(appDirectory, '..');
const tvDirectory = resolve(repoRoot, 'simple_live_tv_app');
const masterDirectory = resolve(
  appDirectory,
  'design',
  'simplelive-brand-master',
);

// The cream plate the brand master paints its background rect with.
const BRAND_BACKGROUND = '#F8F5EF';
const BRAND_BACKGROUND_RGB = { r: 0xf8, g: 0xf5, b: 0xef, alpha: 1 };

const [squareMaster, roundedMaster, foregroundMaster] = await Promise.all([
  readFile(resolve(masterDirectory, 'simplelive-master-1024.svg')),
  readFile(resolve(masterDirectory, 'simplelive-rounded-transparent-1024.svg')),
  readFile(resolve(masterDirectory, 'simplelive-android-foreground-1024.svg')),
]);

// Match the dark appearance configured in the Apple Icon Composer bundle.
// Keep this derived from the shared master so the in-app light and dark marks
// cannot drift apart as the artwork evolves.
const darkRoundedMaster = Buffer.from(
  roundedMaster
    .toString('utf8')
    .replaceAll('#F8F5EF', '#211E2F')
    .replaceAll('#725EF1', '#897AF5')
    .replaceAll('#5D4BDD', '#7867F0')
    .replaceAll('#FF806D', '#FF9A88'),
);

const written = [];

function record(path) {
  written.push(path.replace(repoRoot, '').replace(/^[\\/]/, ''));
}

/** Renders an SVG master to a square PNG buffer. */
function renderPng(source, size, { flatten = false } = {}) {
  let pipeline = sharp(source, { density: 384 }).resize(size, size, {
    fit: 'fill',
  });
  if (flatten) {
    pipeline = pipeline.flatten({ background: BRAND_BACKGROUND_RGB });
  }
  return pipeline.png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

/** Renders an SVG master centred on a transparent canvas at `scale`. */
async function renderInsetPng(source, size, scale) {
  const inner = Math.round(size * scale);
  const offset = Math.round((size - inner) / 2);
  const mark = await sharp(source, { density: 384 })
    .resize(inner, inner, { fit: 'fill' })
    .png()
    .toBuffer();
  return sharp({
    create: {
      width: size,
      height: size,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite([{ input: mark, left: offset, top: offset }])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

/** Renders an SVG master clipped to a circle — Android's legacy round slot. */
function renderCirclePng(source, size) {
  const mask = Buffer.from(
    `<svg width="${size}" height="${size}"><circle cx="${size / 2}" cy="${size / 2}" r="${size / 2}" fill="white"/></svg>`,
  );
  return sharp(source, { density: 384 })
    .resize(size, size, { fit: 'fill' })
    .composite([{ input: mask, blend: 'dest-in' }])
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer();
}

async function writePng(source, size, target, options) {
  await writeFile(target, await renderPng(source, size, options));
  record(target);
}

async function writeWebp(buffer, target) {
  await writeFile(
    target,
    await sharp(buffer).webp({ lossless: true }).toBuffer(),
  );
  record(target);
}

/**
 * Packs PNG payloads into an ICO container. Windows Vista and later read
 * PNG-compressed ICO entries directly, so no BMP re-encoding is needed.
 */
function buildIco(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(entries.length, 4);

  const directory = Buffer.alloc(16 * entries.length);
  let offset = header.length + directory.length;

  entries.forEach(({ size, data }, index) => {
    const at = index * 16;
    // 256 is encoded as 0 in the single-byte width/height fields.
    directory.writeUInt8(size >= 256 ? 0 : size, at);
    directory.writeUInt8(size >= 256 ? 0 : size, at + 1);
    directory.writeUInt8(0, at + 2); // palette count
    directory.writeUInt8(0, at + 3); // reserved
    directory.writeUInt16LE(1, at + 4); // colour planes
    directory.writeUInt16LE(32, at + 6); // bits per pixel
    directory.writeUInt32LE(data.length, at + 8);
    directory.writeUInt32LE(offset, at + 12);
    offset += data.length;
  });

  return Buffer.concat([
    header,
    directory,
    ...entries.map((entry) => entry.data),
  ]);
}

async function writeIco(source, sizes, target) {
  const entries = [];
  for (const size of sizes) {
    entries.push({ size, data: await renderPng(source, size) });
  }
  await writeFile(target, buildIco(entries));
  record(target);
}

async function writeColorXml(target, colors) {
  const body = Object.entries(colors)
    .map(([name, value]) => `    <color name="${name}">${value}</color>`)
    .join('\n');
  await writeFile(
    target,
    `<?xml version="1.0" encoding="utf-8"?>\n<resources>\n${body}\n</resources>\n`,
    'utf8',
  );
  record(target);
}

const ANDROID_DENSITIES = {
  mdpi: { launcher: 48, foreground: 108 },
  hdpi: { launcher: 72, foreground: 162 },
  xhdpi: { launcher: 96, foreground: 216 },
  xxhdpi: { launcher: 144, foreground: 324 },
  xxxhdpi: { launcher: 192, foreground: 432 },
};

function androidResDirectory(root, density) {
  return resolve(
    root,
    'android',
    'app',
    'src',
    'main',
    'res',
    `mipmap-${density}`,
  );
}

// --- simple_live_app : Android -------------------------------------------
for (const [density, sizes] of Object.entries(ANDROID_DENSITIES)) {
  const dir = androidResDirectory(appDirectory, density);
  await writeWebp(
    await renderPng(roundedMaster, sizes.launcher),
    resolve(dir, 'ic_launcher.webp'),
  );
  await writeWebp(
    await renderCirclePng(squareMaster, sizes.launcher),
    resolve(dir, 'ic_launcher_round.webp'),
  );
  await writeWebp(
    await renderPng(foregroundMaster, sizes.foreground),
    resolve(dir, 'ic_launcher_foreground.webp'),
  );
}

await writeColorXml(
  resolve(
    appDirectory,
    'android/app/src/main/res/values/ic_launcher_background.xml',
  ),
  {
    ic_launcher_background: BRAND_BACKGROUND,
    ic_launcher_simplelive_background: BRAND_BACKGROUND,
  },
);

// --- simple_live_app : iOS ------------------------------------------------
// iOS app icons must be fully opaque, so the square master is flattened.
const IOS_ICONS = {
  'icon-20@2x.png': 40,
  'icon-20@3x.png': 60,
  'icon-29.png': 29,
  'icon-29@2x.png': 58,
  'icon-29@3x.png': 87,
  'icon-40@2x.png': 80,
  'icon-40@3x.png': 120,
  'icon-60@2x.png': 120,
  'icon-60@3x.png': 180,
  'icon-20-ipad.png': 20,
  'icon-20@2x-ipad.png': 40,
  'icon-29-ipad.png': 29,
  'icon-29@2x-ipad.png': 58,
  'icon-40.png': 40,
  'icon-76.png': 76,
  'icon-76@2x.png': 152,
  'icon-83.5@2x.png': 167,
  'icon-1024.png': 1024,
};

const iosIconDirectory = resolve(
  appDirectory,
  'ios/Runner/Assets.xcassets/AppIcon.appiconset',
);
for (const [fileName, size] of Object.entries(IOS_ICONS)) {
  await writePng(squareMaster, size, resolve(iosIconDirectory, fileName), {
    flatten: true,
  });
}

// --- simple_live_app : macOS ---------------------------------------------
// flutter_launcher_icons insets macOS art by ~8.6% a side so the artwork sits
// inside Apple's squircle. Match that rather than bleeding to the edge.
const MACOS_ICONS = {
  'icon-16.png': 16,
  'icon-16@2x.png': 32,
  'icon-32.png': 32,
  'icon-32@2x.png': 64,
  'icon-128.png': 128,
  'icon-128@2x.png': 256,
  'icon-256.png': 256,
  'icon-256@2x.png': 512,
  'icon-512.png': 512,
  'icon-512@2x.png': 1024,
};

const macosIconDirectory = resolve(
  appDirectory,
  'macos/Runner/Assets.xcassets/AppIcon.appiconset',
);
for (const [fileName, size] of Object.entries(MACOS_ICONS)) {
  await writeFile(
    resolve(macosIconDirectory, fileName),
    await renderInsetPng(roundedMaster, size, 0.82),
  );
  record(resolve(macosIconDirectory, fileName));
}

// --- simple_live_app : Windows -------------------------------------------
await writeIco(
  roundedMaster,
  [16, 20, 24, 32, 40, 48, 64, 256],
  resolve(appDirectory, 'windows/runner/resources/app_icon.ico'),
);

// --- simple_live_app : shared assets ------------------------------------
// assets/logo.png feeds flutter_launcher_icons and the Linux packaging
// configs; assets/logo_400.png is the MSIX logo; assets/images/logo.png is the
// in-app mark and NetImage's empty-URL placeholder.
await writePng(
  roundedMaster,
  1024,
  resolve(appDirectory, 'assets/logo.png'),
);
await writePng(
  roundedMaster,
  1024,
  resolve(appDirectory, 'assets/logo_circle.png'),
);
await writePng(
  roundedMaster,
  400,
  resolve(appDirectory, 'assets/logo_400.png'),
);
await writePng(
  roundedMaster,
  512,
  resolve(appDirectory, 'assets/images/logo.png'),
);
await writePng(
  darkRoundedMaster,
  512,
  resolve(appDirectory, 'assets/images/logo_dark.png'),
);

// --- simple_live_tv_app : Android ---------------------------------------
const TV_DENSITIES = { ldpi: 36, ...Object.fromEntries(
  Object.entries(ANDROID_DENSITIES).map(([d, s]) => [d, s.launcher]),
) };

for (const [density, size] of Object.entries(TV_DENSITIES)) {
  await writeFile(
    resolve(androidResDirectory(tvDirectory, density), 'ic_launcher.png'),
    await renderPng(roundedMaster, size),
  );
  record(resolve(androidResDirectory(tvDirectory, density), 'ic_launcher.png'));
}

// The TV banner is a 320x180 plate with a 108x108 mark centred on it.
const BANNER = { width: 320, height: 180, mark: 108 };
const bannerMark = await sharp(roundedMaster, { density: 384 })
  .resize(BANNER.mark, BANNER.mark, { fit: 'fill' })
  .png()
  .toBuffer();
const bannerComposite = [
  {
    input: bannerMark,
    left: Math.round((BANNER.width - BANNER.mark) / 2),
    top: Math.round((BANNER.height - BANNER.mark) / 2),
  },
];
const tvBannerDirectory = androidResDirectory(tvDirectory, 'xhdpi');

await writeFile(
  resolve(tvBannerDirectory, 'ic_banner_foreground.png'),
  await sharp({
    create: {
      width: BANNER.width,
      height: BANNER.height,
      channels: 4,
      background: { r: 0, g: 0, b: 0, alpha: 0 },
    },
  })
    .composite(bannerComposite)
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer(),
);
record(resolve(tvBannerDirectory, 'ic_banner_foreground.png'));

await writeFile(
  resolve(tvBannerDirectory, 'ic_banner.png'),
  await sharp({
    create: {
      width: BANNER.width,
      height: BANNER.height,
      channels: 4,
      background: BRAND_BACKGROUND_RGB,
    },
  })
    .composite(bannerComposite)
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toBuffer(),
);
record(resolve(tvBannerDirectory, 'ic_banner.png'));

await writeColorXml(
  resolve(tvDirectory, 'android/app/src/main/res/values/ic_banner_background.xml'),
  { ic_banner_background: BRAND_BACKGROUND },
);

// --- simple_live_tv_app : Windows + assets ------------------------------
await writeIco(
  roundedMaster,
  [16, 32, 48, 256],
  resolve(tvDirectory, 'windows/runner/resources/app_icon.ico'),
);
await writePng(
  roundedMaster,
  512,
  resolve(tvDirectory, 'assets/images/logo.png'),
);

console.log(`Filled ${written.length} primary icon slots with Modern art:`);
for (const path of written) {
  console.log(`  ${path}`);
}
