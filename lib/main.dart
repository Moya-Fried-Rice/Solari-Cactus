import 'package:flutter/material.dart';
import 'package:cactus/cactus.dart';
import 'package:cactus/types.dart';
import 'package:cactus/vlm.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';

class MessageWithImages {
  final ChatMessage message;
  final List<File> images;
  
  MessageWithImages({required this.message, this.images = const []});
}

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Solari Chat',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: ChatScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ChatMessageWidget extends StatelessWidget {
  final ChatMessage message;
  final List<File> attachedImages;
  final bool isGenerating;

  const ChatMessageWidget({
    Key? key,
    required this.message,
    this.attachedImages = const [],
    this.isGenerating = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    
    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(Icons.smart_toy, color: Colors.white, size: 16),
            ),
            SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isUser ? Colors.blue : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Show attached images for user messages
                  if (isUser && attachedImages.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: attachedImages.map((image) => 
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            image,
                            width: 100,
                            height: 100,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ).toList(),
                    ),
                    SizedBox(height: 8),
                  ],
                  Text(
                    message.content,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 16,
                    ),
                  ),
                  if (!isUser && isGenerating) ...[
                    SizedBox(height: 8),
                    Row(
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Generating...',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (isUser) ...[
            SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey[400],
              child: Icon(Icons.person, color: Colors.white, size: 16),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  CactusVLM? _vlm;
  List<MessageWithImages> _messages = [];
  final _controller = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  List<File> _selectedImages = [];
  final ImagePicker _picker = ImagePicker();
  bool _isGenerating = false;
  DateTime? _generationStartTime;
  int _tokenCount = 0;

  @override
  void initState() {
    super.initState();
    _initModel();
  }

  Future<void> _initModel() async {
    try {
      final vlm = CactusVLM();
      await vlm.download(
        modelUrl: 'https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/SmolVLM-256M-Instruct-Q8_0.gguf',
        mmprojUrl: 'https://huggingface.co/ggml-org/SmolVLM-256M-Instruct-GGUF/resolve/main/mmproj-SmolVLM-256M-Instruct-Q8_0.gguf',
        onProgress: (progress, status, isError) {
          print('$status ${progress != null ? '${(progress * 100).toInt()}%' : ''}');
        },
      );
      await vlm.init(contextSize: 2048);
      _vlm = vlm; 
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      print('Error initializing model: $e');
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load model bruh: $e';
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_vlm == null || _controller.text.trim().isEmpty) return;

    final userMsg = ChatMessage(role: 'user', content: _controller.text.trim());
    final userMsgWithImages = MessageWithImages(
      message: userMsg, 
      images: List.from(_selectedImages), // Store the images with the message
    );
    
    setState(() {
      _messages.add(userMsgWithImages);
      _messages.add(MessageWithImages(
        message: ChatMessage(role: 'assistant', content: ''),
      ));
      _isGenerating = true;
      _generationStartTime = DateTime.now();
      _tokenCount = 0;
    });
    
    // Get image paths for the VLM
    List<String> imagePaths = _selectedImages.map((file) => file.path).toList();
    
    _controller.clear();
    setState(() {
      _selectedImages.clear(); // Clear selected images after sending
    });

    String response = '';
    await _vlm!.completion(
      _messages.where((m) => m.message.content.isNotEmpty).map((m) => m.message).toList(),
      imagePaths: imagePaths, // Pass image paths to the VLM
      maxTokens: 200,
        temperature: 0.7,
        onToken: (token) {
        response += token;
        _tokenCount++;
        
        setState(() {
          _messages.last = MessageWithImages(
            message: ChatMessage(role: 'assistant', content: response),
          );
        });
        return true;
      },
    );
    
    // Add final metrics to the response
    final totalTime = DateTime.now().difference(_generationStartTime!);
    final tokensPerSecond = _tokenCount / totalTime.inMilliseconds * 1000;
    
    setState(() {
      _isGenerating = false;
      final metricsText = '\n\n📊 Generated ${_tokenCount} tokens in ${totalTime.inMilliseconds}ms (${tokensPerSecond.toStringAsFixed(1)} tok/s)';
      _messages.last = MessageWithImages(
        message: ChatMessage(role: 'assistant', content: response + metricsText),
      );
    });
  }

  Future<void> _pickImageFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      setState(() {
        _selectedImages.add(File(image.path));
      });
    }
  }

  Future<void> _pickImageFromCamera() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      setState(() {
        _selectedImages.add(File(image.path));
      });
    }
  }

  void _removeImage(int index) {
    setState(() {
      _selectedImages.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(strokeWidth: 3),
              SizedBox(height: 20),
              Text(
                'Loading SmolVLM Model...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
              ),
              SizedBox(height: 8),
              Text(
                'This may take a few minutes on first launch',
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Error:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(_errorMessage!, textAlign: TextAlign.center),
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                  _initModel();
                },
                child: Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Solari Vision Chat', style: TextStyle(fontSize: 18)),
            Text('SmolVLM-256M', style: TextStyle(fontSize: 12, color: Colors.grey[300])),
          ],
        ),
        backgroundColor: Colors.blue[700],
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: EdgeInsets.symmetric(vertical: 8),
                itemCount: _messages.length,
              itemBuilder: (context, index) {
                final reversedIndex = _messages.length - 1 - index;
                final msgWithImages = _messages[reversedIndex];
                final isGeneratingThisMessage = _isGenerating && reversedIndex == _messages.length - 1;
                
                return ChatMessageWidget(
                  message: msgWithImages.message,
                  attachedImages: msgWithImages.images,
                  isGenerating: isGeneratingThisMessage,
                );
              },
            ),
          ),
          // Show selected images
          if (_selectedImages.isNotEmpty)
            Container(
              height: 100,
              padding: EdgeInsets.all(8),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _selectedImages.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: EdgeInsets.only(right: 8),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImages[index],
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Positioned(
                          top: 0,
                          right: 0,
                          child: GestureDetector(
                            onTap: () => _removeImage(index),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.close,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  onPressed: _pickImageFromCamera,
                  icon: Icon(Icons.camera_alt),
                  tooltip: 'Take Photo',
                ),
                IconButton(
                  onPressed: _pickImageFromGallery,
                  icon: Icon(Icons.photo_library),
                  tooltip: 'Pick from Gallery',
                ),
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(onPressed: _sendMessage, icon: Icon(Icons.send)),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _vlm?.dispose();
    super.dispose();
  }
}