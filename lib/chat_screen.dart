// chat_screen.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final String baseUrl = "https://eliteagency.sbs/api.php";
  final TextEditingController _msgController = TextEditingController();
  
  // Mesajları ters sırada tutacağız (reverse: true için)
  List messages = [];
  Timer? _timer;
  bool isUploading = false;
  bool _isFetching = false;
  bool _isTyping = false; 

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

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!_isFetching && mounted) {
        _fetchMessages();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _timer?.cancel();
    } else if (state == AppLifecycleState.resumed) {
      _startPolling();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _msgController.dispose();
    super.dispose();
  }

  Future<void> _fetchMessages() async {
    if (_isFetching) return;
    _isFetching = true;
    
    try {
      final response = await http.get(Uri.parse(
          "$baseUrl?action=get_messages&job_id=${widget.jobId}&user_id=${widget.currentUserId}&receiver_id=${widget.receiverId}"));
      
      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        if (data['status'] == 'success') {
          final List newMessages = data['messages'] ?? [];
          
          // reverse: true kullanacağımız için listeyi ters çevirerek state'e atıyoruz.
          final reversedNewMessages = newMessages.reversed.toList();
          
          if (reversedNewMessages.length != messages.length || _hasReadStatusChanged(reversedNewMessages)) {
            setState(() {
              messages = reversedNewMessages;
            });
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

  bool _hasReadStatusChanged(List reversedNewMessages) {
    if (messages.length != reversedNewMessages.length) return true;
    for (int i = 0; i < messages.length; i++) {
      if (messages[i]['is_read'] != reversedNewMessages[i]['is_read']) {
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

  Future<void> _sendMessage({File? mediaFile, String mediaType = 'text'}) async {
    final text = _msgController.text.trim();
    if (text.isEmpty && mediaFile == null) return;
    
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
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        if (responseData['status'] == 'success') {
          await _fetchMessages();
        } else {
          throw Exception(responseData['message'] ?? 'API Hatası');
        }
      } else {
        throw Exception('Bağlantı Hatası: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        _msgController.text = previousText; 
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Mesaj gönderilemedi, bağlantınızı kontrol edin.", style: TextStyle(color: Colors.white)), 
            backgroundColor: const Color(0xFFFF3366).withOpacity(0.9),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(primaryColor),
      body: Stack(
        children: [
          _buildBackgroundGlow(),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                if (isUploading)
                  LinearProgressIndicator(
                    color: primaryColor, 
                    backgroundColor: Colors.transparent,
                    minHeight: 2,
                  ),
                Expanded(
                  child: ListView.builder(
                    reverse: true, // Listeyi ters çevirir. Klavye açıldığında kusursuz çalışır.
                    padding: const EdgeInsets.only(
                      top: 20, 
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
                _buildInputArea(primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(Color primaryColor) {
    return AppBar(
      backgroundColor: Colors.black.withOpacity(0.5),
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(color: Colors.transparent),
        ),
      ),
      leading: IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
          child: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: Colors.white),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: primaryColor.withOpacity(0.2), shape: BoxShape.circle),
            child: Icon(Icons.person, color: primaryColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              widget.receiverName,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: Colors.white, letterSpacing: -0.3),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundGlow() {
    return Positioned(
      top: MediaQuery.of(context).size.height * 0.1,
      left: -MediaQuery.of(context).size.width * 0.3,
      child: Container(
        width: MediaQuery.of(context).size.width * 1.5,
        height: MediaQuery.of(context).size.width * 1.5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [const Color(0xFF00FFA3).withOpacity(0.04), Colors.transparent],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isMe, Color primaryColor) {
    final hasMedia = msg['media_url'] != null && msg['media_url'].toString().isNotEmpty;
    final isRead = msg['is_read'] == 1 || msg['is_read'] == '1' || msg['is_read'] == true;
    
    String timeString = "Şimdi";
    if (msg['created_at'] != null) {
      final DateTime? date = DateTime.tryParse(msg['created_at'].toString())?.toLocal();
      if (date != null) {
        timeString = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
      }
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        decoration: BoxDecoration(
          color: isMe ? primaryColor : const Color(0xFF1E1E24), 
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(20),
            topRight: const Radius.circular(20),
            bottomLeft: isMe ? const Radius.circular(20) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(20),
          ),
          boxShadow: isMe ? [
            BoxShadow(color: primaryColor.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4))
          ] : [
            BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 5, offset: const Offset(0, 2))
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasMedia && msg['media_type'] == 'image')
                Padding(
                  padding: const EdgeInsets.only(bottom: 6.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250),
                      child: Image.network(
                        "https://eliteagency.sbs/${msg['media_url']}",
                        fit: BoxFit.cover,
                        cacheWidth: 800, // EKLENDİ: OOM (Out of Memory) çökmesini kesin olarak önler
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 100,
                          color: Colors.white10,
                          child: const Center(child: Icon(Icons.broken_image, color: Colors.white54, size: 40)),
                        ),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            height: 150,
                            color: Colors.white10,
                            child: const Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
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
                    decoration: BoxDecoration(color: Colors.black38, borderRadius: BorderRadius.circular(12)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 28),
                        SizedBox(width: 8),
                        Flexible(child: Text("Video Eki", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))
                      ],
                    ),
                  ),
                ),
              if (msg['message_text'] != null && msg['message_text'].toString().trim().isNotEmpty)
                Text(
                  msg['message_text'],
                  style: TextStyle(
                    color: isMe ? const Color(0xFF0A2B1D) : Colors.white, 
                    fontSize: 15, 
                    fontWeight: FontWeight.w500, 
                    height: 1.3
                  ),
                ),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    timeString,
                    style: TextStyle(
                      color: isMe ? const Color(0xFF0A2B1D).withOpacity(0.6) : Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      isRead ? Icons.done_all_rounded : Icons.check_rounded, 
                      size: 14,
                      color: isRead ? const Color(0xFF0A2B1D) : const Color(0xFF0A2B1D).withOpacity(0.5), 
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
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF030305).withOpacity(0.85),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: GestureDetector(
                      onTap: () => _showMediaBottomSheet(primaryColor),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), shape: BoxShape.circle),
                        child: const Icon(Icons.add_rounded, color: Colors.white, size: 24),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.07),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: TextField(
                        controller: _msgController,
                        minLines: 1,
                        maxLines: 5, // Daha uzun metinler için esneklik artırıldı
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 15),
                        textCapitalization: TextCapitalization.sentences,
                        decoration: const InputDecoration(
                          hintText: "Mesaj gönder...",
                          hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w400),
                          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4.0),
                    child: GestureDetector(
                      onTap: _isTyping ? _sendMessage : null, 
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _isTyping ? primaryColor : Colors.white.withOpacity(0.1), 
                          shape: BoxShape.circle,
                          boxShadow: _isTyping ? [
                            BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))
                          ] : [],
                        ),
                        child: Icon(
                          Icons.send_rounded, 
                          color: _isTyping ? const Color(0xFF0A2B1D) : Colors.white54, 
                          size: 22
                        ),
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
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.camera_alt_rounded, color: primaryColor),
                  ),
                  title: const Text("Fotoğraf Çek", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'image'); },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.image_rounded, color: primaryColor),
                  ),
                  title: const Text("Galeriden Seç", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.gallery, 'image'); },
                ),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle),
                    child: Icon(Icons.videocam_rounded, color: primaryColor),
                  ),
                  title: const Text("Video Çek", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'video'); },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}