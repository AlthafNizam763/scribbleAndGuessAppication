import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:scribble_guess/providers/core_providers.dart';
import 'package:scribble_guess/providers/room_controller.dart';
import 'package:scribble_guess/services/quick_play_service.dart';

/// Quick Play.
///
/// The service is built from `RoomController.prepare`, so the Play button and
/// the ordinary create/join buttons establish a session and a socket in
/// exactly the same way. That is the whole reason this provider is not just a
/// `QuickPlayService()`: there must be one definition of "connected" in the
/// app, and it is the room controller's.
final Provider<QuickPlayService> quickPlayServiceProvider =
    Provider<QuickPlayService>((Ref ref) {
  final RoomController controller = ref.watch(roomControllerProvider);

  final QuickPlayService service = QuickPlayService(
    gateway: ref.watch(gatewayProvider),
    connect: controller.prepare,
  );

  ref.onDispose(service.dispose);
  return service;
});

/// What Quick Play is doing, for the button's label and spinner.
///
/// Falls back to the service's own last stage rather than to [
/// QuickPlayStage.idle] so a widget that subscribes mid-flight shows the stage
/// already in progress instead of briefly claiming nothing is happening.
final StreamProvider<QuickPlayStage> quickPlayStageProvider =
    StreamProvider<QuickPlayStage>(
  (Ref ref) => ref.watch(quickPlayServiceProvider).stages,
);

/// Quick Play's stage as a plain value, for widgets that cannot await.
final Provider<QuickPlayStage> quickPlayProvider = Provider<QuickPlayStage>(
  (Ref ref) =>
      ref.watch(quickPlayStageProvider).valueOrNull ??
      ref.watch(quickPlayServiceProvider).stage,
);
