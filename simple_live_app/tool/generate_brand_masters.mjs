import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const sharp = require('sharp');

const toolDirectory = dirname(fileURLToPath(import.meta.url));
const appDirectory = resolve(toolDirectory, '..');
const sourceDirectory = resolve(
  appDirectory,
  'design',
  'simplelive-liquid-glass',
);
const outputDirectory = resolve(
  appDirectory,
  'design',
  'simplelive-brand-master',
);

const previewSource = await readFile(
  resolve(sourceDirectory, 'preview.svg'),
  'utf8',
);
const wordmarkSource = await readFile(
  resolve(sourceDirectory, 'layers', '08-simplelive-wordmark.svg'),
  'utf8',
);

function svgInnerMarkup(source) {
  return source
    .replace(/^\s*<svg\b[^>]*>/, '')
    .replace(/<\/svg>\s*$/, '')
    .trim();
}

const inlinedPreview = previewSource
  .replace(
    /<image\s+href="layers\/08-simplelive-wordmark\.svg"[^>]*\/>/,
    `<g id="simplelive-wordmark">\n${svgInnerMarkup(wordmarkSource)}\n  </g>`,
  )
  .replace(
    'SimpleLive Liquid Glass layered icon preview',
    'SimpleLive cross-platform master icon',
  );

const originalDefs = inlinedPreview.match(/<defs>[\s\S]*?<\/defs>/)?.[0];
if (!originalDefs) {
  throw new Error('The preview SVG does not contain a defs block.');
}

const originalBody = svgInnerMarkup(inlinedPreview)
  .replace(/\s*<title>[\s\S]*?<\/title>\s*/, '')
  .replace(originalDefs, '')
  .trim();
const foregroundBody = originalBody
  .replace(/<rect\s+width="1024"\s+height="1024"\s+fill="#F8F5EF"\s*\/?>/, '')
  .trim();

const roundedMaster = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>SimpleLive rounded transparent master icon</title>
  ${originalDefs.replace(
    '</defs>',
    '  <clipPath id="simplelive-rounded-mask"><rect width="1024" height="1024" rx="224"/></clipPath>\n  </defs>',
  )}
  <g clip-path="url(#simplelive-rounded-mask)">
    ${originalBody}
  </g>
</svg>
`;

// Adaptive icons need extra room for system masks and launcher motion. Scaling the
// complete foreground to 75% retains the wordmark and live signal under common masks.
const androidForeground = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <title>SimpleLive Android adaptive foreground master</title>
  ${originalDefs}
  <g transform="translate(128 128) scale(.75)">
    ${foregroundBody}
  </g>
</svg>
`;

const masters = [
  ['simplelive-master-1024.svg', inlinedPreview],
  ['simplelive-rounded-transparent-1024.svg', roundedMaster],
  ['simplelive-android-foreground-1024.svg', androidForeground],
];

await mkdir(outputDirectory, { recursive: true });

for (const [svgName, svgSource] of masters) {
  const svgPath = resolve(outputDirectory, svgName);
  const pngPath = svgPath.replace(/\.svg$/, '.png');
  await writeFile(svgPath, svgSource, 'utf8');
  await sharp(Buffer.from(svgSource))
    .resize(1024, 1024, { fit: 'fill' })
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(pngPath);
}

const squareBuffer = Buffer.from(inlinedPreview);
const roundedBuffer = Buffer.from(roundedMaster);
const foregroundBuffer = Buffer.from(androidForeground);

await sharp(roundedBuffer)
  .resize(256, 256)
  .png({ compressionLevel: 9, adaptiveFiltering: true })
  .toFile(resolve(appDirectory, 'assets', 'images', 'app_icon_simplelive.png'));

const androidDensities = {
  mdpi: { launcher: 48, foreground: 108 },
  hdpi: { launcher: 72, foreground: 162 },
  xhdpi: { launcher: 96, foreground: 216 },
  xxhdpi: { launcher: 144, foreground: 324 },
  xxxhdpi: { launcher: 192, foreground: 432 },
};

for (const [density, sizes] of Object.entries(androidDensities)) {
  const mipmapDirectory = resolve(
    appDirectory,
    'android',
    'app',
    'src',
    'main',
    'res',
    `mipmap-${density}`,
  );
  await mkdir(mipmapDirectory, { recursive: true });

  await sharp(roundedBuffer)
    .resize(sizes.launcher, sizes.launcher)
    .webp({ lossless: true })
    .toFile(resolve(mipmapDirectory, 'ic_launcher_simplelive.webp'));

  const circleMask = Buffer.from(
    `<svg width="${sizes.launcher}" height="${sizes.launcher}"><circle cx="${sizes.launcher / 2}" cy="${sizes.launcher / 2}" r="${sizes.launcher / 2}" fill="white"/></svg>`,
  );
  await sharp(squareBuffer)
    .resize(sizes.launcher, sizes.launcher)
    .composite([{ input: circleMask, blend: 'dest-in' }])
    .webp({ lossless: true })
    .toFile(resolve(mipmapDirectory, 'ic_launcher_simplelive_round.webp'));

  await sharp(foregroundBuffer)
    .resize(sizes.foreground, sizes.foreground)
    .webp({ lossless: true })
    .toFile(resolve(mipmapDirectory, 'ic_launcher_simplelive_foreground.webp'));
}

const iosIcons = {
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
  'ios',
  'Runner',
  'Assets.xcassets',
  'AppIconSimpleLive.appiconset',
);
await mkdir(iosIconDirectory, { recursive: true });
for (const [fileName, size] of Object.entries(iosIcons)) {
  await sharp(squareBuffer)
    .resize(size, size)
    .removeAlpha()
    .png({ compressionLevel: 9, adaptiveFiltering: true })
    .toFile(resolve(iosIconDirectory, fileName));
}

console.log(
  `Generated ${masters.length} master pairs, app preview, Android launcher resources, and iOS alternate icons.`,
);
