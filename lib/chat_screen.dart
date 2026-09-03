import 'package:flutter/material.dart';
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
          _markAsRead();
        }
      }
    } catch (e) {
      // Background poll fail
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
      // Sessizce başarısız olabilir
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
        const SnackBar(content: Text("Mesaj gönderilemedi.", style: TextStyle(color: Colors.white)), backgroundColor: Color(0xFFFF3366)),
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
    final Color bgColor = const Color(0xFF030305);
    final Color primaryColor = const Color(0xFF00FFA3);

    return Scaffold(
      backgroundColor: bgColor,
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: ClipRRect(
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
              iconTheme: const IconThemeData(color: Colors.white),
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
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
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
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
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: LinearProgressIndicator(color: primaryColor, backgroundColor: Colors.white.withOpacity(0.1)),
                  ),
                _buildInputArea(primaryColor),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map msg, bool isMe, Color primaryColor) {
    final hasMedia = msg['media_url'] != null && msg['media_url'].toString().isNotEmpty;
    final isRead = msg['is_read'] == 1 || msg['is_read'] == '1' || msg['is_read'] == true;
    
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isMe ? primaryColor : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: isMe ? const Radius.circular(24) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(24),
          ),
          border: isMe ? null : Border.all(color: Colors.white.withOpacity(0.05)),
          boxShadow: isMe ? [
            BoxShadow(color: primaryColor.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5))
          ] : [],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(24),
            topRight: const Radius.circular(24),
            bottomLeft: isMe ? const Radius.circular(24) : const Radius.circular(4),
            bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(24),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: isMe ? 0 : 10, sigmaY: isMe ? 0 : 10),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                        style: TextStyle(color: isMe ? Colors.black : Colors.white, fontSize: 15, fontWeight: FontWeight.w500, height: 1.4),
                      ),
                    ),
                  if (isMe)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Align(
                        alignment: Alignment.bottomRight,
                        child: Icon(
                          isRead ? Icons.done_all : Icons.check, 
                          size: 16,
                          color: isRead ? Colors.blue.shade900 : Colors.black54, 
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

  Widget _buildInputArea(Color primaryColor) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.05))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    showModalBottomSheet(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (context) => BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF111115).withOpacity(0.9),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.camera_alt, color: primaryColor)),
                                  title: const Text("Fotoğraf Çek", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.camera, 'image'); },
                                ),
                                ListTile(
                                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.image, color: primaryColor)),
                                  title: const Text("Galeriden Fotoğraf Seç", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                  onTap: () { Navigator.pop(context); _pickMedia(ImageSource.gallery, 'image'); },
                                ),
                                ListTile(
                                  leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: primaryColor.withOpacity(0.1), shape: BoxShape.circle), child: Icon(Icons.videocam, color: primaryColor)),
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
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), shape: BoxShape.circle),
                    child: const Icon(Icons.add_a_photo_rounded, color: Colors.white, size: 22),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05)),
                    ),
                    child: TextField(
                      controller: _msgController,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                      decoration: const InputDecoration(
                        hintText: "Mesajınızı yazın...",
                        hintStyle: TextStyle(color: Colors.white54, fontWeight: FontWeight.w400),
                        filled: true,
                        fillColor: Colors.transparent,
                        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: () => _sendMessage(),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: primaryColor, 
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: primaryColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 5))]
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.black, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}