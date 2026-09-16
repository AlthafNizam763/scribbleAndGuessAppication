import 'package:scribble_guess/core/utils/result.dart';
import 'package:scribble_guess/data/api/api_client.dart';
import 'package:scribble_guess/models/app_notification.dart';
import 'package:scribble_guess/models/json_utils.dart';

/// `GET/PATCH/DELETE /api/notifications`.
///
/// The transport for the notification centre. Like [SocialApi] it owns no
/// rules: whether a row is the caller's, whether it was already read, and what
/// the unread count now is are all decided by the server.
///
/// Note what is missing: there is no `create`. Notifications are written by
/// the server from events that already happened, so there is no method here
/// that could put a row in an inbox — including the local player's own.
///
/// Every method returns the server's unread count rather than a success flag,
/// because that count is what the badge draws. The client never derives it by
/// arithmetic on its last value: a push missed while the app was backgrounded
/// would make that permanently wrong.
///
/// Nothing throws.
class NotificationsApi {
  /// Creates the API over [client].
  const NotificationsApi(this._client);

  final ApiClient _client;

  /// One page of the local player's inbox, newest first.
  ///
  /// [unreadOnly] narrows it to the backlog, which is what the filter chip on
  /// the notifications screen sends.
  Future<Result<NotificationPage>> list({
    int page = 1,
    int limit = 25,
    bool unreadOnly = false,
  }) async {
    final Result<Map<String, dynamic>> response = await _client.get(
      '/api/notifications',
      query: <String, String>{
        'page': '$page',
        'limit': '$limit',
        if (unreadOnly) 'unreadOnly': 'true',
      },
    );

    return response.map(NotificationPage.fromJson);
  }

  /// Marks one row read. Returns the new unread count.
  ///
  /// Marking an already-read row is a no-op rather than an error — a player
  /// taps a notification they have already opened all the time.
  Future<Result<int>> markRead(String notificationId) async {
    final Result<Map<String, dynamic>> response =
        await _client.patch('/api/notifications/$notificationId/read');

    return response.map((Map<String, dynamic> data) => asInt(data['unreadCount']));
  }

  /// Clears the whole backlog. Returns the new unread count, always zero.
  Future<Result<int>> markAllRead() async {
    final Result<Map<String, dynamic>> response =
        await _client.patch('/api/notifications/read-all');

    return response.map((Map<String, dynamic> data) => asInt(data['unreadCount']));
  }

  /// Deletes one row. Returns the new unread count.
  Future<Result<int>> remove(String notificationId) async {
    final Result<Map<String, dynamic>> response =
        await _client.delete('/api/notifications/$notificationId');

    return response.map((Map<String, dynamic> data) => asInt(data['unreadCount']));
  }
}
