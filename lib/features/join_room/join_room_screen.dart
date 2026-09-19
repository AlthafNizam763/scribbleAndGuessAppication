import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:scribble_guess/core/constants/app_constants.dart';
import 'package:scribble_guess/core/errors/failure.dart';
import 'package:scribble_guess/core/i18n/app_text.dart';
import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/core/utils/validators.dart';
import 'package:scribble_guess/models/room.dart';
import 'package:scribble_guess/providers/providers.dart';
import 'package:scribble_guess/routes/route_names.dart';
import 'package:scribble_guess/theme/theme.dart';
import 'package:scribble_guess/widgets/widgets.dart';

/// Room code entry.
class JoinRoomScreen extends ConsumerStatefulWidget {
  const JoinRoomScreen({super.key});

  @override
  ConsumerState<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends ConsumerState<JoinRoomScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _joining = false;
  String? _error;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _pasteCode() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String? text = data?.text;
    if (text == null || !mounted) {
      return;
    }
    setState(() {
      _codeController.text = Validators.normalizeRoomCode(text);
      _error = null;
    });
  }

  Future<void> _join() async {
    final String code = Validators.normalizeRoomCode(_codeController.text);
    final String? problem = Validators.roomCode(code);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _joining = true;
      _error = null;
    });

    final Result<Room> result =
        await ref.read(roomControllerProvider).joinRoom(code);

    if (!mounted) {
      return;
    }
    setState(() => _joining = false);

    result.fold(
      (Room room) => context.goNamed(AppRoutes.lobby),
      (Failure failure) => setState(() => _error = failure.message),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppPalette colors = context.palette;
    final TextTheme text = Theme.of(context).textTheme;

    return AppScaffold(
      title: context.l10n.joinTitle,
      banner: const ConnectionBanner(),
      bottom: AppButton.primary(
        label: context.l10n.joinSubmit,
        icon: Icons.login,
        busy: _joining,
        onPressed: _join,
      ),
      child: ListView(
        padding: pagePadding(context),
        children: <Widget>[
          const SizedBox(height: AppSpacing.xl),
          Text(
            context.l10n.joinCodeLabel,
            textAlign: TextAlign.center,
            style: text.titleMedium?.copyWith(color: colors.text),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            context.l10n.joinCodeHelp,
            textAlign: TextAlign.center,
            style: text.bodyMedium?.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _codeController,
            autofocus: true,
            enabled: !_joining,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            maxLength: AppConstants.roomCodeLength,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => _join(),
            onChanged: (_) {
              if (_error != null) {
                setState(() => _error = null);
              }
            },
            inputFormatters: <TextInputFormatter>[
              // Codes are a fixed alphabet; filtering as the player types
              // beats rejecting the whole thing on submit.
              FilteringTextInputFormatter.allow(
                RegExp('[${AppConstants.roomCodeAlphabet}]', caseSensitive: false),
              ),
              LengthLimitingTextInputFormatter(AppConstants.roomCodeLength),
              TextInputFormatter.withFunction(
                (TextEditingValue old, TextEditingValue next) => next.copyWith(
                  text: next.text.toUpperCase(),
                ),
              ),
            ],
            style: text.displaySmall?.copyWith(
              color: colors.text,
              letterSpacing: 8,
            ),
            decoration: InputDecoration(
              hintText: context.l10n.joinCodeHint,
              counterText: '',
              // Both sources of this text — the validators and `Failure` —
              // are built without a context, so they arrive in English and
              // are localised here, where they are shown.
              errorText: _error == null ? null : context.l10n.fromEnglish(_error!),
              hintStyle: text.displaySmall?.copyWith(
                color: colors.textFaint,
                letterSpacing: 8,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Center(
            child: AppButton(
              label: context.l10n.joinPaste,
              icon: Icons.content_paste,
              variant: AppButtonVariant.ghost,
              onPressed: _joining ? null : _pasteCode,
            ),
          ),
        ],
      ),
    );
  }
}
