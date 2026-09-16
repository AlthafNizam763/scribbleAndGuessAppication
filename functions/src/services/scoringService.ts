import { SCORING } from '../config/constants';

/**
 * Turns the facts of a round into points (section 28).
 *
 * Pure and deterministic: it reads no clock and touches no database, so every
 * branch is directly testable. All scoring happens here and nowhere else, and
 * it only ever runs inside a Cloud Function — a client's claim about its own
 * score is never even parsed, let alone trusted (section 50).
 */

/** The tunable balance. Injectable so tests can pin exact numbers. */
export interface ScoringConfig {
  maxGuessPoints: number;
  minGuessPoints: number;
  orderBonuses: number[];
  drawerPointsPerGuess: number;
  drawerAllGuessedBonus: number;
  drawerMaxPoints: number;
  difficultyMultiplier: Record<string, number>;
}

/** The balance the shipped game uses. */
export const standardScoring: ScoringConfig = {
  maxGuessPoints: SCORING.maxGuessPoints,
  minGuessPoints: SCORING.minGuessPoints,
  orderBonuses: [...SCORING.orderBonuses],
  drawerPointsPerGuess: SCORING.drawerPointsPerGuess,
  drawerAllGuessedBonus: SCORING.drawerAllGuessedBonus,
  drawerMaxPoints: SCORING.drawerMaxPoints,
  difficultyMultiplier: { ...SCORING.difficultyMultiplier },
};

/** Arguments for a single guesser's award. */
export interface GuesserPointsArgs {
  /** Milliseconds left on the clock when the guess landed. */
  msRemaining: number;
  /** Length of the whole turn, in milliseconds. */
  msTotal: number;
  /** 1-based position among this turn's correct guessers. */
  guessOrder: number;
  difficulty: string;
}

/** Arguments for the drawer's award. */
export interface DrawerPointsArgs {
  correctGuessers: number;
  /** Players eligible to guess this turn: everyone but the drawer. */
  totalGuessers: number;
  difficulty: string;
}

export class ScoringService {
  constructor(private readonly config: ScoringConfig = standardScoring) {}

  /**
   * Points for a player who guessed the word.
   *
   * The time component scales linearly from `minGuessPoints` (no clock left)
   * to `maxGuessPoints` (full clock); an order bonus rewards the first few
   * correct guesses; the difficulty multiplier is applied last. Nonsensical
   * input is coerced rather than thrown on, and the result is never negative.
   */
  guesserPoints({
    msRemaining,
    msTotal,
    guessOrder,
    difficulty,
  }: GuesserPointsArgs): number {
    const ratio = timeRatio(msRemaining, msTotal);
    const span = this.config.maxGuessPoints - this.config.minGuessPoints;
    const timeComponent = this.config.minGuessPoints + span * ratio;

    const order = Math.max(1, toInt(guessOrder));
    const orderBonus = this.config.orderBonuses[order - 1] ?? 0;

    const total =
      (timeComponent + orderBonus) * this.multiplierFor(difficulty);
    return Math.max(0, roundHalfAwayFromZero(total));
  }

  /**
   * Points for the drawer of a turn.
   *
   * Every correct guesser is worth `drawerPointsPerGuess`, scaled by
   * difficulty; a bonus lands when nobody was left behind; the total is capped
   * so a huge room cannot make drawing worth more than playing. A turn nobody
   * guessed is worth nothing, which is what stops a drawer scribbling
   * nonsense for easy points.
   */
  drawerPoints({
    correctGuessers,
    totalGuessers,
    difficulty,
  }: DrawerPointsArgs): number {
    const correct = toInt(correctGuessers);
    const total = toInt(totalGuessers);
    if (total <= 0 || correct <= 0) return 0;

    const guessed = Math.min(correct, total);
    const earned =
      this.config.drawerPointsPerGuess *
      guessed *
      this.multiplierFor(difficulty);
    const sum =
      guessed >= total ? earned + this.config.drawerAllGuessedBonus : earned;

    const points = Math.max(0, roundHalfAwayFromZero(sum));
    return Math.min(points, Math.max(0, this.config.drawerMaxPoints));
  }

  /** The multiplier for `difficulty`, defaulting to 1.0 when unmapped. */
  private multiplierFor(difficulty: string): number {
    const value = this.config.difficultyMultiplier[difficulty];
    return typeof value === 'number' && Number.isFinite(value) ? value : 1.0;
  }
}

/** Fraction of the clock still left, clamped to `[0, 1]`. */
function timeRatio(msRemaining: number, msTotal: number): number {
  const remaining = toInt(msRemaining);
  const total = toInt(msTotal);
  if (total <= 0 || remaining <= 0) return 0;
  return remaining >= total ? 1 : remaining / total;
}

/**
 * Rounds to the nearest integer, away from zero on a tie.
 *
 * `Math.round` breaks ties towards +Infinity, which disagrees with Dart's
 * `double.round()` for negative halves. Matching Dart matters because the
 * client renders a predicted score before the server's number arrives.
 */
export function roundHalfAwayFromZero(value: number): number {
  if (!Number.isFinite(value)) return 0;
  return value < 0 ? -Math.round(-value) : Math.round(value);
}

/** Coerces to a finite integer. */
function toInt(value: unknown): number {
  const n = Number(value);
  return Number.isFinite(n) ? Math.trunc(n) : 0;
}

/** The instance the game engine scores with. */
export const scoring = new ScoringService();
