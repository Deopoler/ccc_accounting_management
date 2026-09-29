// Noto Sans KR 가변 폰트(src/NotoSansKR-VF.ttf)에서 앱에 넣을 정적 폰트를 만든다.
//
//   * 현대 한글 음절 11,172자 전체 + 자모 전체(옛한글 포함) + 라틴 + 앱에서 쓰는 기호
//   * 한자(CJK 통합 한자)는 크기 때문에 뺀다. 필요하면 Flutter 웹이 자동으로 받아 채운다.
//   * 굵기별 정적 인스턴스(wght 고정)로 만든다. Flutter 웹은 등록된 폰트를 시작 시 모두 받으므로
//     보통(400) / 굵게(700) 두 가지만 넣는다. (500 은 400, 600 은 700 으로 그려진다)
//
// 사용법:  cd tool/fonts && npm install && npm run build
// 원본:    https://github.com/google/fonts/tree/main/ofl/notosanskr (SIL OFL 1.1)
import { copyFile, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import * as fontkit from 'fontkit';
import subsetFont from 'subset-font';

const here = dirname(fileURLToPath(import.meta.url));
const outDir = join(here, '..', '..', 'assets', 'fonts');

/** [시작, 끝] 코드포인트 범위 (끝 포함) */
const ranges = [
  [0x0020, 0x007e], // ASCII
  [0x00a0, 0x00ff], // Latin-1 보충 (·, ×, © 등)
  [0x1100, 0x11ff], // 한글 자모 (옛한글 포함)
  [0x2000, 0x206f], // 일반 구두점 (–, —, ‘’, “”, …, ※)
  [0x20a9, 0x20a9], // ₩
  [0x2100, 0x214f], // 글자꼴 기호 (№, ℃)
  [0x2150, 0x218f], // 숫자 꼴 (Ⅰ, ½)
  [0x2190, 0x21ff], // 화살표
  [0x2460, 0x24ff], // 원문자 (①)
  [0x2500, 0x257f], // 상자 그리기
  [0x25a0, 0x25ff], // 도형 (○, ●, □, ■, △)
  [0x2600, 0x26ff], // 기타 기호 (☆, ★)
  [0x3000, 0x303f], // CJK 기호와 구두점 (「」, 、。)
  [0x3130, 0x318f], // 한글 호환 자모 (ㄱ, ㅏ)
  [0x3200, 0x32ff], // 괄호·원 한글 (㈜)
  [0xa960, 0xa97f], // 한글 자모 확장 A
  [0xac00, 0xd7a3], // 현대 한글 음절 11,172자
  [0xd7b0, 0xd7ff], // 한글 자모 확장 B
  [0xff00, 0xffef], // 반각·전각 형태
];

const text = ranges
  .flatMap(([a, b]) => Array.from({ length: b - a + 1 }, (_, i) => String.fromCodePoint(a + i)))
  .join('');

/** 파일 이름 → 굵기 */
const weights = {
  'NotoSansKR-Regular.ttf': 400,
  'NotoSansKR-Bold.ttf': 700,
};

// 원본(약 10MB)은 저장소에 두지 않고 없으면 내려받는다.
const base = 'https://github.com/google/fonts/raw/main/ofl/notosanskr';
const srcDir = join(here, 'src');
await mkdir(srcDir, { recursive: true });
for (const [remote, local] of [['NotoSansKR%5Bwght%5D.ttf', 'NotoSansKR-VF.ttf'], ['OFL.txt', 'OFL.txt']]) {
  const path = join(srcDir, local);
  if (existsSync(path)) continue;
  console.log(`내려받는 중: ${local}`);
  const res = await fetch(`${base}/${remote}`);
  if (!res.ok) throw new Error(`${local} 다운로드 실패: ${res.status}`);
  await writeFile(path, Buffer.from(await res.arrayBuffer()));
}

const source = await readFile(join(srcDir, 'NotoSansKR-VF.ttf'));
await mkdir(outDir, { recursive: true });

for (const [file, wght] of Object.entries(weights)) {
  const out = await subsetFont(source, text, {
    targetFormat: 'truetype',
    variationAxes: { wght },
  });
  const path = join(outDir, file);
  await writeFile(path, out);
  const { size } = await stat(path);

  // 검증: 넣기로 한 글자가 모두 있어야 하고, 굵기가 고정된 정적 폰트여야 한다.
  const font = fontkit.create(out);
  const missing = [...text].filter((c) => !font.hasGlyphForCodePoint(c.codePointAt(0)));
  const missingHangul = missing.filter((c) => c >= '가' && c <= '힣');
  if (missingHangul.length > 0) {
    throw new Error(`${file}: 한글 음절 ${missingHangul.length}자 누락 (${missingHangul.slice(0, 10).join('')}…)`);
  }
  if (Object.keys(font.variationAxes ?? {}).length > 0) {
    throw new Error(`${file}: 가변축이 남아 있습니다.`);
  }
  console.log(
    `${file.padEnd(26)} wght=${wght}  ${(size / 1024 / 1024).toFixed(2)} MB  ` +
      `(한글 11,172자 모두 포함${missing.length ? `, 원본에 없는 기호 ${missing.length}개` : ''})`,
  );
}
// 폰트 라이선스(SIL OFL 1.1)는 폰트와 함께 배포한다.
await copyFile(join(srcDir, 'OFL.txt'), join(outDir, 'OFL.txt'));
console.log(`글자 수: ${[...text].length}`);
