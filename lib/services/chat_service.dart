import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The delivery state used by the chat UI for outgoing messages.
enum ChatMessageStatus { sending, sent, delivered, read }

enum ChatServiceFailure {
  unauthenticated,
  unauthorized,
  notFound,
  invalidArgument,
  failedPrecondition,
  unavailable,
  unknown,
}

class ChatServiceException implements Exception {
  const ChatServiceException(this.failure, [this.message]);

  final ChatServiceFailure failure;
  final String? message;

  @override
  String toString() =>
      'ChatServiceException(${failure.name}${message == null ? '' : ': $message'})';
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.createdAt,
    this.deliveredAt,
    this.readAt,
  });

  final String id;
  final String senderUid;
  final String text;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? readAt;

  ChatMessageStatus get status {
    if (readAt != null) return ChatMessageStatus.read;
    if (deliveredAt != null) return ChatMessageStatus.delivered;
    return ChatMessageStatus.sent;
  }

  factory ChatMessage.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return ChatMessage(
      id: document.id,
      senderUid: data['senderUid'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: _dateTimeFrom(data['createdAt']),
      deliveredAt: _dateTimeFrom(data['deliveredAt']),
      readAt: _dateTimeFrom(data['readAt']),
    );
  }
}

class ChatMessageCursor {
  const ChatMessageCursor._(this.document);

  final DocumentSnapshot<Map<String, dynamic>> document;
}

class ChatPage<T, C> {
  const ChatPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  final List<T> items;
  final C? nextCursor;
  final bool hasMore;
}

/// Firestore-backed chat for request conversations.
///
/// Conversations are keyed by request ID and messages are stored under
/// `conversations/{requestId}/messages`. Firestore rules remain the authority
/// for participant authorization and constrain message and receipt fields.
class ChatService {
  ChatService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    this.pageSize = 30,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _auth = auth ?? FirebaseAuth.instance {
    if (pageSize < 1 || pageSize > 100) {
      throw ArgumentError.value(pageSize, 'pageSize', 'Must be between 1 and 100.');
    }
  }

  static final ChatService instance = ChatService();

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;
  final int pageSize;

  CollectionReference<Map<String, dynamic>> _messages(String requestId) =>
      _firestore
          .collection('conversations')
          .doc(requestId)
          .collection('messages');

  /// Creates the immutable conversation record for an accepted request.
  /// Either participant may make the record; Firestore rules validate the
  /// request status, participant roles, and authorization.
  Future<void> ensureConversation(String requestId) async {
    final uid = _requireUser();
    if (requestId.trim().isEmpty) {
      throw const ChatServiceException(
        ChatServiceFailure.invalidArgument,
        'A request ID is required.',
      );
    }

    try {
      final requestRef = _firestore.collection('requests').doc(requestId);
      final requestSnapshot = await requestRef.get();
      final request = requestSnapshot.data();
      if (!requestSnapshot.exists || request == null) {
        throw const ChatServiceException(
          ChatServiceFailure.notFound,
          'The request does not exist.',
        );
      }

      final agentUid = request['agentUid'];
      final loUid = request['loUid'];
      if (agentUid is! String || loUid is! String ||
          (uid != agentUid && uid != loUid)) {
        throw const ChatServiceException(
          ChatServiceFailure.unauthorized,
          'The signed-in user is not a participant in this request.',
        );
      }
      if (request['status'] != 'accepted') {
        throw const ChatServiceException(
          ChatServiceFailure.failedPrecondition,
          'Chat is available only for accepted requests.',
        );
      }

      final conversationRef = _firestore
          .collection('conversations')
          .doc(requestId);
      final existing = await conversationRef.get();
      if (existing.exists) {
        _validateConversation(existing.data(), requestId, agentUid, loUid);
        return;
      }

      try {
        await conversationRef.set({
          'requestId': requestId,
          'agentUid': agentUid,
          'loUid': loUid,
          'participantUids': [agentUid, loUid],
          'createdAt': FieldValue.serverTimestamp(),
        });
      } on FirebaseException {
        // A concurrent participant may have created it. Accept only the
        // exact expected participant mapping; never overwrite a conversation.
        final createdByOther = await conversationRef.get();
        if (!createdByOther.exists) rethrow;
        _validateConversation(
          createdByOther.data(),
          requestId,
          agentUid,
          loUid,
        );
      }
    } on ChatServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _convertFirebaseError(error);
    } catch (error) {
      throw ChatServiceException(ChatServiceFailure.unknown, error.toString());
    }
  }

  Stream<ChatPage<ChatMessage, ChatMessageCursor>> watchLatestMessages(
    String requestId,
  ) {
    _requireUser();
    return _messages(requestId)
        .orderBy('createdAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map(_pageFromSnapshot);
  }

  Future<ChatPage<ChatMessage, ChatMessageCursor>> loadOlderMessages(
    String requestId, {
    ChatMessageCursor? before,
  }) async {
    _requireUser();
    try {
      Query<Map<String, dynamic>> query = _messages(requestId).orderBy(
        'createdAt',
        descending: true,
      );
      if (before != null) query = query.startAfterDocument(before.document);
      final snapshot = await query.limit(pageSize).get();
      return _pageFromSnapshot(snapshot);
    } on FirebaseException catch (error) {
      throw _convertFirebaseError(error);
    } catch (error) {
      if (error is ChatServiceException) rethrow;
      throw ChatServiceException(ChatServiceFailure.unknown, error.toString());
    }
  }

  Future<void> sendMessage({
    required String requestId,
    required String text,
  }) async {
    final uid = _requireUser();
    final normalizedText = text.trim();
    if (normalizedText.isEmpty || normalizedText.length > 4000) {
      throw const ChatServiceException(
        ChatServiceFailure.invalidArgument,
        'Message text must contain 1 to 4000 characters.',
      );
    }

    try {
      await _messages(requestId).add({
        'senderUid': uid,
        'text': normalizedText,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw _convertFirebaseError(error);
    } catch (error) {
      throw ChatServiceException(ChatServiceFailure.unknown, error.toString());
    }
  }

  Future<void> markDelivered({
    required String requestId,
    required String messageId,
  }) => _markRecipientReceipt(
    requestId: requestId,
    messageId: messageId,
    receiptField: 'deliveredAt',
  );

  Future<void> markRead({
    required String requestId,
    required String messageId,
  }) => _markRecipientReceipt(
    requestId: requestId,
    messageId: messageId,
    receiptField: 'readAt',
  );

  Future<void> _markRecipientReceipt({
    required String requestId,
    required String messageId,
    required String receiptField,
  }) async {
    final uid = _requireUser();
    try {
      final messageRef = _messages(requestId).doc(messageId);
      final message = await messageRef.get();
      final data = message.data();
      if (!message.exists || data == null) {
        throw const ChatServiceException(
          ChatServiceFailure.notFound,
          'The message does not exist.',
        );
      }
      // Only a recipient can set a receipt. The rules independently enforce
      // this and permit updates to the receipt field only.
      if (data['senderUid'] == uid || data[receiptField] != null) return;
      await messageRef.update({receiptField: FieldValue.serverTimestamp()});
    } on ChatServiceException {
      rethrow;
    } on FirebaseException catch (error) {
      throw _convertFirebaseError(error);
    } catch (error) {
      throw ChatServiceException(ChatServiceFailure.unknown, error.toString());
    }
  }

  ChatPage<ChatMessage, ChatMessageCursor> _pageFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final documents = snapshot.docs;
    final hasMore = documents.length == pageSize;
    final cursor = documents.isEmpty
        ? null
        : ChatMessageCursor._(documents.last);
    // The query is newest-first; the page UI displays its list in reverse.
    return ChatPage(
      items: documents.reversed.map(ChatMessage.fromDocument).toList(),
      nextCursor: cursor,
      hasMore: hasMore,
    );
  }

  String _requireUser() {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      throw const ChatServiceException(
        ChatServiceFailure.unauthenticated,
        'A signed-in user is required to use chat.',
      );
    }
    return uid;
  }

  void _validateConversation(
    Map<String, dynamic>? data,
    String requestId,
    String agentUid,
    String loUid,
  ) {
    final participants = data?['participantUids'];
    if (data == null ||
        data['requestId'] != requestId ||
        data['agentUid'] != agentUid ||
        data['loUid'] != loUid ||
        participants is! List ||
        participants.length != 2 ||
        !participants.contains(agentUid) ||
        !participants.contains(loUid)) {
      throw const ChatServiceException(
        ChatServiceFailure.failedPrecondition,
        'The conversation does not match the request participants.',
      );
    }
  }

  ChatServiceException _convertFirebaseError(FirebaseException error) {
    final failure = switch (error.code) {
      'permission-denied' => ChatServiceFailure.unauthorized,
      'unauthenticated' => ChatServiceFailure.unauthenticated,
      'not-found' => ChatServiceFailure.notFound,
      'invalid-argument' => ChatServiceFailure.invalidArgument,
      'failed-precondition' => ChatServiceFailure.failedPrecondition,
      'unavailable' => ChatServiceFailure.unavailable,
      _ => ChatServiceFailure.unknown,
    };
    return ChatServiceException(failure, error.message ?? error.code);
  }
}

DateTime? _dateTimeFrom(Object? value) {
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  return null;
}
