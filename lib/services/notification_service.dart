import 'package:cloud_firestore/cloud_firestore.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.createdAt,
  });

  factory AppNotification.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final createdAt = data['createdAt'];
    final title = data['title'];
    final body = data['body'];

    return AppNotification(
      id: document.id,
      title: title is String && title.isNotEmpty ? title : 'Notification',
      body: body is String && body.isNotEmpty ? body : 'No additional details.',
      createdAt: createdAt is Timestamp ? createdAt.toDate() : null,
    );
  }
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();
  static const int _maxNotifications = 30;

  Stream<List<AppNotification>> watchForRecipient(String recipientUid) {
    return FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientUid', isEqualTo: recipientUid)
        .limit(_maxNotifications)
        .snapshots()
        .map((snapshot) {
          final notifications =
              snapshot.docs.map(AppNotification.fromDocument).toList();
          notifications.sort((first, second) {
            final firstDate = first.createdAt;
            final secondDate = second.createdAt;
            if (firstDate == null) return secondDate == null ? 0 : 1;
            if (secondDate == null) return -1;
            return secondDate.compareTo(firstDate);
          });
          return notifications;
        });
  }
}
