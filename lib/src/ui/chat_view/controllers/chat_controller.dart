import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:chatify/chatify.dart';
import 'package:chatify/src/localization/get_string.dart';
import 'package:chatify/src/ui/chat_view/body/images/image_mode.dart';
import 'package:chatify/src/ui/chat_view/controllers/pending_messages.dart';
import 'package:chatify/src/ui/common/toast.dart';
import 'package:chatify/src/utils/extensions.dart';
import 'package:chatify/src/utils/load_images_video.dart';
import 'package:chatify/src/utils/storage_utils.dart';
import 'package:chatify/src/utils/uuid.dart';
import 'package:chatify/src/utils/value_notifiers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:vibration/vibration.dart';

import 'messages_controller.dart';

part 'record_controller.dart';

class ChatController {
  final Chat chat;
  final List<ChatifyUser> users;
  ChatController(this.chat, this._receivedPendingHandler, this.users)
      : pending =
            _receivedPendingHandler ?? PendingMessagesHandler(chat: chat) {
    voiceController = VoiceRecordingController(this);
    textController.addListener(() {
      isTyping.value = textController.text.isNotEmpty;
      if (isTyping.value) {
        Chatify.datasource.updateChatStatus(ChatStatus.typing, chat.id);
      } else {
        Chatify.datasource.updateChatStatus(ChatStatus.none, chat.id);
      }
    });
  }

  Iterable<ChatifyUser> get receivers =>
      users.where((e) => e.id != Chatify.currentUserId);
  late final VoiceRecordingController voiceController;
  final PendingMessagesHandler pending;
  final PendingMessagesHandler? _receivedPendingHandler;

  final focus = FocusNode();
  final isTyping = false.obs;
  final preventChatScroll = false.obs;
  final selecetdMessages = <String, Message>{}.obs;
  Map<String, Message> initialSelecetdMessages = {};
  final messageAction = Rx<MessageActionArgs?>(null);
  final isEmoji = false.obs;
  final isEmojiIcon = false.obs;
  bool preventEmoji = false;

  final textController = TextEditingController();

  late final messagesController = MessagesController(chat, pending);

  edit(Message message, BuildContext context) {
    messageAction.value =
        MessageActionArgs(message: message, type: MessageActionType.edit);
    textController.text = message.message(localization(context));
    focus.requestFocus();
  }

  reply(Message message) {
    messageAction.value =
        MessageActionArgs(message: message, type: MessageActionType.reply);
    focus.requestFocus();
  }

  copy(Message message, BuildContext context) {
    Clipboard.setData(
      ClipboardData(text: message.message(localization(context))),
    );
    showToast('Copied to clipboard', Colors.black45);
  }

  submitMessage(String msg, BuildContext context) async {
    msg = msg.trim();
    if (msg.isEmpty) return;
    if (messageAction.value?.type == MessageActionType.edit) {
      Chatify.datasource.addMessage(
        (messageAction.value!.message! as TextMessage).copyWith(message: msg),
        null,
      );
    } else {
      for (int i = 0; i <= (msg.length ~/ 1000); i++) {
        final message = TextMessage(
          message: msg.substring(i * 1000, min(msg.length, (i + 1) * 1000)),
          chatId: chat.id,
          unSeenBy:
              chat.members.where((e) => e != Chatify.currentUserId).toList(),
          replyId: messageAction.value?.message?.id,
          replyUid: messageAction.value?.message?.sender,
          replyMessage:
              messageAction.value?.message?.message(localization(context)),
          canReadBy: chat.members,
        );
        final pendingMsg = TextMessage(
          id: message.id,
          message: msg.substring(i * 1000, min(msg.length, (i + 1) * 1000)),
          chatId: chat.id,
          unSeenBy:
              chat.members.where((e) => e != Chatify.currentUserId).toList(),
          replyId: messageAction.value?.message?.id,
          replyUid: messageAction.value?.message?.sender,
          replyMessage:
              messageAction.value?.message?.message(localization(context)),
          canReadBy: chat.members,
          isPending: true,
        );
        pending.add(pendingMsg);
        Chatify.datasource.addMessage(message, receivers);
      }
      Chatify.datasource.addChat(chat);
    }
    messageAction.value = null;
    textController.clear();
  }

  sendImages(List<ImageModel> images) async {
    Chatify.datasource.updateChatStatus(ChatStatus.sendingMedia, chat.id);
    final imgs = await getImages(images);
    await Future.wait(imgs.map((e) => _sendSingleImage(e)));
    Chatify.datasource.updateChatStatus(ChatStatus.none, chat.id);
    Chatify.datasource.addChat(chat);
    selecetdMessages.value = {};
  }

  Future<void> _sendSingleImage(ImageAttachment img) async {
    final id = Uuid.generate();
    final attachment = uploadAttachment(
      img.image,
      'chats/${chat.id}/$id.jpg',
    );
    final pendingMsg = ImageMessage(
      id: id,
      bytes: img.image,
      imageUrl: '',
      thumbnailBytes: [],
      width: img.width,
      height: img.height,
      chatId: chat.id,
      unSeenBy: chat.members.where((e) => e != Chatify.currentUserId).toList(),
      attachment: attachment,
      canReadBy: chat.members,
      isPending: true,
    );
    pending.add(pendingMsg);
    final imageUrl = await attachment.url;
    if (imageUrl == null) {
      pending.remove(pendingMsg);
      return;
    }
    Chatify.datasource.addMessage(
      pendingMsg.copyWith(imageUrl: imageUrl, thumbnailBytes: img.thumbnail),
      receivers,
    );
  }

  vibrate() {
    if (kDebugMode && Platform.isIOS) {
      return;
    }
    Vibration.hasVibrator().then((canVibrate) {
      if (canVibrate == true) Vibration.vibrate(duration: 10, amplitude: 100);
    });
  }

  void dispose() {
    textController.dispose();
    if (_receivedPendingHandler == null) pending.dispose();
    voiceController.dispose();
    preventChatScroll.dispose();
    messagesController.dispose();
    isTyping.dispose();
    selecetdMessages.dispose();
    messageAction.dispose();
    isEmoji.dispose();
    isEmojiIcon.dispose();
    focus.dispose();
  }
}

enum MessageActionType {
  reply,
  edit,
}

class MessageActionArgs {
  final MessageActionType type;
  final Message? message;

  MessageActionArgs({
    required this.message,
    required this.type,
  });
}
