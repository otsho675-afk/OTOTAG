import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final int jobId;
  final int currentUserId;
  final String currentUserType; // 'customer' or 'provider'
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

  @override
  void initState() {
    super.initState();
    _fetchMessages();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchMessages());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    try {
      final response = await http.get(Uri.parse(
          "$baseUrl?action=get_messages&job_id=${widget.jobId}&user_id=${widget.currentUserId}&receiver_id=${widget.receiverId}"));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['status'] == 'success' && mounted) {
          final newMessages = data['messages'] ?? [];
          if (newMessages.length > messages.length || _hasReadStatusChanged(newMessages)) {
            setState(() {
              messages = newMessages;
            });
            _scrollToBottom();
          }
          // Ekrandaki mesajları okundu olarak işaretle
          _markAsRead();
        }
      }
    } catch (e) {
      // Background poll fail
    }
  }

  // Yeni mesaj dizisinde okundu durumu değişen var mı kontrolü (Arayüzün güncellenmesi için)
  bool _hasReadStatusChanged(List newMessages) {
    if (messages.length != newMessages.length) return true;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['is_read'] != newMessages[i]['is_read']) {
        return true;
      }
    }
    return false;
  }

  // Mesajları okundu olarak API'ye bildir
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
      // Sessizce başarısız olabilir, periyodik olarak tekrar deneyecektir
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage({File? mediaFile, String mediaType = 'text'}) async {
    final text = _msgController.text.trim();
    if (text.isEmpty && mediaFile == null) return;
    
    _msgController.clear();
    setState(() => isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse("$baseUrl?action=send_message"));
      request.fields['job_id'] = widget.jobId.toString();
      request.fields['sender_id'] = widget.currentUserId.toString();
      request.fields['sender_type'] = widget.currentUserType;
      request.fields['receiver_id'] = widget.receiverId.toString();
      request.fields['message_text'] = text;
      request.fields['media_type'] = mediaType;

      if (mediaFile != null) {
        request.files.add(await http.MultipartFile.fromPath('media', mediaFile.path));
      }

      final streamedResponse = await request.send();
      if (streamedResponse.statusCode == 200 || streamedResponse.statusCode == 201) {
        await _fetchMessages();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mesaj gönderilemedi.", style: TextStyle(color: Colors.white)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => isUploading = false);
    }
  }

  Future<void> _pickMedia(ImageSource source, String type) async {
    final picker = ImagePicker();
    XFile? pickedFile;

    if (type == 'image') {
      pickedFile = await picker.pickImage(source: source, imageQuality: 70);
    } else if (type == 'video') {
      pickedFile = await picker.pickVideo(source: source, maxDuration: const Duration(seconds: 15));
    }

    if (pickedFile != null) {
      _sendMessage(mediaFile: File(pickedFile.path), mediaType: type);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color bgColor = const Color(0xFF050505);
    final Color cardColor = const Color(0xFF111111);
    final Color primaryColor = const Color(0xFF00E676);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 1,
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
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final msg = messages[index];
                  final isMe = msg['sender_id'].toString() == widget.currentUserId.toString();
                  return _buildMessageBubble(msg, isMe, primaryColor, cardColor);
                },
              ),
            ),
            if (isUploading)
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: LinearProgressIndicator(color: primaryColor, backgroundColor: cardColor),
              ),
            _buildInputArea(cardColor, primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isMe, Color primaryColor, Color cardColor) {
    final hasMedia = msg['media_url'] != null && msg['media_url'].toString().isNotEmpty;
    // Backend'den is_read anahtarının 1, '1' veya true dönmesi beklenmektedir.
    final isRead = msg['is_read'] == 1 || msg['is_read'] == '1' || msg['is_read'] == true;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isMe ? primaryColor.withOpacity(0.9) : cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(0),
            bottomRight: isMe ? const Radius.circular(0) : const Radius.circular(20),
          ),
          border: Border.all(color: isMe ? primaryColor : Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasMedia && msg['media_type'] == 'image')
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  "https://eliteagency.sbs/${msg['media_url']}",
                  fit: BoxFit.cover,
                ),
              ),
            if (hasMedia && msg['media_type'] == 'video')
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text("Video Eki", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))
                  ],
                ),
              ),
            if (msg['message_text'] != null && msg['message_text'].toString().trim().isNotEmpty)
              Padding(
                padding: EdgeInsets.only(top: hasMedia ? 8.0 : 0.0),
                child: Text(
                  msg['message_text'],
                  style: TextStyle(color: isMe ? Colors.black : Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            if (isMe)
              Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Icon(
                    isRead ? Icons.done_all : Icons.check, // Okunduysa çift tik, okunmadıysa tek tik
                    size: 16,
                    color: isRead ? Colors.blue.shade800 : Colors.black54, // Okundu mavi, iletildi siyahımsı
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(Color cardColor, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        border: const Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                backgroundColor: cardColor,
                builder: (context) => SafeArea(
                  child: Wrap(
                    children: [
                      ListTile(
                        leading: Icon(Icons.camera_alt, color: primaryColor),
                        title: const Text("Fotoğraf Çek", style: TextStyle(color: Colors.white)),
                        onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'image'); },
                      ),
                      ListTile(
                        leading: Icon(Icons.image, color: primaryColor),
                        title: const Text("Galeriden Fotoğraf Seç", style: TextStyle(color: Colors.white)),
                        onTap: () { Navigator.pop(context); _pickMedia(ImageSource.gallery, 'image'); },
                      ),
                      ListTile(
                        leading: Icon(Icons.videocam, color: primaryColor),
                        title: const Text("Video Çek", style: TextStyle(color: Colors.white)),
                        onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'video'); },
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
              child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 22),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _msgController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: "Mesajınızı yazın...",
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: const Color(0xFF050505),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _sendMessage(),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: primaryColor, shape: BoxShape.circle),
              child: const Icon(Icons.send_rounded, color: Colors.black, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}