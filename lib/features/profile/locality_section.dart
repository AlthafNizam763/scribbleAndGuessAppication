import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/features/profile/location_flow.dart';
import 'package:scribble_guess/models/social.dart';
import 'package:scribble_guess/providers/location_provider.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Where the player plays from, for the locality leaderboard.
///
/// ## Detected, not typed
///
/// The button does the work: one tap explains what location is for, asks the
/// system, reads a single coarse fix and fills in the town. Nobody has to
/// spell their own city or remember that Germany is `DE`, which is also what
/// stops the board fragmenting across "Köln", "Koln" and "Cologne" — the
/// device's geocoder answers with one spelling and an ISO country code.
///
/// The three text fields are still here, because a permission a player is
/// allowed to refuse is only genuinely refusable if refusing still gets them
/// what they came for. They start collapsed on a build that can detect, and
/// expanded on one that cannot — see `LocationService.isSupported`, which is
/// false on the web.
///
/// ## Why it saves itself rather than joining the profile form
///
/// The name and avatar are device-owned: they are written to preferences
/// first so a rename renders on the next frame, and pushed to the server
/// afterwards. The locality is not — it exists only server-side, because the
/// only thing that reads it is a leaderboard query. Folding it into the
/// profile save would mean one button whose two halves have different failure
/// modes, where a network error would have to either lose the rename or claim
/// the locality was saved when it was not.
///
/// So this is its own small form with its own save, and the profile screen
/// simply hosts it.
///
/// ## What it can and cannot store
///
/// A town, a region and a two-letter country code. There is no field for a
/// street or a postcode here, none on the endpoint, and none on the user
/// document — the same structural refusal the profile patch makes for scores.
/// Detection does not widen that by one field: `LocationService` discards the
/// coordinates it read before this widget is given anything.
class LocalitySection extends ConsumerStatefulWidget {
  /// Creates the locality section.
  const LocalitySection({super.key});

  @override
  ConsumerState<LocalitySection> createState() => _LocalitySectionState();
}

class _LocalitySectionState extends ConsumerState<LocalitySection> {
  final TextEditingController _city = TextEditingController();
  final TextEditingController _region = TextEditingController();
  final TextEditingController _country = TextEditingController();

  bool _detecting = false;
  bool _saving = false;
  bool _manualOpen = false;

  /// The locality the controllers were last filled from.
  ///
  /// Tracked so that a town arriving from detection, or from the first server
  /// read, refills the fields, while a rebuild that changed nothing leaves a
  /// player who is midway through typing one alone.
  Locality? _filledFrom;

  @override
  void initState() {
    super.initState();
    // The provider may already hold a town from an earlier visit to this
    // screen, in which case the listener registered in build never fires.
    _fill(ref.read(localityProvider).valueOrNull);
  }

  @override
  void dispose() {
    _city.dispose();
    _region.dispose();
    _country.dispose();
    super.dispose();
  }

  void _fill(Locality? locality) {
    _filledFrom = locality;
    _city.text = locality?.city ?? '';
    _region.text = locality?.region ?? '';
    _country.text = locality?.country ?? '';
  }

  bool _isDirty(Locality? saved) =>
      _city.text.trim() != (saved?.city ?? '') ||
      _region.text.trim() != (saved?.region ?? '') ||
      _country.text.trim().toUpperCase() != (saved?.country ?? '');

  // ----------------------------------------------------------- detection ---

  Future<void> _detect() async {
    if (_detecting) return;
    setState(() => _detecting = true);

    // A failure or a refusal opens the manual fields rather than leaving the
    // player looking at a button that just did not work.
    await runLocationUpdate(
      context,
      ref,
      onTypeInstead: () {
        if (mounted) setState(() => _manualOpen = true);
      },
    );

    if (mounted) setState(() => _detecting = false);
  }

  // -------------------------------------------------------------- manual ---

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);

    final Result<void> result =
        await ref.read(localityProvider.notifier).save(
              Locality(
                city: _city.text.trim(),
                region: _region.text.trim(),
                country: _country.text.trim().toUpperCase(),
              ),
            );

    if (!mounted) return;
    setState(() => _saving = false);

    switch (result) {
      case Ok<void>():
        notify(context, context.l10n.profileSaved);
      case Err<void>(:final Failure failure):
        notify(context, failure.userMessage, isError: true);
    }
  }

  Future<void> _clear() async {
    final bool yes = await confirm(
      context,
      title: context.l10n.locationClearTitle,
      message: context.l10n.locationClearBody,
      confirmLabel: context.l10n.locationClear,
      destructive: true,
    );
    if (!yes || !mounted) return;

    setState(() => _saving = true);
    final Result<void> result =
        await ref.read(localityProvider.notifier).save(null);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _manualOpen = false;
    });

    switch (result) {
      case Ok<void>():
        notify(context, context.l10n.locationCleared);
      case Err<void>(:final Failure failure):
        notify(context, failure.userMessage, isError: true);
    }
  }

  // ---------------------------------------------------------------- build ---

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    // Filling the controllers is done from a listener rather than from the
    // body below: writing to a TextEditingController notifies the TextField
    // watching it, and doing that partway through a build is how "setState
    // called during build" happens.
    ref.listen<AsyncValue<Locality?>>(localityProvider,
        (AsyncValue<Locality?>? _, AsyncValue<Locality?> next) {
      final Locality? town = next.valueOrNull;
      if (next.hasValue && town != _filledFrom) {
        setState(() => _fill(town));
      }
    });

    final AsyncValue<Locality?> async = ref.watch(localityProvider);
    final bool canDetect = ref.read(localityProvider.notifier).canDetect;

    if (async.isLoading && !async.hasValue) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final Locality? saved = async.valueOrNull;

    final bool busy = _detecting || _saving;
    // Nothing to detect with, so the fields are the only way in and start open.
    final bool manualVisible = _manualOpen || !canDetect;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(left: AppSpacing.xs),
          child: Text(
            context.l10n.localitySection.toUpperCase(),
            style: text.labelSmall?.copyWith(color: colors.inkSoft),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.xs,
            bottom: AppSpacing.sm,
          ),
          child: Text(
            context.l10n.localityHint,
            style: text.bodySmall?.copyWith(color: colors.inkSoft),
          ),
        ),
        SketchCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _CurrentTown(locality: saved),
              const SizedBox(height: AppSpacing.md),
              if (canDetect) ...<Widget>[
                SketchButton.primary(
                  label: _detecting
                      ? context.l10n.locationDetecting
                      : saved == null
                          ? context.l10n.locationUse
                          : context.l10n.locationUpdate,
                  icon: Icons.my_location,
                  busy: _detecting,
                  onPressed: busy ? null : _detect,
                ),
                const SizedBox(height: AppSpacing.sm),
                SketchButton(
                  label: manualVisible
                      ? context.l10n.locationHideManual
                      : context.l10n.locationEnterManually,
                  variant: SketchButtonVariant.ghost,
                  expand: true,
                  onPressed: busy
                      ? null
                      : () => setState(() => _manualOpen = !_manualOpen),
                ),
              ],
              if (manualVisible) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _city,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.l10n.localityCity,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _region,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.l10n.localityRegion,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _country,
                  maxLength: 2,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: context.l10n.localityCountry,
                    helperText: context.l10n.localityCountryHint,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                SketchButton(
                  label: context.l10n.save,
                  icon: Icons.location_on_outlined,
                  expand: true,
                  busy: _saving,
                  // Disabled until something changed, so the button cannot
                  // send a write that would do nothing.
                  onPressed: _isDirty(saved) && !busy ? _save : null,
                ),
              ],
              if (saved != null) ...<Widget>[
                const SizedBox(height: AppSpacing.sm),
                SketchButton(
                  label: context.l10n.locationClear,
                  variant: SketchButtonVariant.ghost,
                  expand: true,
                  onPressed: busy ? null : _clear,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// The town on file, or a plain "not set".
class _CurrentTown extends StatelessWidget {
  const _CurrentTown({required this.locality});

  final Locality? locality;

  @override
  Widget build(BuildContext context) {
    final SketchColors colors = context.sketch;
    final TextTheme text = Theme.of(context).textTheme;
    final bool isSet = locality != null;

    return Row(
      children: <Widget>[
        Icon(
          isSet ? Icons.place : Icons.place_outlined,
          size: AppSpacing.lg,
          color: isSet ? colors.ink : colors.inkFaint,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                context.l10n.locationCurrent.toUpperCase(),
                style: text.labelSmall?.copyWith(color: colors.inkSoft),
              ),
              Text(
                isSet ? locality!.display : context.l10n.locationNoneSet,
                style: text.bodyLarge?.copyWith(
                  color: isSet ? colors.ink : colors.inkSoft,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
