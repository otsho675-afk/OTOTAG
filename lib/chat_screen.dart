import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Haptic feedback için eklendi
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final int jobId;
  final int currentUserId;
  final String currentUserType; 
  final int receiverId;
  final String receiverName;

  const ChatScreen({
    super.key,
    required this.jobId,
    required this.currentUserId,
    required this.currentUserType,
    required this.receiverId,
    required this.receiverName,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final String baseUrl = "https://eliteagency.sbs/api.php";
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  List messages = [];
  Timer? _timer;
  bool isUploading = false;
  bool _isFetching = false;
  bool _isTyping = false; // Dinamik buton için state

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    
    // Timer polling (İleride Socket.io'ya geçirilebilir)
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isFetching) _fetchMessages();
    });

    // Yazma durumunu dinleme
    _msgController.addListener(() {
      setState(() {
        _isTyping = _msgController.text.trim().isNotEmpty;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    _isFetching = true;
    try {
      final response = await http.get(Uri.parse(
          "$baseUrl?action=get_messages&job_id=${widget.jobId}&user_id=${widget.currentUserId}&receiver_id=${widget.receiverId}"));
      
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final newMessages = data['messages'] ?? [];
          if (newMessages.length > messages.length || _hasReadStatusChanged(newMessages)) {
            setState(() {
              messages = newMessages;
            });
            _scrollToBottom();
          }
          _markAsRead();
        }
      }
    } catch (e) {
      debugPrint("Fetch error: $e");
    } finally {
      if (mounted) _isFetching = false;
    }
  }

  bool _hasReadStatusChanged(List newMessages) {
    if (messages.length != newMessages.length) return true;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['is_read'] != newMessages[i]['is_read']) {
        return true;
      }
    }
    return false;
  }

  Future<void> _markAsRead() async {
    try {
      await http.post(
        Uri.parse("$baseUrl?action=mark_read"),
        body: {
          'job_id': widget.jobId.toString(),
          'user_id': widget.currentUserId.toString(),
          'receiver_id': widget.receiverId.toString(),
        },
      );
    } catch (e) {
      debugPrint("Mark read error: $e");
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients && messages.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _sendMessage({File? mediaFile, String mediaType = 'text'}) async {
    final text = _msgController.text.trim();
    if (text.isEmpty && mediaFile == null) return;
    
    // Gönderim sırasında hafif titreşim
    HapticFeedback.lightImpact();

    final previousText = text;
    _msgController.clear();
    setState(() => isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=send_message"));
      request.fields.addAll({
        'job_id': widget.jobId.toString(),
        'sender_id': widget.currentUserId.toString(),
        'sender_type': widget.currentUserType,
        'receiver_id': widget.receiverId.toString(),
        'message_text': text,
        'media_type': mediaType,
      });

      if (mediaFile != null) {
        request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
      }

      final streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
        await _fetchMessages();
        _scrollToBottom();
      } else {
        throw Exception('API Hatası');
      }
    } catch (e) {
      if (mounted) {
        _msgController.text = previousText; 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Mesaj gönderilemedi."), backgroundColor: Color(0xFFFF3366)),
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
        pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 15));
      }

      if (pickedFile != null) {
        await _sendMessage(mediaFile: File(pickedFile.path), mediaType: type);
      }
    } catch (e) {
      debugPrint("Media pick error: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color bgColor = Color(0xFF030305);
    const Color primaryColor = Color(0xFF00FFA3);
    final topPadding = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: true,
      appBar: _buildAppBar(primaryColor),
      body: Stack(
        children: [
          _buildBackgroundGlow(),
          SafeArea(
            bottom: false,
            top: false, 
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.only(
                      top: topPadding + kToolbarHeight + 20, 
                      bottom: 20, 
                      left: 16, 
                      right: 16
                    ),
                    physics: const BouncingScrollPhysics(),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final msg = messages[index];
                      final isMe = msg['sender_id'].toString() == widget.currentUserId.toString();
                      return _buildMessageBubble(msg, isMe, primaryColor);
                    },
                  ),
                ),
                if (isUploading)
                  LinearProgressIndicator(color: primaryColor, backgroundColor: Colors.white.withOpacity(0.1)),
                _buildInputArea(primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Color primaryColor) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: AppBar(
            backgroundColor: Colors.white.withOpacity(0.02),
            elevation: 0,
            leading: IconButton(
              icon: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: primaryColor.withOpacity(0.15), shape: BoxShape.circle),
                  child: Icon(Icons.person, color: primaryColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.receiverName,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.white, letterSpacing: -0.5),
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
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.2,
      left: -MediaQuery.of(context).size.width * 0.2,
      child: Container(
        width: MediaQuery.of(context).size.width,
        height: MediaQuery.of(context).size.width,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [const Color(0xFF00FFA3).withOpacity(0.05), Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isMe, Color primaryColor) {
    final hasMedia = msg['media_url'] != null && msg['media_url'].toString().isNotEmpty;
    final isRead = msg['is_read'] == 1 || msg['is_read'] == '1' || msg['is_read'] == true;
    
    // Saat verisi formatlama (Eğer API 'created_at' dönmüyorsa varsayılan gösterim)
    String timeString = "Şimdi";
    if (msg['created_at'] != null && msg['created_at'].toString().length >= 16) {
      timeString = msg['created_at'].toString().substring(11, 16);
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isMe ? primaryColor : const Color(0xFF1E1E24), 
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
          ),
          boxShadow: isMe ? [
            BoxShadow(color: primaryColor.withOpacity(0.15), blurRadius: 8, offset: const Offset(0, 3))
          ] : [],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasMedia && msg['media_type'] == 'image')
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 250),
                    child: Image.network(
                      "https://eliteagency.sbs/${msg['media_url']}",
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, color: Colors.white54, size: 50),
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const SizedBox(
                          height: 100,
                          child: Center(child: CircularProgressIndicator(color: Colors.white54)),
                        );
                      },
                    ),
                  ),
                ),
              if (hasMedia && msg['media_type'] == 'video')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 24),
                      SizedBox(width: 8),
                      Flexible(child: Text("Video Eki", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis))
                    ],
                  ),
                ),
              if (msg['message_text'] != null && msg['message_text'].toString().trim().isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: hasMedia ? 8.0 : 0.0),
                  child: Text(
                    msg['message_text'],
                    style: TextStyle(color: isMe ? Colors.black87 : Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.3),
                  ),
                ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeString,
                    style: TextStyle(
                      color: isMe ? Colors.black54 : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isRead ? Icons.done_all_rounded : Icons.check_rounded, 
                      size: 15,
                      color: isRead ? Colors.black87 : Colors.black45, 
                    ),
                  ]
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputArea(Color primaryColor) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: EdgeInsets.only(
            left: 12, 
            right: 12, 
            top: 10, 
            bottom: MediaQuery.of(context).padding.bottom + 10
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.04),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: GestureDetector(
                  onTap: () => _showMediaBottomSheet(primaryColor),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                    child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 22),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: _msgController,
                    minLines: 1,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
                    textCapitalization: TextCapitalization.sentences,
                    onTap: _scrollToBottom,
                    decoration: const InputDecoration(
                      hintText: "Mesajınızı yazın...",
                      hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w400),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: InputBorder.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 4.0),
                child: GestureDetector(
                  onTap: _isTyping ? _sendMessage : null, // Metin yoksa buton tıklanmasın
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _isTyping ? primaryColor : Colors.white.withOpacity(0.1), 
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded, 
                      color: _isTyping ? Colors.black : Colors.white54, 
                      size: 20
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMediaBottomSheet(Color primaryColor) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF111115).withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.1))
          ),
          child: SafeArea(
            child: Wrap(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Center(
                    child: Container(
                      width: 40, height: 4, 
                      decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10))
                    )
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.camera_alt, color: primaryColor),
                  title: const Text("Fotoğraf Çek", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'image'); },
                ),
                ListTile(
                  leading: Icon(Icons.image, color: primaryColor),
                  title: const Text("Galeriden Seç", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.gallery, 'image'); },
                ),
                ListTile(
                  leading: Icon(Icons.videocam, color: primaryColor),
                  title: const Text("Video Çek", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'video'); },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}