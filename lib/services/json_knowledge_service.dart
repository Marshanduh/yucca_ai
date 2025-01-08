import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:html_unescape/html_unescape.dart';

class YuccaKnowledgeService {
  static const String apiUrl = "https://api.openai.com/v1/chat/completions";
  static final HtmlUnescape _unescape = HtmlUnescape();

  /// Load multiple JSON knowledge bases from assets and merge them.
  static Future<Map<String, dynamic>> loadKnowledgeBases(
      List<String> assetPaths) async {
    Map<String, dynamic> mergedKnowledgeBase = {};

    for (String assetPath in assetPaths) {
      try {
        final String jsonString = await rootBundle.loadString(assetPath);
        Map<String, dynamic> knowledgeBase = jsonDecode(jsonString);

        // Merge the content (you can adjust how you want to merge the knowledge)
        mergedKnowledgeBase.addAll(knowledgeBase);
      } catch (e) {
        throw Exception(
            'Failed to load JSON knowledge base from $assetPath: $e');
      }
    }

    return mergedKnowledgeBase;
  }

  /// Splits content into manageable chunks to handle token limits.
  static List<String> splitIntoChunks(String content, {int chunkSize = 2000}) {
    if (content.isEmpty) {
      throw Exception(
          'Knowledge base content is empty. Cannot split into chunks.');
    }

    List<String> chunks = [];
    for (var i = 0; i < content.length; i += chunkSize) {
      chunks.add(content.substring(
        i,
        i + chunkSize > content.length ? content.length : i + chunkSize,
      ));
    }
    return chunks;
  }

  /// Decode special characters and clean up the text, removing formatting.
  static String _cleanResponse(String text) {
    // Unescape HTML entities
    String cleaned = _unescape.convert(text);

    // Remove Markdown formatting like bold, italics, etc.
    cleaned = cleaned.replaceAll(
        RegExp(r'(\*\*|\*|__|_)'), ''); // Removing **, *, __, _
    cleaned = cleaned.replaceAll(
        RegExp(r'(```.*?```)', dotAll: true), ''); // Removing code blocks
    cleaned = cleaned.replaceAll(RegExp(r'`.*?`'), ''); // Removing inline code

    // Remove any remaining stray characters (if needed)
    cleaned =
        cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), ''); // Non-ASCII characters

    return cleaned.trim();
  }

  /// Queries OpenAI with JSON knowledge and a user question.
  static Future<String> fetchResponseWithKnowledge(
      Map<String, dynamic> knowledgeBase, String question) async {
    final apiKey = "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"; // (punya marsha)
    

    if (apiKey.isEmpty) {
      throw Exception('API key is empty. Please provide a valid API key.');
    }

    int retryCount = 0;
    const maxRetries = 5;

    while (retryCount < maxRetries) {
      try {
        final response = await http.post(
          Uri.parse(apiUrl),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: json.encode({
            'model': 'gpt-4o-mini',
            'messages': [
              {
                'role': 'system',
                'content': '''
You are Yuca, a cheerful, expressive, and knowledgeable assistant specializing in Universitas Ciputra topics. Your tone should be lively, engaging, and human-like, with responses that are concise and casual. Avoid long explanations unless explicitly requested. If the query is unrelated to the provided knowledge base, politely acknowledge it and avoid giving irrelevant information.
'''
              },
              {
                'role': 'user',
                'content': '''
Knowledge Base: ${jsonEncode(knowledgeBase)}

Question: $question

Respond based on the provided JSON knowledge base about Universitas Ciputra, including courses, events, and campus facilities. Keep your response brief and casual. If the question is unrelated to the knowledge base, reply politely and avoid providing unrelated information.
'''
              }
            ],
          }),
        );

        if (response.statusCode == 200) {
          // Decode response body to handle encoding issues
          final String rawResponse = utf8.decode(response.bodyBytes);
          final data = json.decode(rawResponse);

          if (data.containsKey('choices') && data['choices'].isNotEmpty) {
            final rawText = data['choices'][0]['message']['content'] ??
                'No response content found.';
            // Clean and decode the response before returning
            return _cleanResponse(rawText);
          } else {
            throw Exception('Invalid response format from OpenAI.');
          }
        } else if (response.statusCode == 429) {
          retryCount++;
          int waitTime = retryCount * 2; // Exponential backoff
          print("Rate limit exceeded. Retrying in $waitTime seconds...");
          await Future.delayed(Duration(seconds: waitTime));
        } else {
          throw Exception(
              'Failed to fetch response. HTTP Status: ${response.statusCode}');
        }
      } catch (e) {
        retryCount++;
        if (retryCount >= maxRetries) {
          throw Exception('Error after $maxRetries retries: $e');
        }
        print('Retrying due to error: $e');
      }
    }

    throw Exception(
        'Rate limit exceeded after $maxRetries retries. Please try again later.');
  }

  /// Processes the JSON knowledge base and queries OpenAI.
  static Future<String> processAndQuery(
      List<String> jsonPaths, String question) async {
    try {
      print('Loading JSON knowledge base...');
      final knowledgeBase = await loadKnowledgeBases(jsonPaths);

      print('Querying OpenAI with the knowledge base...');
      final response =
          await fetchResponseWithKnowledge(knowledgeBase, question);

      // Clean the response one final time before returning
      return _cleanResponse(response);
    } catch (e) {
      print('Error occurred: $e');

      // If knowledge base fails, query OpenAI with a default system message
      final response = await fetchResponseWithKnowledge({}, question);
      return _cleanResponse(response);
    }
  }
}
