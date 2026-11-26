// Pretendard 가변 폰트에서 2단계 로딩용 정적 폰트(기본 Core + 확장 Ext)를 만든다.
//
//   * Core (Pretendard-Regular/Bold.ttf): KS X 1001 상용 한글 2,350자 + 자모·라틴·기호.
//     pubspec.yaml 의 fonts 에 등록해 앱 시작 시 먼저 받는다.
//   * Ext (PretendardExt-Regular/Bold.ttf): 나머지 현대 한글 음절 8,822자 (11,172 - 2,350).
//     첫 화면이 그려진 뒤 FontLoader 로 백그라운드에서 내려받아 대체 폰트로 붙인다.
//   * 폰트를 다시 생성하면 lib/core/theme/font_loader.dart 의 extFontCacheName 버전을 함께 올린다.
//   * 굵기별 정적 인스턴스(wght 400, 700 고정)로 만들고, 생성 뒤 음절 포함 여부와 크기를 검증한다.
//
// 사용법:  cd tool/fonts && npm install && npm run build
// 원본:    https://github.com/orioncactus/pretendard (SIL OFL 1.1), npm 패키지 pretendard
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as fontkit from 'fontkit';
import subsetFont from 'subset-font';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', 'assets', 'fonts');

const version = '1.3.9';
const cdn = `https://cdn.jsdelivr.net/npm/pretendard@${version}/dist`;
const sources = {
  'PretendardVariable.ttf': `${cdn}/public/variable/PretendardVariable.ttf`,
  'Pretendard-LICENSE.txt': `${cdn}/LICENSE.txt`,
};

/** 굵기별 출력 파일 이름 (core / ext 쌍) */
const weights = [
  { wght: 400, core: 'Pretendard-Regular.ttf', ext: 'PretendardExt-Regular.ttf' },
  { wght: 700, core: 'Pretendard-Bold.ttf', ext: 'PretendardExt-Bold.ttf' },
];

/** [시작, 끝] 코드포인트 범위 (끝 포함, 현대 한글 음절 0xAC00~0xD7A3 제외) */
const nonSyllableRanges = [
  [0x0020, 0x007e], // ASCII
  [0x00a0, 0x00ff], // Latin-1 보충 (·, ×, © 등)
  [0x1100, 0x11ff], // 한글 자모 (원본에 있는 것만)
  [0x2000, 0x206f], // 일반 구두점 (–, —, ‘’, “”, …, ※)
  [0x20a9, 0x20a9], // ₩
  [0x2100, 0x214f], // 글자꼴 기호 (№, ℃)
  [0x2150, 0x218f], // 숫자 꼴 (Ⅰ, ½)
  [0x2190, 0x21ff], // 화살표
  [0x2460, 0x24ff], // 원문자 (①)
  [0x25a0, 0x25ff], // 도형 (○, ●, □, ■, △)
  [0x2600, 0x26ff], // 기타 기호 (☆, ★)
  [0x3000, 0x303f], // CJK 기호와 구두점 (「」, 、。)
  [0x3130, 0x318f], // 한글 호환 자모 (ㄱ, ㅏ)
  [0x3200, 0x32ff], // 괄호·원 한글 (㈜)
  [0xa960, 0xa97f], // 한글 자모 확장 A
  [0xd7b0, 0xd7ff], // 한글 자모 확장 B
  [0xff00, 0xffef], // 반각·전각 형태
];

const HANGUL_START = 0xac00;
const HANGUL_END = 0xd7a3;
const TOTAL_HANGUL_SYLLABLES = HANGUL_END - HANGUL_START + 1; // 11,172
const KSX1001_SYLLABLE_COUNT = 2350;

/** EUC-KR 완성형 한글 영역(lead 0xB0..0xC8 × trail 0xA1..0xFE)에서 KS X 1001 2,350자를 구한다. */
function buildKsx1001Set() {
  const decoder = new TextDecoder('euc-kr');
  const set = new Set();
  for (let lead = 0xb0; lead <= 0xc8; lead++) {
    for (let trail = 0xa1; trail <= 0xfe; trail++) {
      const ch = decoder.decode(Uint8Array.of(lead, trail));
      if (ch === '\ufffd') continue;
      const cp = ch.codePointAt(0);
      if (cp >= HANGUL_START && cp <= HANGUL_END) {
        set.add(cp);
      }
    }
  }
  if (set.size !== KSX1001_SYLLABLE_COUNT) {
    throw new Error(`KS X 1001 음절 수 불일치: ${set.size} (기대: ${KSX1001_SYLLABLE_COUNT})`);
  }
  return set;
}

const ksx1001Set = buildKsx1001Set();
const extSet = new Set();
for (let cp = HANGUL_START; cp <= HANGUL_END; cp++) {
  if (!ksx1001Set.has(cp)) extSet.add(cp);
}

const nonSyllableCps = nonSyllableRanges.flatMap(([a, b]) =>
  Array.from({ length: b - a + 1 }, (_, i) => a + i),
);
const coreText = [...nonSyllableCps, ...ksx1001Set].map((cp) => String.fromCodePoint(cp)).join('');
const extText = [...extSet].map((cp) => String.fromCodePoint(cp)).join('');

// 원본은 저장소에 두지 않고 없으면 내려받는다.
const srcDir = join(here, 'src');
await mkdir(srcDir, { recursive: true });
for (const [local, url] of Object.entries(sources)) {
  const path = join(srcDir, local);
  if (existsSync(path)) continue;
  console.log(`내려받는 중: ${local}`);
  const res = await fetch(url);
  if (!res.ok) throw new Error(`${local} 다운로드 실패: ${res.status}`);
  await writeFile(path, Buffer.from(await res.arrayBuffer()));
}

const source = await readFile(join(srcDir, 'PretendardVariable.ttf'));
const sourceFont = fontkit.create(source);
const expectedNonSyllableCps = nonSyllableCps.filter((cp) => sourceFont.hasGlyphForCodePoint(cp));
await mkdir(outDir, { recursive: true });

function assertStatic(font, file) {
  if (Object.keys(font.variationAxes ?? {}).length > 0) {
    throw new Error(`${file}: 가변축이 남아 있습니다.`);
  }
}

function formatSize(bytes) {
  return `${(bytes / 1024).toFixed(1)} KB (${(bytes / 1024 / 1024).toFixed(2)} MB)`;
}

for (const { wght, core, ext } of weights) {
  const coreBuf = await subsetFont(source, coreText, {
    targetFormat: 'truetype',
    variationAxes: { wght },
  });
  const corePath = join(outDir, core);
  await writeFile(corePath, coreBuf);
  const coreStat = await stat(corePath);
  const coreFont = fontkit.create(coreBuf);
  assertStatic(coreFont, core);

  const missingNonSyllable = expectedNonSyllableCps.filter(
    (cp) => !coreFont.hasGlyphForCodePoint(cp),
  );
  if (missingNonSyllable.length > 0) {
    throw new Error(`${core}: 기본 범위 ${missingNonSyllable.length}자 누락`);
  }

  const coreSyllables = new Set();
  for (let cp = HANGUL_START; cp <= HANGUL_END; cp++) {
    if (coreFont.hasGlyphForCodePoint(cp)) coreSyllables.add(cp);
  }
  const missingKsx = [...ksx1001Set].filter((cp) => !coreSyllables.has(cp));
  const extraCoreSyllables = [...coreSyllables].filter((cp) => !ksx1001Set.has(cp));
  if (missingKsx.length > 0 || extraCoreSyllables.length > 0) {
    throw new Error(
      `${core}: KS X 1001 음절 불일치 (누락 ${missingKsx.length}, 초과 ${extraCoreSyllables.length})`,
    );
  }

  const extBuf = await subsetFont(source, extText, {
    targetFormat: 'truetype',
    variationAxes: { wght },
  });
  const extPath = join(outDir, ext);
  await writeFile(extPath, extBuf);
  const extStat = await stat(extPath);
  const extFont = fontkit.create(extBuf);
  assertStatic(extFont, ext);

  const extSyllables = new Set();
  for (let cp = HANGUL_START; cp <= HANGUL_END; cp++) {
    if (extFont.hasGlyphForCodePoint(cp)) extSyllables.add(cp);
  }
  const missingExt = [...extSet].filter((cp) => !extSyllables.has(cp));
  const overlap = [...extSyllables].filter((cp) => ksx1001Set.has(cp));
  if (missingExt.length > 0 || overlap.length > 0) {
    throw new Error(
      `${ext}: 확장 음절 불일치 (누락 ${missingExt.length}, 중복 ${overlap.length})`,
    );
  }

  const union = new Set([...coreSyllables, ...extSyllables]);
  if (union.size !== TOTAL_HANGUL_SYLLABLES) {
    throw new Error(`wght=${wght}: core ∪ ext 음절 수 ${union.size} (기대: ${TOTAL_HANGUL_SYLLABLES})`);
  }

  console.log(
    `${core.padEnd(28)} wght=${wght}  ${formatSize(coreStat.size)}  (KS X 1001 ${coreSyllables.size}자 + 기호 ${expectedNonSyllableCps.length}자)`,
  );
  console.log(
    `${ext.padEnd(28)} wght=${wght}  ${formatSize(extStat.size)}  (확장 음절 ${extSyllables.size}자, 전체 ${union.size}자 검증 완료)`,
  );
}

// 폰트 라이선스(SIL OFL 1.1)는 폰트와 함께 배포한다.
await writeFile(join(outDir, 'Pretendard-LICENSE.txt'), await readFile(join(srcDir, 'Pretendard-LICENSE.txt')));
