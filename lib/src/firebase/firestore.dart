import 'package:chatify/chatify.dart';
import 'package:chatify/src/utils/cache.dart';
import 'package:chatify/src/utils/identical_list.dart';
import 'package:chatify/src/utils/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatifyDatasource {
  final instance = FirebaseFirestore.instance;
  final String messagesCollectionName;
  final String chatsCollectionName;

  ChatifyDatasource({
    this.messagesCollectionName = 'chatify_messages',
    this.chatsCollectionName = 'chatify_chats',
  });

  CollectionReference<Message> get _messages => FirebaseFirestore.instance
      .collection(messagesCollectionName)
      .withConverter<Message>(
        fromFirestore: (snapshot, _) =>
            Message.fromJson(snapshot.data()!, snapshot.id),
        toFirestore: (message, _) => message.toJson,
      );
  CollectionReference<Chat> get _chats => FirebaseFirestore.instance
      .collection(chatsCollectionName)
      .withConverter<Chat>(
        fromFirestore: (snapshot, _) =>
            Chat.fromJson(snapshot.data()!, snapshot.id),
        toFirestore: (chat, _) => chat.toJson,
      );

  Future<Message?> readMessage(String messageId) async {
    return (await _messages.doc(messageId).get()).data();
  }

  Future<void> addMessage(Message message) async {
    await _messages.doc(message.id).set(message, SetOptions(merge: true));
    Chatify.config.onSendMessage?.call(message);
  }

  Future<void> updateMessageUsingFieldValue(
    String messageId,
    Map<String, FieldValue> data,
  ) async {
    await _messages.doc(messageId).update(data);
  }

  Future<void> addMessageEmojis(String messageId, String emoji) async {
    await _messages.doc(messageId).update({
      'emojis': FieldValue.arrayUnion(
        [MessageEmoji(emoji: emoji, uid: Chatify.currentUserId)],
      )
    });
  }

  Future<void> removeMessageEmojis(String messageId) async {
    return FirebaseFirestore.instance.runTransaction((t) async {
      final msg = await t.get(_messages.doc(messageId));
      final emojis = msg.data()!.emojis;
      emojis.removeWhere((e) => e.uid == Chatify.currentUserId);
      t.update(
        _messages.doc(messageId),
        {'emojis': emojis.map((e) => e.toJson)},
      );
    });
  }

  Future<void> deleteMessageForAll(String id) async {
    await _messages.doc(id).delete();
  }

  Future<void> deleteMessageForMe(String id) async {
    await _messages.doc(id).update({
      'deletedBy': FieldValue.arrayUnion([Chatify.currentUserId])
    });
  }

  Future<void> markAsSeen(String id) async {
    await _messages.doc(id).update({
      'unSeenBy': FieldValue.arrayRemove([Chatify.currentUserId]),
      'seenBy': FieldValue.arrayUnion([Chatify.currentUserId])
    });
  }

  Future<void> markAllMessagesAsSeen(String chatId) async {
    final unSeenMessages = await _messages
        .where('chatId', isEqualTo: chatId)
        .where('unSeenBy', arrayContains: Chatify.currentUserId)
        .get();
    for (final message in unSeenMessages.docs) {
      await markAsSeen(message.id);
    }
  }

  Future<void> markAsDelivered(String id) async {
    await _messages.doc(id).update({
      'deliveredTo': FieldValue.arrayUnion([Chatify.currentUserId])
    });
  }

  Future<void> addChat(Chat chat) async {
    await _chats.doc(chat.id).set(chat, SetOptions(merge: true));
  }

  Future<Chat?> readChat(String id) async {
    return Cache.get<Chat>(id) ?? (await _chats.doc(id).get()).data();
  }

  Future<Chat> findChatOrCreate(List<String> members) async {
    bool isExist = Cache.cache.entries.any(
      (e) =>
          e.value is Chat &&
          (e.value as Chat).members.hasSameElementsAs(members),
    );
    if (isExist) {
      return Cache.cache.entries
          .firstWhere(
            (e) =>
                e.value is Chat &&
                (e.value as Chat).members.hasSameElementsAs(members),
          )
          .value as Chat;
    }
    final res = await _chats
        .where('membersCount', isEqualTo: members.length)
        .where('members', whereIn: [members, members.reversed.toList()]).get();
    if (res.size > 0) return res.docs.first.data();
    final chat = Chat(id: Uuid.generate(), members: members);
    return chat;
  }

  Future<void> deletechat(String id) async {
    await _chats.doc(id).delete();
  }

  Query<Message> messagesQuery(String chatId) {
    return _messages
        .where('chatId', isEqualTo: chatId)
        .orderBy('sendAt', descending: true);
  }

  Query<Chat> get chatsQuery {
    return _chats
        .where('members', arrayContains: Chatify.currentUserId)
        .orderBy('updatedAt', descending: true);
  }

  Query<Message> unSeenMessages(String chatId) {
    return _messages
        .where('chatId', isEqualTo: chatId)
        .where('unSeenBy', arrayContains: Chatify.currentUserId)
        .withConverter<Message>(
          fromFirestore: (snapshot, _) =>
              Message.fromJson(snapshot.data()!, snapshot.id),
          toFirestore: (model, _) => model.toJson,
        );
  }

  Stream<int> unSeenMessagesCount(String chatId) =>
      unSeenMessages(chatId).snapshots().map((e) => e.size);

  Stream<int> get getUnreadMessagesCount {
    return _messages
        .where('unSeenBy', arrayContains: Chatify.currentUserId)
        .snapshots()
        .map((event) => event.size);
  }

  Future<Message?> lastMessage(String roomId) async {
    var data = await messagesQuery(roomId).limit(1).get();
    if (data.docs.isNotEmpty) return data.docs.first.data();
    return null;
  }

  Stream<Message?> lastMessageStream(String roomId) {
    return messagesQuery(roomId).limit(1).snapshots().map((event) {
      if (event.docs.isNotEmpty) return event.docs.first.data();
      return null;
    });
  }
}
