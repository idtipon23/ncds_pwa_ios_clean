import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../services/patient_profile_service.dart';
import '../services/ht_consult_service.dart';

class HtConsultScreen extends StatefulWidget {
  const HtConsultScreen({super.key});

  @override
  State<HtConsultScreen> createState() => _HtConsultScreenState();
}

class _HtConsultScreenState extends State<HtConsultScreen> {
  final _profileService = PatientProfileService();
  final _consultService = HtConsultService();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;

  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai',
      'text':
          'สวัสดีค่ะ มีข้อสงสัยเกี่ยวกับโรคความดัน การทานยา การคุมอาหาร หรือต้องการคำแนะนำตามแนวทาง HT Guideline 2567 สอบถามหมอ AI ได้เลยนะคะ 😊',
      'time': DateTime.now(),
    }
  ];

  bool _isSending = false;
  Map<String, dynamic>? _profileData;

  static const Color emeraldColor = Color(0xFF10B981);
  static const Color slateColor = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _initTts();
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage("th-TH");
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    _flutterTts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    setState(() => _isSpeaking = true);
    await _flutterTts.speak(text);
  }

  Future<void> _stopSpeaking() async {
    await _flutterTts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  @override
  void dispose() {
    _stopSpeaking();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final profile = await _profileService.getProfile();
    if (mounted) {
      setState(() {
        _profileData = profile;
      });
    }
  }

  Future<void> _handleSendMessage() async {
    final query = _textController.text.trim();
    if (query.isEmpty || _isSending) return;

    await _stopSpeaking();

    setState(() {
      _messages.add({
        'sender': 'user',
        'text': query,
        'time': DateTime.now(),
      });
      _textController.clear();
      _isSending = true;
      
      _messages.add({
        'sender': 'ai',
        'text': 'กำลังคิด...',
        'time': DateTime.now(),
      });
    });

    _scrollToBottom();

    try {
      final stream = _consultService.askConsultStream(
        userQuery: query,
        profileData: _profileData,
      );

      String fullAiResponse = '';
      bool isFirstChunk = true;
      
      await for (final chunk in stream) {
        fullAiResponse += chunk; 
        
        setState(() {
          if (isFirstChunk) {
            isFirstChunk = false; 
          }
          _messages.last['text'] = fullAiResponse;
        });
        _scrollToBottom();
      }

      if (fullAiResponse.isNotEmpty) {
        _speak(fullAiResponse);
      }

    } catch (e) {
      debugPrint('Chat Error: $e');
      setState(() {
        _messages.last['text'] = 'ขออภัยค่ะ ขณะนี้ระบบประมวลผลหนาแน่น กรุณาลองถามใหม่อีกครั้งนะคะ';
      });
    } finally {
      setState(() {
        _isSending = false;
      });
      _scrollToBottom();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('ปรึกษาหมอ AI', style: TextStyle(color: slateColor, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: slateColor),
        elevation: 1,
        actions: [
          if (_isSpeaking)
            IconButton(
              icon: const Icon(Icons.volume_off_rounded, color: Colors.redAccent),
              onPressed: _stopSpeaking,
              tooltip: 'หยุดเสียงอ่าน',
            ),
        ],
      ),
      body: Column(
        children: [
          _buildMedicalDisclaimerBanner(),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final msg = _messages[index];
                final isAI = msg['sender'] == 'ai';
                return Align(
                  alignment: isAI ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.8,
                    ),
                    decoration: BoxDecoration(
                      color: isAI ? Colors.white : emeraldColor,
                      borderRadius: BorderRadius.circular(16).copyWith(
                        bottomLeft: isAI ? const Radius.circular(0) : const Radius.circular(16),
                        bottomRight: !isAI ? const Radius.circular(0) : const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 5,
                          offset: const Offset(0, 2),
                        )
                      ],
                    ),
                    child: Text(
                      msg['text'] ?? '',
                      style: TextStyle(
                        color: isAI ? slateColor : Colors.white,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'พิมพ์ข้อความเพื่อสอบถาม...',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade500,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                      onSubmitted: (_) => _handleSendMessage(),
                      readOnly: _isSending,
                    ),
                  ),
                  const SizedBox(width: 10),

                  CircleAvatar(
                    radius: 22,
                    backgroundColor: _isSending ? Colors.grey.shade300 : slateColor,
                    child: IconButton(
                      icon: Icon(
                        Icons.send_rounded, 
                        color: _isSending ? Colors.grey.shade500 : Colors.white, 
                        size: 20
                      ),
                      onPressed: _isSending ? null : _handleSendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalDisclaimerBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFCD34D), width: 1),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFFB45309), size: 20),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'คำแนะนำจาก AI ใช้เป็นแนวทางเบื้องต้นเท่านั้น ไม่สามารถทดแทนการวินิจฉัยของแพทย์ หากมีอาการฉุกเฉินกรุณาพบแพทย์ทันที',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFF92400E),
                height: 1.3,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}