import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_sound/flutter_sound.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechService {
  final SpeechToText _speechToText = SpeechToText();
  final String _typecastApiUrl = "https://typecast.ai/api/speak";
  
  final String _typecastApiKey = "your_typecast_API_key"; // can't commit secret

  /// Maximum number of polling attempts
  static const int _maxPollingAttempts = 10;

  /// Delay between polling attempts in milliseconds
  static const int _pollingDelay = 1000;

  bool _isListening = false;
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  bool _isPlayerInitialized = false;

  /// Initializes the player
  Future<void> initializePlayer() async {
    if (!_isPlayerInitialized) {
      try {
        await _audioPlayer.openPlayer();
        _isPlayerInitialized = true;
        print("Audio player initialized successfully.");
      } catch (e) {
        print("Error initializing audio player: $e");
        _isPlayerInitialized = false;
      }
    }
  }

  /// Disposes the player when it's no longer needed
  Future<void> dispose() async {
    try {
      if (_isPlayerInitialized) {
        await _audioPlayer.closePlayer();
        _isPlayerInitialized = false;
      }
    } catch (e) {
      print("Error disposing audio player: $e");
    }
  }

  /// Fetches the audio content using the v2 API
  Future<String?> _getV2AudioUrl(String speakId) async {
    try {
      final v2Url = 'https://typecast.ai/api/speak/v2/$speakId';
      print("Fetching V2 audio from: $v2Url");
      print("Using Authorization header: Bearer $_typecastApiKey");

      final response = await http.get(
        Uri.parse(v2Url),
        headers: {
          'Authorization': 'Bearer $_typecastApiKey',
          'Accept': 'application/json',
        },
      );

      print("V2 Response status: ${response.statusCode}");
      print("V2 Response headers: ${response.headers}");
      print("V2 Response body: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print("Parsed V2 response data: $responseData");
        final audioUrl = responseData['url'];
        if (audioUrl != null && audioUrl.isNotEmpty) {
          print("Retrieved V2 audio URL: $audioUrl");
          return audioUrl;
        }
      }
      print("Error: No valid audio URL in V2 response");
      return null;
    } catch (error) {
      print("Error getting V2 audio: $error");
      print("Error stack trace: ${StackTrace.current}");
      return null;
    }
  }

  /// Polls the V2 API until the audio is ready
  Future<String?> _pollForAudio(String speakId) async {
  int attempts = 0;

  while (attempts < _maxPollingAttempts) {
    try {
      final v2Url = 'https://typecast.ai/api/speak/v2/$speakId';
      print("Polling attempt ${attempts + 1} for audio at: $v2Url");

      final response = await http.get(
        Uri.parse(v2Url),
        headers: {
          'Authorization': 'Bearer $_typecastApiKey',
          'Accept': 'application/json',
        },
      );

      print("Poll response status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print("Poll response data: $responseData");

        final result = responseData['result'];
        final status = result['status'];

        if (status == 'done') {
          final audioUrl = result['audio_download_url'];
          if (audioUrl != null && audioUrl.isNotEmpty) {
            print("Audio is ready! URL: $audioUrl");
            return audioUrl;
          }
        } else if (status == 'error') {
          print(
              "Error in audio generation: ${result['callback']['error_msg']}");
          return null;
        } else if (status == 'progress') {
          print("Audio still generating... waiting");
          await Future.delayed(Duration(milliseconds: _pollingDelay));
          attempts++;
          continue;
        }
      }

      // If we get here, something unexpected happened
      print("Unexpected response structure");
      return null;
    } catch (error) {
      print("Error during polling: $error");
      return null;
    }
  }

  print("Polling timeout after $attempts attempts");
  return null;
}


  /// Converts the given [text] to speech using Typecast API
  Future<void> speakWithTypecast(String text) async {
    try {
      // First request to generate the speech
      final response = await http.post(
        Uri.parse(_typecastApiUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_typecastApiKey',
        },
        body: jsonEncode({
          "actor_id": "62fb678f9b93d9207fa8c032",
          "text": text,
          "lang": "auto",
          "tempo": 1,
          "volume": 100,
          "pitch": 0,
          "xapi_hd": true,
          "max_seconds": 60,
          "model_version": "latest",
          "xapi_audio_format": "wav",
          "emotion_tone_preset": "normal-1",
        }),
      );

      print("Initial response body: ${response.body}");

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        final speakUrl = responseData['result']?['speak_v2_url'];

        if (speakUrl == null || speakUrl.isEmpty) {
          print("Error: speak_v2_url is null or empty.");
          return;
        }

        // Extract the speak ID from the URL
        final speakId = speakUrl.split('/').last;

        print("Starting polling for audio generation...");

        // Poll until the audio is ready
        final audioUrl = await _pollForAudio(speakId);

        if (audioUrl != null) {
          print("Playing audio from URL: $audioUrl");
          await playAudioFromUrl(audioUrl);
        } else {
          print("Failed to get audio URL after polling");
        }
      } else {
        print(
            "Error: Initial API request failed with status code ${response.statusCode}");
      }
    } catch (error) {
      print("Error in speakWithTypecast: $error");
    }
  }

  /// Plays audio from a given [url]
  Future<void> playAudioFromUrl(String url) async {
    try {
      // Ensure player is initialized
      if (!_isPlayerInitialized) {
        await initializePlayer();
      }

      // Stop any currently playing audio
      if (_audioPlayer.isPlaying) {
        await _audioPlayer.stopPlayer();
      }

      print("Starting playback from URL: $url");

      // Start playing the audio from the URL
      await _audioPlayer.startPlayer(
        fromURI: url,
        whenFinished: () {
          print("Audio playback finished.");
        },
      );
    } catch (error) {
      print("Error playing audio: $error");
      // Try to recover by reinitializing the player
      _isPlayerInitialized = false;
      await initializePlayer();
    }
  }

  /// Stops the currently playing audio
  Future<void> stopSpeaking() async {
    try {
      if (_isPlayerInitialized && _audioPlayer.isPlaying) {
        await _audioPlayer.stopPlayer();
        print("Audio stopped.");
      }
    } catch (error) {
      print("Error stopping audio: $error");
    }
  }

  /// Initializes the speech-to-text service
  Future<bool> initialize({required Function(String) onResult}) async {
    bool available = await _speechToText.initialize(
      onStatus: (status) => print('Speech status: $status'),
      onError: (error) => print('Speech error: $error'),
    );
    if (available) {
      _speechToText.listen(onResult: (result) {
        onResult(result.recognizedWords);
      });
    }
    return available;
  }

  /// Starts listening and passes the recognized words to the [onResult] callback
  void startListening(Function(String) onResult) {
    if (!_isListening) {
      _speechToText.listen(onResult: (result) {
        onResult(result.recognizedWords);
      });
      _isListening = true;
    } else {
      print("Already listening.");
    }
  }

  /// Stops the speech-to-text listening
  void stopListening() {
    if (_isListening) {
      _speechToText.stop();
      _isListening = false;
    } else {
      print("Not currently listening.");
    }
  }

  /// A new method that directly speaks the response text
  Future<void> speak(String response) async {
    await speakWithTypecast(response);
  }
}
