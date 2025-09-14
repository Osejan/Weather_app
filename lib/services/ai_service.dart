// lib/services/ai_service.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class AIService {
  static Future<String> getTripRecommendations({
    required String origin,
    required String destination,
    required DateTime date,
  }) async {
    final url = Uri.parse("https://api.openai.com/v1/chat/completions");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer ${ApiKeys.oenAiKey}",
      },
      body: jsonEncode({
        "model": "gpt-4o-mini",
        "messages": [
          {
            "role": "system",
            "content": "You are a travel assistant that provides smart suggestions."
          },
          {
            "role": "user",
            "content":
                "I am planning a trip from $origin to $destination on ${date.toLocal()}. "
                "Suggest useful things to carry, highlight potential weather issues, and warn me if any route hazards exist."
          }
        ],
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data["choices"][0]["message"]["content"];
    } else {
      throw Exception("AI API error: ${response.body}");
    }
  }
}

