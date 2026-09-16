/**
 * Faithful port of lib/domain/rules/scoring.dart.
 *
 * Every number and every branch matches the Dart original so that client side
 * prediction and server truth agree to the point. Pure and deterministic.
 */

/** Difficulty multipliers. Mirrors `ScoringConfig.defaultDifficultyMultiplier`. */
export const DEFAULT_DIFFICULTY_MULTIPLIER = Object.freeze({
  easy: 1.0,
  medium: 1.15,
  hard: 1.35,
});

/**
 * Rounds like Dart's `double.round()`: to the nearest integer, away from zero
 * on a tie. `Math.round` rounds ties towards +Infinity, which differs for
 * negative halves, so it is not enough on its own.
 */
export function roundHalfAwayFromZero(value) {
  if (!Number.isFinite(value)) return 0;
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/** Tunable numbers behind every point award of a turn. `ScoringConfig`. */
export class ScoringConfig {
  /**
   * @param {Partial<ScoringConfig>} [overrides] fields to replace.
   */
  constructor(overrides = {}) {
    /** Award for a guesser who answers with the whole clock still left. */
    this.maxGuessPoints = 100;
    /** Award for a guesser who answers as the clock runs out. */
    this.minGuessPoints = 30;
    /** Extra points for the first correct guess of a turn. */
    this.firstGuessBonus = 25;
    /** Extra points for the second correct guess of a turn. */
    this.secondGuessBonus = 15;
    /** Extra points for the third correct guess of a turn. */
    this.thirdGuessBonus = 8;
    /** Points the drawer earns for every player who guessed the word. */
    this.drawerPointsPerGuess = 20;
    /** Extra points for a drawer whose word everybody guessed. */
    this.drawerAllGuessedBonus = 30;
    /** Ceiling on what a drawer can earn in a single turn. */
    this.drawerMaxPoints = 120;
    /** Multiplier applied last to every award, keyed by word difficulty. */
    this.difficultyMultiplier = { ...DEFAULT_DIFFICULTY_MULTIPLIER };
    Object.assign(this, overrides);
  }

  /** The multiplier for `difficulty`, defaulting to 1.0 when unmapped. */
  multiplierFor(difficulty) {
    const value = this.difficultyMultiplier?.[difficulty];
    return typeof value === 'number' && Number.isFinite(value) ? value : 1.0;
  }
}

/** The balance the shipped game uses. `ScoringConfig.standard`. */
ScoringConfig.standard = new ScoringConfig();

/** Turns the facts of a turn into points. Pure, deterministic, injectable. */
export class ScoringService {
  /**
   * @param {ScoringConfig} [config] the balance to score with.
   */
  constructor(config = ScoringConfig.standard) {
    this.config = config;
  }

  /**
   * Points awarded to a player who guessed the word.
   *
   * The time component scales linearly from `minGuessPoints` (no time left)
   * to `maxGuessPoints` (full clock), an order bonus is added for the first
   * three correct guesses, and the difficulty multiplier is applied last.
   * Nonsensical input is coerced rather than thrown on, and the result is
   * never negative.
   *
   * @param {{msRemaining: number, msTotal: number, guessOrder: number, difficulty: string}} args
   * @returns {number}
   */
  guesserPoints({ msRemaining, msTotal, guessOrder, difficulty }) {
    const ratio = timeRatio(msRemaining, msTotal);
    const span = this.config.maxGuessPoints - this.config.minGuessPoints;
    const timeComponent = this.config.minGuessPoints + span * ratio;
    const order = toInt(guessOrder) < 1 ? 1 : toInt(guessOrder);
    let orderBonus = 0;
    if (order === 1) orderBonus = this.config.firstGuessBonus;
    else if (order === 2) orderBonus = this.config.secondGuessBonus;
    else if (order === 3) orderBonus = this.config.thirdGuessBonus;
    const total = (timeComponent + orderBonus) * this.config.multiplierFor(difficulty);
    return atLeastZero(roundHalfAwayFromZero(total));
  }

  /**
   * Points awarded to the drawer of a turn.
   *
   * Every correct guesser is worth `drawerPointsPerGuess`, the whole reward
   * is scaled by the difficulty multiplier, the all-guessed bonus lands on
   * top when nobody was left behind, and the total is capped at
   * `drawerMaxPoints`. A turn nobody guessed is worth nothing.
   *
   * @param {{correctGuessers: number, totalGuessers: number, difficulty: string}} args
   * @returns {number}
   */
  drawerPoints({ correctGuessers, totalGuessers, difficulty }) {
    const correct = toInt(correctGuessers);
    const total = toInt(totalGuessers);
    if (total <= 0 || correct <= 0) return 0;
    const guessed = correct > total ? total : correct;
    const earned = this.config.drawerPointsPerGuess * guessed * this.config.multiplierFor(difficulty);
    const sum = guessed >= total ? earned + this.config.drawerAllGuessedBonus : earned;
    const points = atLeastZero(roundHalfAwayFromZero(sum));
    const cap = atLeastZero(this.config.drawerMaxPoints);
    return points > cap ? cap : points;
  }
}

/** Fraction of the clock still left, clamped to 0..1. */
function timeRatio(msRemaining, msTotal) {
  const remaining = toInt(msRemaining);
  const total = toInt(msTotal);
  if (total <= 0 || remaining <= 0) return 0;
  return remaining >= total ? 1 : remaining / total;
}

/** `value` with negatives folded to zero. */
function atLeastZero(value) {
  return value < 0 ? 0 : value;
}

/** Coerces to a finite integer, mirroring the defensiveness of the Dart side. */
function toInt(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.trunc(number) : 0;
}

/** The shared service instance the game engine scores with. */
export const scoring = new ScoringService(ScoringConfig.standard);

export default scoring;
