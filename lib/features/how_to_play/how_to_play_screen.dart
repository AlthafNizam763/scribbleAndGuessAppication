import 'package:flutter/material.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// The rules, as a scrollable list of illustrated beats.
class HowToPlayScreen extends StatelessWidget {
  const HowToPlayScreen({super.key});

  /// Each rule, in the order a new player meets them.
  static List<({IconData icon, String title, String body})> _rulesFor(
    AppText l10n,
  ) => <({IconData icon, String title, String body})>[
    (
      icon: Icons.groups_outlined,
      title: l10n.howToPlayTurnsTitle,
      body: l10n.howToPlayTurnsBody,
    ),
    (
      icon: Icons.spellcheck,
      title: l10n.howToPlayWordTitle,
      body: l10n.howToPlayWordBody,
    ),
    (
      icon: Icons.brush_outlined,
      title: l10n.howToPlayDrawTitle,
      body: l10n.howToPlayDrawBody,
    ),
    (
      icon: Icons.chat_bubble_outline,
      title: l10n.howToPlayGuessTitle,
      body: l10n.howToPlayGuessBody,
    ),
    (
      icon: Icons.emoji_events_outlined,
      title: l10n.howToPlayScoreTitle,
      body: l10n.howToPlayScoreBody,
    ),
    (
      icon: Icons.lightbulb_outline,
      title: l10n.howToPlayHintTitle,
      body: l10n.howToPlayHintBody,
    ),
    (
      icon: Icons.handshake_outlined,
      title: l10n.howToPlayFairTitle,
      body: l10n.howToPlayFairBody,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final List<({IconData icon, String title, String body})> rules = _rulesFor(
      context.l10n,
    );

    return SketchScaffold(
      title: context.l10n.howToPlayTitle,
      child: ListView.separated(
        padding: pagePadding(context),
        itemCount: rules.length + 1,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text(
                context.l10n.howToPlayIntro,
                style: text.bodyLarge?.copyWith(color: colors.inkSoft),
              ),
            );
          }

          final ({IconData icon, String title, String body}) rule =
              rules[index - 1];
          return SketchCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  height: 40,
                  width: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: colors.accentAt(index),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colors.ink,
                      width: AppSpacing.border,
                    ),
                  ),
                  child: Icon(rule.icon, size: 20, color: colors.ink),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        rule.title,
                        style: text.titleSmall?.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        rule.body,
                        style: text.bodyMedium?.copyWith(color: colors.inkSoft),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
