/**
 * Per-socket token buckets.
 *
 * Each socket owns one `RateLimiter` holding one bucket per class of event
 * (chat, draw, room actions, time pings). A bucket refills continuously at
 * `refillPerSec` and bursts up to `capacity`; when it runs dry the event is
 * dropped rather than queued, which is exactly what an abusive client should
 * get. There are no timers involved: refill is computed lazily on read, so a
 * disconnected socket costs nothing.
 */

import { config } from './config.js';

/** One continuously refilling token bucket. */
export class TokenBucket {
  /**
   * @param {{capacity: number, refillPerSec: number, now?: () => number}} options
   */
  constructor({ capacity, refillPerSec, now = Date.now }) {
    this.capacity = Math.max(1, Number(capacity) || 1);
    this.refillPerSec = Math.max(0.01, Number(refillPerSec) || 1);
    this.now = now;
    this.tokens = this.capacity;
    this.updatedAt = this.now();
    /** How many events this bucket has dropped, for /stats. */
    this.dropped = 0;
  }

  /** Refills according to elapsed wall time. */
  #refill() {
    const at = this.now();
    const elapsedMs = at - this.updatedAt;
    if (elapsedMs <= 0) return;
    this.updatedAt = at;
    this.tokens = Math.min(this.capacity, this.tokens + (elapsedMs / 1000) * this.refillPerSec);
  }

  /**
   * Spends one token.
   * @returns {boolean} true when the caller may proceed.
   */
  take(cost = 1) {
    this.#refill();
    if (this.tokens < cost) {
      this.dropped++;
      return false;
    }
    this.tokens -= cost;
    return true;
  }

  /** Tokens currently available, for tests and diagnostics. */
  available() {
    this.#refill();
    return this.tokens;
  }
}

/** The buckets one socket is limited by. */
export class RateLimiter {
  /**
   * @param {{rate?: object, now?: () => number}} [options]
   */
  constructor({ rate = config.rate, now = Date.now } = {}) {
    this.buckets = new Map();
    for (const [name, spec] of Object.entries(rate)) {
      this.buckets.set(name, new TokenBucket({ ...spec, now }));
    }
    this.fallback = new TokenBucket({ capacity: 20, refillPerSec: 10, now });
  }

  /**
   * Whether an event of class `name` may run right now.
   * Unknown classes fall back to a conservative shared bucket.
   */
  allow(name, cost = 1) {
    const bucket = this.buckets.get(name) ?? this.fallback;
    return bucket.take(cost);
  }

  /** Total events dropped across every bucket. */
  droppedCount() {
    let total = this.fallback.dropped;
    for (const bucket of this.buckets.values()) total += bucket.dropped;
    return total;
  }
}

/** Creates the limiter a freshly connected socket gets. */
export function createLimiter(now = Date.now) {
  return new RateLimiter({ rate: config.rate, now });
}

export default { TokenBucket, RateLimiter, createLimiter };
