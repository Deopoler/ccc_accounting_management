const MAX_FUTURE_SKEW_MS = 5 * 60 * 1000;
const MIN_VALID_TS_MS = Date.UTC(2020, 0, 1);

// Matches ISO-like date-time without an explicit timezone offset (interpreted as Asia/Seoul).
const OFFSETLESS_ISO =
  /^(\d{4}-\d{2}-\d{2})[T ](\d{2}:\d{2}(?::\d{2}(?:\.\d{1,6})?)?)$/;

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
      const offsetless = trimmed.match(OFFSETLESS_ISO);
      if (offsetless) {
        const timePart = offsetless[2].length === 5 ? `${offsetless[2]}:00` : offsetless[2];
        const parsed = Date.parse(`${offsetless[1]}T${timePart}+09:00`);
        if (!Number.isNaN(parsed)) ms = parsed;
      } else {
        const parsed = Date.parse(trimmed);
        if (!Number.isNaN(parsed)) ms = parsed;
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
