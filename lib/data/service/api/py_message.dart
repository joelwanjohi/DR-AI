import 'dart:developer';
import 'package:google_generative_ai/google_generative_ai.dart';

class GenerativeAiWebService {
  static final apiKey = 'AIzaSyC0mgALAiYmKS40QXu7dSX9tyEtoj1TY24';
  static late GenerativeModel model;

  static Future<void> initialize() async {
    try {
      // Initialize the model
      model = GenerativeModel(
        model: 'gemini-1.5-flash-latest',
        apiKey: apiKey,
      );
      log('Gemini AI model initialized successfully');
    } catch (e) {
      log('Error initializing Gemini AI model: $e');
      rethrow;
    }
  }

  static Future<String?> postData({required String text}) async {
    try {
      // Initialize the model if not already initialized
      if (model == null) {
        await initialize();
      }

      // Generate content with the model
      final content = await model.generateContent(text as Iterable<Content>);
      
      // Return the generated response
      return content.text;
    } catch (e) {
      log('Error generating AI response: $e');
      return Future.error("Gemini API error: $e", StackTrace.current);
    }
  }
}