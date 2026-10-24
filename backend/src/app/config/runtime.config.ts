export function readBoolean(name: string, fallback: boolean) {
  const value = Reflect.get(process.env, name);
  if (value == null) return fallback;
  return ['1', 'true', 'yes', 'on'].includes(value.trim().toLowerCase());
}

export function readNumber(name: string, fallback: number) {
  const value = Number(Reflect.get(process.env, name));
  return Number.isFinite(value) && value > 0 ? value : fallback;
}

export function readStringList(name: string, fallback: string[] = []) {
  const raw = Reflect.get(process.env, name)?.trim();
  if (!raw) return fallback;

  return raw
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
}

export function readTimezone() {
  return process.env.APP_TIMEZONE?.trim() || 'UTC';
}

export function formatDateInTimezone(date: Date, timeZone = readTimezone()) {
  try {
    return new Intl.DateTimeFormat('sv-SE', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hour12: false,
    }).format(date);
  } catch {
    return date.toISOString();
  }
}

interface RequestSecurityConfig {
  requestIdHeader: string;
  requestTimestampHeader: string;
  maxAgeMs: number;
  freshnessEnabled: boolean;
  freshnessSafeMethods: boolean;
}

let _requestSecurityConfig: RequestSecurityConfig | null = null;

export function getRequestSecurityConfig(): RequestSecurityConfig {
  if (_requestSecurityConfig) return _requestSecurityConfig;

  _requestSecurityConfig = {
    requestIdHeader: (
      process.env.REQUEST_ID_HEADER ?? 'x-request-id'
    ).toLowerCase(),
    requestTimestampHeader: (
      process.env.REQUEST_TIMESTAMP_HEADER ?? 'x-request-timestamp'
    ).toLowerCase(),
    maxAgeMs: readNumber('REQUEST_MAX_AGE_MS', 5 * 60 * 1000),
    freshnessEnabled: readBoolean('REQUEST_FRESHNESS_ENABLED', true),
    freshnessSafeMethods: readBoolean('REQUEST_FRESHNESS_SAFE_METHODS', false),
  };
  return _requestSecurityConfig;
}
