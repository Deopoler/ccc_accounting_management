const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
const MIN_VALID_TS_MS = Date.UTC(2020, 0, 1);

// Offset-less date-time strings (`YYYY-MM-DD`, `YYYY/MM/DD`, `YYYY.MM.DD` + `HH:mm[:ss[.fff]]`)
// are treated as Asia/Seoul (+09:00).
const OFFSETLESS_LOCAL_TS =
  /^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})[T ](\d{1,2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?$/;

// Strict ISO-8601 date-time with an explicit timezone offset (`Z` or `±HH:MM` / `±HHMM`).
const EXPLICIT_TZ_ISO =
  /^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,6}))?)?(Z|[+-]\d{2}:?\d{2})$/i;

export function getClientIp(headers: Headers): string {
  const cf = headers.get('cf-connecting-ip')?.trim();
  if (cf) return cf;
  const forwarded = headers.get('x-forwarded-for');
  if (forwarded) {
    const parts = forwarded
      .split(',')
      .map((p) => p.trim())
      .filter((p) => p.length > 0);
    if (parts.length > 0) return parts[parts.length - 1];
  }
  return 'unknown';
}

export async function sha256Hex(input: string): Promise<string> {
  const bytes = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

export function normalizeForHash(input: string): string {
  return input.normalize('NFC').replace(/\r\n?/g, '\n').trim();
}

function isValidCalendarDate(year: number, month: number, day: number): boolean {
  if (month < 1 || month > 12 || day < 1 || day > 31) return false;
  const d = new Date(Date.UTC(year, month - 1, day));
  return (
    d.getUTCFullYear() === year &&
    d.getUTCMonth() === month - 1 &&
    d.getUTCDate() === day
  );
}

function pad2(n: number): string {
  return String(n).padStart(2, '0');
}

export function parseIngestTimestamp(
  raw: unknown,
  now: Date,
): { date: Date; supplied: boolean } {
  if (raw === undefined || raw === null || raw === '') {
    return { date: now, supplied: false };
  }

  let ms: number | null = null;
  if (typeof raw === 'number' && Number.isFinite(raw)) {
    ms = raw >= 1e12 ? raw : raw >= 1e9 ? raw * 1000 : null;
  } else if (typeof raw === 'string') {
    const trimmed = raw.trim();
    if (/^\d+$/.test(trimmed)) {
      const n = Number(trimmed);
      ms = n >= 1e12 ? n : n >= 1e9 ? n * 1000 : null;
    } else {
      const localMatch = trimmed.match(OFFSETLESS_LOCAL_TS);
      if (localMatch) {
        const year = Number(localMatch[1]);
        const month = Number(localMatch[2]);
        const day = Number(localMatch[3]);
        const hour = Number(localMatch[4]);
        const minute = Number(localMatch[5]);
        const second = localMatch[6] ? Number(localMatch[6]) : 0;
        const frac = localMatch[7] ? `.${localMatch[7].slice(0, 3)}` : '';
        if (
          isValidCalendarDate(year, month, day) &&
          hour <= 23 &&
          minute <= 59 &&
          second <= 59
        ) {
          const iso = `${year}-${pad2(month)}-${pad2(day)}T${pad2(hour)}:${pad2(minute)}:${pad2(second)}${frac}+09:00`;
          const parsed = Date.parse(iso);
          if (!Number.isNaN(parsed)) ms = parsed;
        }
      } else {
        const isoMatch = trimmed.match(EXPLICIT_TZ_ISO);
        if (isoMatch) {
          const year = Number(isoMatch[1]);
          const month = Number(isoMatch[2]);
          const day = Number(isoMatch[3]);
          const hour = Number(isoMatch[4]);
          const minute = Number(isoMatch[5]);
          const second = isoMatch[6] ? Number(isoMatch[6]) : 0;
          const frac = isoMatch[7] ? `.${isoMatch[7].slice(0, 3)}` : '';
          const rawTz = isoMatch[8].toUpperCase();
          const tz =
            rawTz === 'Z' || rawTz.includes(':')
              ? rawTz
              : `${rawTz.slice(0, 3)}:${rawTz.slice(3)}`;
          if (
            isValidCalendarDate(year, month, day) &&
            hour <= 23 &&
            minute <= 59 &&
            second <= 59
          ) {
            const iso = `${year}-${pad2(month)}-${pad2(day)}T${pad2(hour)}:${pad2(minute)}:${pad2(second)}${frac}${tz}`;
            const parsed = Date.parse(iso);
            if (!Number.isNaN(parsed)) ms = parsed;
          }
        }
      }
    }
  }

  if (ms === null || ms < MIN_VALID_TS_MS || ms > now.getTime() + MAX_FUTURE_SKEW_MS) {
    return { date: now, supplied: false };
  }
  return { date: new Date(ms), supplied: true };
}

export async function computeDedupeHashes(params: {
  appPackage: string;
  title: string;
  text: string;
  externalId: string;
  depositedAt: Date;
  tsSupplied: boolean;
  uniqueNonce?: string;
}): Promise<{ rawHash: string; dedupeKey: string }> {
  const normTitle = normalizeForHash(params.title);
  const normText = normalizeForHash(params.text);
  const rawHash = await sha256Hex(`${params.appPackage}|${normTitle}|${normText}`);

  if (params.externalId) {
    // Include rawHash so reusing externalId for different notifications never silently drops a deposit.
    const dedupeKey = await sha256Hex(`${params.externalId}|${rawHash}`);
    return { rawHash, dedupeKey };
  }
  if (params.tsSupplied) {
    const epochSec = Math.floor(params.depositedAt.getTime() / 1000);
    const dedupeKey = await sha256Hex(`${rawHash}|${epochSec}`);
    return { rawHash, dedupeKey };
  }
  const nonce = params.uniqueNonce ?? crypto.randomUUID();
  const dedupeKey = await sha256Hex(`${rawHash}|srv:${nonce}`);
  return { rawHash, dedupeKey };
}
