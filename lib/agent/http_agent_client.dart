import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'agent_client.dart';
import 'intent/pending_clarification.dart';
import 'models/agent_context_snapshot.dart';
import 'models/agent_message.dart';
import 'models/agent_response.dart';

/// 通过 HTTP 调用 FitForge Coach Agent 后端的 [AgentClient] 实现。
///
/// 默认 POST 到 `<baseUrl>/v1/coach/message`，请求 body 为：
///
/// ```json
/// {
///   "message": "...",
///   "context": { ...AgentContextSnapshot.toJson() },
///   "history": [ { "role": "...", "content": "..." }, ... ]
/// }
/// ```
class HttpAgentClient implements AgentClient {
  HttpAgentClient({
    required this.baseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 30),
    this.path = '/v1/coach/message',
  }) : _client = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  final String baseUrl;
  final String path;
  final http.Client _client;
  final bool _ownsClient;
  final Duration timeout;

  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  Future<AgentResponse> sendMessage({
    required String message,
    required AgentContextSnapshot context,
    required List<AgentMessage> history,
    PendingClarification? pendingClarification,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final body = jsonEncode({
      'message': message,
      'context': context.toJson(),
      'history': history.map(_historyMessageToJson).toList(),
    });

    try {
      final response = await _client
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpAgentException(
          'Coach 后端返回 HTTP ${response.statusCode}',
          statusCode: response.statusCode,
          responseBody: response.body,
        );
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const HttpAgentException('Coach 后端返回的不是合法 JSON 对象');
      }
      return AgentResponse.fromJson(decoded);
    } on TimeoutException {
      throw HttpAgentException('Coach 后端响应超时（${timeout.inSeconds} 秒）');
    } on FormatException catch (e) {
      throw HttpAgentException('Coach 后端返回了无法解析的响应：${e.message}');
    } on http.ClientException catch (e) {
      throw HttpAgentException('网络无法连接 Coach 后端：${e.message}');
    }
  }

  Map<String, dynamic> _historyMessageToJson(AgentMessage message) {
    final json = <String, dynamic>{
      'role': message.role.name,
      'content': message.content,
    };
    if (message.role == AgentMessageRole.assistant &&
        message.actions.isNotEmpty) {
      json['actions'] = message.actions
          .map(
            (action) => {
              'id': action.id,
              'type': action.type.name,
              'requiresConfirmation': action.requiresConfirmation,
            },
          )
          .toList();
    }
    return json;
  }
}

class HttpAgentException implements Exception {
  const HttpAgentException(this.message, {this.statusCode, this.responseBody});

  final String message;
  final int? statusCode;
  final String? responseBody;

  @override
  String toString() => message;
}
