// chat_screen.dart
import 'package:flutter/material.dart';
import 'core/constants/app_constants.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';
import 'services/realtime_client.dart';
import 'services/push_session.dart';

class ChatScreen extends StatefulWidget {
  final int jobId;
  final int currentUserId;
  final String currentUserType;
  final int receiverId;
  final String receiverName;
  final http.Client? client;

  const ChatScreen({
    super.key,
    required this.jobId,
    required this.currentUserId,
    required this.currentUserType,
    required this.receiverId,
    required this.receiverName,
    this.client,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final String baseUrl = AppConstants.baseUrl;
  final TextEditingController _msgController = TextEditingController();

  // Mesajları ters sırada tutacağız (reverse: true için)
  List messages = [];
  bool isUploading = false;
  final RealtimeClient pusher = RealtimeClient();
  bool _isFetching = false;
  Timer? _fallbackPoller;
  bool _isTyping = false;
  late final http.Client _httpClient = widget.client ?? http.Client();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _fetchMessages();
    _startPolling();

    _msgController.addListener(() {
      setState(() {
        _isTyping = _msgController.text.trim().isNotEmpty;
      });
    });
  }

  Future<void> _initWebSocket() async {
    try {
      await pusher.init(
        apiKey: AppConstants.pusherKey,
        cluster: "eu",
        onAuthorizer:
            (String channelName, String socketId, dynamic options) async {
          final response = await _httpClient.post(
            Uri.parse("$baseUrl?action=pusher_auth"),
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: {
              'socket_id': socketId,
              'channel_name': channelName,
              'user_id': widget.currentUserId.toString(),
            },
          );
          return jsonDecode(response.body);
        },
        onConnectionStateChange: (currentState, previousState) {
          if (currentState == 'CONNECTED' && mounted) {
            _fetchMessages();
          }
        },
        onEvent: (event) {
          if (event.eventName == "new_message" && mounted) {
            _fetchMessages();
          }
        },
      );
      await pusher.subscribe(channelName: "private-chat_${widget.jobId}");
      await pusher.connect();
    } catch (e) {
      debugPrint("Pusher error: $e");
    }
  }

  void _startPolling() {
    _initWebSocket();
    _startFallbackPolling();
  }

  void _startFallbackPolling() {
    _fallbackPoller?.cancel();
    _fallbackPoller = Timer.periodic(const Duration(seconds: 6), (_) {
      if (mounted && !pusher.isSubscribed('private-chat_${widget.jobId}')) {
        _fetchMessages();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _fallbackPoller?.cancel();
      pusher.disconnect();
    } else if (state == AppLifecycleState.resumed) {
      PushSession.refresh();
      pusher.connect();
      // Uygulama uyandığında WebSocket kopukluğu sırasında kaçırılan mesajları senkronize et
      _fetchMessages();
      _startFallbackPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fallbackPoller?.cancel();
    pusher.unsubscribe(channelName: "private-chat_${widget.jobId}");
    pusher.dispose();
    _msgController.dispose();
    if (widget.client == null) _httpClient.close();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      final response = await _httpClient
          .get(Uri.parse(
              "$baseUrl?action=get_messages&job_id=${widget.jobId}&user_id=${widget.currentUserId}&receiver_id=${widget.receiverId}"))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List newMessages = data['messages'] is List
              ? (data['messages'] as List).whereType<Map>().toList()
              : [];

          // reverse: true kullanacağımız için listeyi ters çevirerek state'e atıyoruz.
          final reversedNewMessages = newMessages.reversed.toList();

          if (reversedNewMessages.length != messages.length ||
              _hasReadStatusChanged(reversedNewMessages)) {
            setState(() {
              messages = reversedNewMessages;
            });
          }
        }
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    } finally {
      if (mounted) _isFetching = false;
    }
  }

  bool _hasReadStatusChanged(List reversedNewMessages) {
    if (messages.length != reversedNewMessages.length) return true;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['is_read'] != reversedNewMessages[i]['is_read']) {
        return true;
      }
    }
    return false;
  }

  Future<void> _sendMessage(
      {File? mediaFile, String mediaType = 'text'}) async {
    if (isUploading || !mounted) return;
    final text = _msgController.text.trim();
    if (text.isEmpty && mediaFile == null) return;

    HapticFeedback.lightImpact();

    final previousText = text;
    setState(() => isUploading = true);

    try {
      var request = http.MultipartRequest(
          'POST', Uri.parse("$baseUrl?action=send_message"));
      request.fields.addAll({
        'job_id': widget.jobId.toString(),
        'sender_id': widget.currentUserId.toString(),
        'sender_type': widget.currentUserType,
        'receiver_id': widget.receiverId.toString(),
        'message_text': text,
        'media_type': mediaType,
      });

      if (mediaFile != null) {
        request.files
            .add(await http.MultipartFile.fromPath('media', mediaFile.path));
      }

      // Use the app client so multipart uploads carry the same session token
      // as ordinary API requests.
      final streamedResponse =
          await _httpClient.send(request).timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          if (mounted) _msgController.clear();
          await _fetchMessages();
        } else {
          throw Exception(responseData['message'] ?? 'API Hatası');
        }
      } else {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        throw Exception(data is Map
            ? (data['message'] ?? 'Bağlantı hatası')
            : 'Bağlantı hatası');
      }
    } catch (e) {
      if (mounted) {
        if (_msgController.text.isEmpty) _msgController.text = previousText;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                "Mesaj gönderilemedi, bağlantınızı kontrol edin.",
                style: TextStyle(color: Colors.white)),
            backgroundColor: const Color(0xFFFF3366).withValues(alpha: 0.9),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    try {
      final picker = ImagePicker();
      XFile? pickedFile;

      if (type == 'image') {
        pickedFile = await picker.pickImage(source: source, imageQuality: 70);
      } else if (type == 'video') {
        pickedFile = await picker.pickVideo(
            source: source, maxDuration: const Duration(seconds: 15));
      }

      if (pickedFile != null) {
        await _sendMessage(mediaFile: File(pickedFile.path), mediaType: type);
      }
    } catch (e) {
      debugPrint("Media pick error: $e");
    }
  }

  // Siber Tema Renk Paleti (V2 - Ultra Modern Glassmorphism)
  static const Color neonGreen = Color(0xFF00FFA3);
  static const Color pureBlack = AppConstants.bgColor;
  static const Color panelBlack = AppConstants.cardColor;
  static const Color neonCyan = AppConstants.primaryColor;
  static const Color alertRed = Color(0xFFFF2A5F);

  @override
  Widget build(BuildContext context) {
    final mediaQueryData = MediaQuery.of(context);

    return MediaQuery(
      data: mediaQueryData.copyWith(
        textScaler: mediaQueryData.textScaler.clamp(maxScaleFactor: 1.3),
      ),
      child: Scaffold(
        backgroundColor: pureBlack,
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(neonGreen),
        body: Stack(
          children: [
            _buildBackgroundGlow(),
            SafeArea(
              bottom: false,
              child: Column(
                children: [
                  if (isUploading)
                    const LinearProgressIndicator(
                        color: neonGreen,
                        backgroundColor: Colors.transparent,
                        minHeight: 2),
                  Expanded(
                    child: ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.only(
                          top: 20, bottom: 20, left: 16, right: 16),
                      physics: const BouncingScrollPhysics(),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final msg = messages[index];
                        final isMe = msg['sender_id'].toString() ==
                            widget.currentUserId.toString();
                        return _buildMessageBubble(msg, isMe, neonGreen);
                      },
                    ),
                  ),
                  _buildInputArea(neonGreen),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Color primaryColor) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(60),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: AppBar(
            backgroundColor: panelBlack.withValues(alpha: 0.65),
            elevation: 0,
            shadowColor: primaryColor.withValues(alpha: 0.2),
            surfaceTintColor: Colors.transparent,
            shape: Border(
                bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.05), width: 1)),
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white10)),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 16, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: primaryColor.withValues(alpha: 0.3))),
                  child:
                      Icon(Icons.person_rounded, color: primaryColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    widget.receiverName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: Colors.white,
                        letterSpacing: -0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackgroundGlow() {
    return Stack(
      children: [
        Positioned(
          top: -100,
          left: -100,
          child: Container(
            width: 300,
            height: 300,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                neonGreen.withValues(alpha: 0.12),
                Colors.transparent
              ]),
              boxShadow: [
                BoxShadow(
                    color: neonGreen.withValues(alpha: 0.1),
                    blurRadius: 100,
                    spreadRadius: 50)
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 100,
          right: -100,
          child: Container(
            width: 350,
            height: 350,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                neonCyan.withValues(alpha: 0.1),
                Colors.transparent
              ]),
              boxShadow: [
                BoxShadow(
                    color: neonCyan.withValues(alpha: 0.1),
                    blurRadius: 100,
                    spreadRadius: 50)
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(Map msg, bool isMe, Color primaryColor) {
    final hasMedia =
        msg['media_url'] != null && msg['media_url'].toString().isNotEmpty;
    final isRead =
        msg['is_read'] == 1 || msg['is_read'] == '1' || msg['is_read'] == true;

    String timeString = "Şimdi";
    if (msg['created_at'] != null) {
      final DateTime? date =
          DateTime.tryParse(msg['created_at'].toString())?.toLocal();
      if (date != null) {
        timeString =
            "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isMe ? primaryColor : panelBlack.withValues(alpha: 0.7),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft:
                isMe ? const Radius.circular(24) : const Radius.circular(6),
            bottomRight:
                isMe ? const Radius.circular(6) : const Radius.circular(24),
          ),
          border: isMe
              ? null
              : Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 1.5),
          boxShadow: isMe
              ? [
                  BoxShadow(
                      color: primaryColor.withValues(alpha: 0.3),
                      blurRadius: 15,
                      offset: const Offset(0, 5))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5))
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft:
                isMe ? const Radius.circular(24) : const Radius.circular(6),
            bottomRight:
                isMe ? const Radius.circular(6) : const Radius.circular(24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasMedia && msg['media_type'] == 'image')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(context).size.height * 0.35),
                        child: Image.network(
                          "https://eliteagency.sbs/${msg['media_url']}",
                          fit: BoxFit.cover,
                          cacheWidth: 800,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                            height: 100,
                            color: Colors.white10,
                            child: const Center(
                                child: Icon(Icons.broken_image,
                                    color: Colors.white54, size: 40)),
                          ),
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 150,
                              color: Colors.white10,
                              child: const Center(
                                  child: CircularProgressIndicator(
                                      color: Colors.white54, strokeWidth: 2)),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (hasMedia && msg['media_type'] == 'video')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6.0),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: Colors.black38,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_circle_fill_rounded,
                              color: Colors.white, size: 28),
                          SizedBox(width: 8),
                          Flexible(
                              child: Text("Video Eki",
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis))
                        ],
                      ),
                    ),
                  ),
                if (msg['message_text'] != null &&
                    msg['message_text'].toString().trim().isNotEmpty)
                  Text(
                    msg['message_text'],
                    style: TextStyle(
                        color: isMe ? const Color(0xFF0A2B1D) : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        letterSpacing: -0.2),
                  ),
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      timeString,
                      style: TextStyle(
                        color: isMe
                            ? const Color(0xFF0A2B1D).withValues(alpha: 0.6)
                            : Colors.white54,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      Icon(
                        isRead ? Icons.done_all_rounded : Icons.check_rounded,
                        size: 14,
                        color: isRead
                            ? const Color(0xFF0A2B1D)
                            : const Color(0xFF0A2B1D).withValues(alpha: 0.5),
                      ),
                    ]
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(Color primaryColor) {
    return Container(
      decoration: BoxDecoration(
        color: panelBlack.withValues(alpha: 0.75),
        border: Border(
            top: BorderSide(
                color: Colors.white.withValues(alpha: 0.08), width: 1.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.5),
              blurRadius: 20,
              offset: const Offset(0, -5))
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _showMediaBottomSheet(primaryColor);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.1))),
                        child: Icon(Icons.add_rounded,
                            color: primaryColor, size: 22),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                            width: 1.5),
                      ),
                      child: TextField(
                        controller: _msgController,
                        enabled: !isUploading,
                        minLines: 1,
                        maxLines: 5,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          hintText: "Mesaj gönder...",
                          hintStyle: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontWeight: FontWeight.w500),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 14),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2.0),
                    child: GestureDetector(
                      onTap: _isTyping && !isUploading ? _sendMessage : null,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _isTyping
                              ? primaryColor
                              : Colors.white.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _isTyping
                                  ? primaryColor
                                  : Colors.white.withValues(alpha: 0.1)),
                          boxShadow: _isTyping
                              ? [
                                  BoxShadow(
                                      color:
                                          primaryColor.withValues(alpha: 0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4))
                                ]
                              : [],
                        ),
                        child: Icon(Icons.send_rounded,
                            color: _isTyping
                                ? const Color(0xFF0A2B1D)
                                : Colors.white54,
                            size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMediaBottomSheet(Color primaryColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
              color: panelBlack.withValues(alpha: 0.9),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(32)),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08), width: 1.5)),
          child: SafeArea(
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                      child: Container(
                          width: 48,
                          height: 5,
                          decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10)))),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 24, bottom: 12),
                  child: Text("Medya Gönder",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.5)),
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: primaryColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: primaryColor.withValues(alpha: 0.3))),
                    child: Icon(Icons.camera_alt_rounded,
                        color: primaryColor, size: 22),
                  ),
                  title: const Text("Fotoğraf Çek",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia(ImageSource.camera, 'image');
                  },
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: neonCyan.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: neonCyan.withValues(alpha: 0.3))),
                    child: const Icon(Icons.image_rounded,
                        color: neonCyan, size: 22),
                  ),
                  title: const Text("Galeriden Seç",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia(ImageSource.gallery, 'image');
                  },
                ),
                ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: alertRed.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: alertRed.withValues(alpha: 0.3))),
                    child: const Icon(Icons.videocam_rounded,
                        color: alertRed, size: 22),
                  ),
                  title: const Text("Video Çek",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
                  onTap: () {
                    Navigator.pop(context);
                    _pickMedia(ImageSource.camera, 'video');
                  },
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
