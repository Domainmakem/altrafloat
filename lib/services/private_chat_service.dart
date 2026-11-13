import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Private, one-to-one Agent–Liquidity Officer chat storage.
///
/// Rooms use `agentChats/{agentUid}/conversations/{loUid}`. This makes the
/// Firebase UIDs the immutable room identity and lets LO inboxes use a
/// collection-group query constrained by `loUid`, rather than scanning users
/// or a global unbounded conversation collection.
class PrivateChatService {
  PrivateChatService({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _db = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  static final PrivateChatService instance = PrivateChatService();
  static const int pageSize = 30;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  String get currentUid {
    final uid = _auth.currentUser?.uid;
    if (uid == null || uid.isEmpty) throw StateError('Sign in to use chat.');
    return uid;
  }

  DocumentReference<Map<String, dynamic>> _room(String agentUid, String loUid) =>
      _db.collection('agentChats').doc(agentUid)
          .collection('conversations').doc(loUid);

  CollectionReference<Map<String, dynamic>> _messages(
    String agentUid,
    String loUid,
  ) => _room(agentUid, loUid).collection('messages');

  /// Starts or retrieves the stable UID-pair room. Financial requests are not
  /// read or consulted. Firestore rules independently verify both roles and
  /// the LO's current authorization before allowing creation/access.
  Future<String> openOrCreateRoom({
    required String loUid,
    required String agentName,
    required String loName,
  }) async {
    final agentUid = currentUid;
    if (loUid.trim().isEmpty || loUid == agentUid) {
      throw ArgumentError('A different authorized LO is required.');
    }
    final room = _room(agentUid, loUid);
    final existing = await room.get();
    if (existing.exists) return existing.id;
    await room.set({
      'agentUid': agentUid,
      'loUid': loUid,
      'agentName': agentName,
      'loName': loName,
      'openedByLo': false,
      'lastActivityAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    return room.id;
  }

  /// LO inbox stream: two bounded, server-filtered collection-group queries.
  /// `openedByLo=false` is New Requests; `true` is Conversations.
  Stream<List<PrivateChatRoom>> watchLoInbox({required bool opened}) {
    final uid = currentUid;
    return _db.collectionGroup('conversations')
        .where('loUid', isEqualTo: uid)
        .where('openedByLo', isEqualTo: opened)
        .orderBy('lastActivityAt', descending: true)
        .limit(pageSize)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(PrivateChatRoom.fromDocument).toList());
  }

  /// Cursor-paginated older LO inbox pages; no full-collection downloads.
  Future<PrivateChatRoomPage> loadOlderLoInbox({
    required bool opened,
    DocumentSnapshot<Map<String, dynamic>>? before,
  }) async {
    final query = _db.collectionGroup('conversations')
        .where('loUid', isEqualTo: currentUid)
        .where('openedByLo', isEqualTo: opened)
        .orderBy('lastActivityAt', descending: true);
    final pageQuery = before == null ? query : query.startAfterDocument(before);
    final snapshot = await pageQuery.limit(pageSize).get();
    return PrivateChatRoomPage(
      rooms: snapshot.docs.map(PrivateChatRoom.fromDocument).toList(),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  /// Marking opened is a one-way LO action enforced by Firestore rules.
  Future<void> markOpened({required String agentUid, required String loUid}) async {
    if (currentUid != loUid) throw StateError('Only the selected LO can open this request.');
    await _room(agentUid, loUid).update({'openedByLo': true});
  }

  Stream<List<PrivateChatMessage>> watchLatestMessages({
    required String agentUid,
    required String loUid,
  }) => _messages(agentUid, loUid)
      .orderBy('createdAt', descending: true)
      .limit(pageSize)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map(PrivateChatMessage.fromDocument).toList().reversed.toList());

  Future<PrivateChatMessagePage> loadOlderMessages({
    required String agentUid,
    required String loUid,
    DocumentSnapshot<Map<String, dynamic>>? before,
  }) async {
    Query<Map<String, dynamic>> query = _messages(agentUid, loUid)
        .orderBy('createdAt', descending: true);
    if (before != null) query = query.startAfterDocument(before);
    final snapshot = await query.limit(pageSize).get();
    return PrivateChatMessagePage(
      messages: snapshot.docs.map(PrivateChatMessage.fromDocument).toList().reversed.toList(),
      cursor: snapshot.docs.isEmpty ? null : snapshot.docs.last,
      hasMore: snapshot.docs.length == pageSize,
    );
  }

  Future<void> sendMessage({
    required String agentUid,
    required String loUid,
    required String text,
  }) async {
    final senderUid = currentUid;
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 4000) {
      throw ArgumentError('Message must contain 1–4000 characters.');
    }
    final room = _room(agentUid, loUid);
    final message = _messages(agentUid, loUid).doc();
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(room);
      if (!snapshot.exists) throw StateError('Chat room not found.');
      transaction.set(message, {
        'senderUid': senderUid,
        'text': normalized,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.update(room, {
        'lastMessageText': normalized,
        'lastSenderUid': senderUid,
        'lastActivityAt': FieldValue.serverTimestamp(),
      });
    });
  }
}

class PrivateChatRoom {
  const PrivateChatRoom({
    required this.agentUid,
    required this.loUid,
    required this.agentName,
    required this.loName,
    required this.openedByLo,
    required this.lastActivityAt,
    required this.reference,
  });

  final String agentUid;
  final String loUid;
  final String agentName;
  final String loName;
  final bool openedByLo;
  final DateTime? lastActivityAt;
  final DocumentReference<Map<String, dynamic>> reference;

  factory PrivateChatRoom.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    return PrivateChatRoom(
      agentUid: data['agentUid'] as String? ?? '',
      loUid: data['loUid'] as String? ?? '',
      agentName: data['agentName'] as String? ?? 'Agent',
      loName: data['loName'] as String? ?? 'Liquidity Officer',
      openedByLo: data['openedByLo'] == true,
      lastActivityAt: _chatDate(data['lastActivityAt']),
      reference: doc.reference,
    );
  }
}

class PrivateChatRoomPage {
  const PrivateChatRoomPage({required this.rooms, required this.cursor, required this.hasMore});
  final List<PrivateChatRoom> rooms;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

class PrivateChatMessage {
  const PrivateChatMessage({required this.id, required this.senderUid, required this.text, required this.createdAt});
  final String id;
  final String senderUid;
  final String text;
  final DateTime? createdAt;

  factory PrivateChatMessage.fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return PrivateChatMessage(
      id: doc.id,
      senderUid: data['senderUid'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: _chatDate(data['createdAt']),
    );
  }
}

class PrivateChatMessagePage {
  const PrivateChatMessagePage({required this.messages, required this.cursor, required this.hasMore});
  final List<PrivateChatMessage> messages;
  final DocumentSnapshot<Map<String, dynamic>>? cursor;
  final bool hasMore;
}

DateTime? _chatDate(Object? value) => value is Timestamp ? value.toDate() : null;
