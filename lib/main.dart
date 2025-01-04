import 'package:flutter/material.dart';
import 'package:flutter_model_viewer/flutter_model_viewer.dart';
import 'services/speech_service.dart';
import 'package:html_unescape/html_unescape.dart';
import 'services/json_knowledge_service.dart';

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SpeechService _speechService = SpeechService();
  final HtmlUnescape _unescape = HtmlUnescape();
  final TextEditingController _textController = TextEditingController();

  // Knowledge file paths
  final List<String> _knowledgeFiles = [
    "lib/data/uc_regulation.json",
    "lib/data/uc_scholarship.json",
    "lib/data/uc_pmb25_administration.json",
    "lib/data/uc_pmb25_contohTes.json"
  ];

  // List to store chat history
  final List<Map<String, dynamic>> _chatHistory = [];

  String _recognizedText = "";
  // String _response = "";
  bool _isProcessing = false;
  bool _isListening = false;

  double _containerHeight = 300.0; 

  @override
  void initState() {
    super.initState();
  }


  void _handleSpeechResult(String result) {
    setState(() {
      _recognizedText = result;
    });
  }

  void _addMessage(String text, bool isUser) {
    setState(() {
      _chatHistory.add({'text': text, 'isUser': isUser});
    });
  }


  // Process query using YuccaKnowledgeService from json file
  Future<void> _processQuery(String query) async {
    setState(() {
      _isProcessing = true;
    });
    try {
      await _speechService.stopSpeaking();

      _addMessage(query, true); // Add user query to chat history

      String response = await YuccaKnowledgeService.processAndQuery(
        _knowledgeFiles, query);

      // Unescape the response before adding it to chat history
      String unescapedResponse = _unescape.convert(response);

      _addMessage(unescapedResponse, false); // Add AI response to chat history

      await _speechService.speak(unescapedResponse);
    } catch (e) {
      String errorMessage = "Error: Unable to process query.";
      _addMessage(errorMessage, false); // Add error message to chat history
      print("Error: $e");
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }


  // Toggle listening state and process speech-to-text input
  void _toggleListening() async {
    if (_isListening) {
      _speechService.stopListening();
      setState(() {
        _isListening = false;
      });

      if (_recognizedText.isNotEmpty) {
        await _processQuery(_recognizedText);
        setState(() {
          _recognizedText = ""; // Clear recognized text after processing
        });
      }
    } else {
      try {
        bool available = await _speechService.initialize(onResult: (result) {
          setState(() {
            _recognizedText = result;
          });
        });
        if (available) {
          _speechService.startListening(_handleSpeechResult);
          setState(() {
            _isListening = true;
          });
        } else {
          _addMessage("Speech recognition not available.", false);
        }
      } catch (e) {
        print("Error starting speech recognition: $e");
      }
    }
  }

  Future<void> _speakResponse(String response) async {
    try {
      await _speechService.speak(response);
    } catch (e) {
      print("Error speaking response: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: Text(
            "AI Yucca",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          backgroundColor: Colors.orange,
        ),
        body: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Container(
                    child: Center(
                      child: ModelViewer(
                        src: 'lib/assets/yucca_char.glb',
                        alt: "A 3D character model",
                        autoRotate: false,
                        autoRotateDelay: 0,
                        cameraControls: true,
                        ar: true,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: FloatingActionButton(
                      onPressed: _toggleListening,
                      child: Icon(_isListening ? Icons.stop : Icons.mic),
                      backgroundColor: Colors.orange,
                      shape: CircleBorder(),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onVerticalDragUpdate: (details) {
                setState(() {
                  _containerHeight -= details.delta.dy;
                  _containerHeight = _containerHeight.clamp(
                      100.0, MediaQuery.of(context).size.height / 2);
                });
              },
              child: Container(
                height: _containerHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(30),
                    topRight: Radius.circular(30),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2.5),
                        ),
                        margin: EdgeInsets.only(bottom: 10),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _chatHistory.length,
                          itemBuilder: (context, index) {
                            final message = _chatHistory[index];
                            return ChatBubble(
                              text: message['text'],
                              isUser: message['isUser'],
                              onSpeak: message['isUser']
                                  ? null
                                  : () => _speakResponse(message['text']),
                            );
                          },
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _textController,
                              decoration: InputDecoration(
                                hintText: "Type your query",
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                filled: true,
                                fillColor: Colors.grey.shade200,
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          _isProcessing
                              ? CircularProgressIndicator()
                              : IconButton(
                                  icon: Icon(Icons.send),
                                  color: Colors.orange,
                                  onPressed: () {
                                    if (_textController.text.isNotEmpty) {
                                      _processQuery(_textController.text);
                                      _textController.clear();
                                    }
                                  },
                                ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final VoidCallback? onSpeak;

  const ChatBubble({
    Key? key,
    required this.text,
    required this.isUser,
    this.onSpeak,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              margin: EdgeInsets.symmetric(vertical: 5),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isUser ? Colors.orange.shade300 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                text,
                style: TextStyle(color: isUser ? Colors.white : Colors.black),
              ),
            ),
          ),
          if (!isUser && onSpeak != null)
            IconButton(
              icon: Icon(Icons.volume_up),
              color: Colors.orange,
              onPressed: onSpeak,
            ),
        ],
      ),
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}
