/**
 * Tiny levelled logger. No dependencies, no configuration files.
 *
 * Levels, in increasing severity: `debug`, `info`, `warn`, `error`, `silent`.
 * Anything below the active level is dropped before the message is formatted,
 * so debug logging costs nothing in production.
 */

const LEVELS = Object.freeze({
  debug: 10,
  info: 20,
  warn: 30,
  error: 40,
  silent: 100,
});

/** Normalizes an arbitrary value to a known level name. */
export function normalizeLevel(value, fallback = 'info') {
  const name = String(value ?? '').trim().toLowerCase();
  return Object.prototype.hasOwnProperty.call(LEVELS, name) ? name : fallback;
}

/** A logger bound to a level and an optional scope prefix. */
export class Logger {
  /**
   * @param {{level?: string, scope?: string, sink?: Console}} [options]
   */
  constructor(options = {}) {
    this.level = normalizeLevel(options.level, 'info');
    this.scope = options.scope ? String(options.scope) : '';
    this.sink = options.sink ?? console;
  }

  /** Returns a child logger that prefixes every line with `scope`. */
  child(scope) {
    const prefix = this.scope ? `${this.scope}:${scope}` : String(scope);
    return new Logger({ level: this.level, scope: prefix, sink: this.sink });
  }

  /** Changes the active level in place. */
  setLevel(level) {
    this.level = normalizeLevel(level, this.level);
  }

  /** Whether a message at `level` would be emitted. */
  enabled(level) {
    return LEVELS[normalizeLevel(level, 'info')] >= LEVELS[this.level];
  }

  debug(...args) {
    this.#write('debug', args);
  }

  info(...args) {
    this.#write('info', args);
  }

  warn(...args) {
    this.#write('warn', args);
  }

  error(...args) {
    this.#write('error', args);
  }

  #write(level, args) {
    if (!this.enabled(level)) return;
    const stamp = new Date().toISOString();
    const tag = this.scope ? `[${level.toUpperCase()}][${this.scope}]` : `[${level.toUpperCase()}]`;
    const method = level === 'debug' ? 'log' : level;
    const fn = typeof this.sink[method] === 'function' ? this.sink[method] : this.sink.log;
    fn.call(this.sink, stamp, tag, ...args);
  }
}

/** The process-wide logger. Level comes from `LOG_LEVEL`. */
export const logger = new Logger({ level: process.env.LOG_LEVEL ?? 'info' });

export default logger;
