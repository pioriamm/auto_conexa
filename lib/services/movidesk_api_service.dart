import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/movidesk_models.dart';

class MovideskApiService {
  Future<MovideskTicketInfo?> fetchTicketInfo(String cnpjFormatado, String token) async {
    if (token.isEmpty || cnpjFormatado.isEmpty) {
      return null;
    }

    final filter =
        "startswith(subject,'#Cobrança') and customFieldValues/any(cf: cf/customFieldId eq 90531 and cf/value eq '$cnpjFormatado')";

    final uri = Uri.https('api.movidesk.com', '/public/v1/tickets', {
      'token': token,
      r'$select': 'id,status',
      r'$filter': filter,
      r'$orderby': 'id desc',
      r'$top': '1',
    });

    const int maxAttempts = 3;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        final response = await http.get(uri);
        if (response.statusCode != 200) {
          if (response.statusCode >= 500 && attempt < maxAttempts) {
            await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
            continue;
          }
          throw ProcessingException(
            'Falha ao consultar o Movidesk (HTTP ${response.statusCode}). Confira se o token está correto e ativo.',
          );
        }

        if (response.body.trim().isEmpty) {
          throw const ProcessingException(
            'A API do Movidesk retornou resposta vazia. Tente novamente em alguns instantes.',
          );
        }

        final dynamic data;
        try {
          data = jsonDecode(response.body);
        } on FormatException {
          throw const ProcessingException(
            'A resposta do Movidesk veio em formato inválido. Tente novamente em alguns instantes.',
          );
        }

        if (data is! List) {
          throw const ProcessingException(
            'Formato de retorno inesperado do Movidesk. Verifique o token e tente novamente.',
          );
        }

        if (data.isEmpty) {
          return null;
        }

        final first = data.first;
        if (first is Map<String, dynamic>) {
          final id = first['id'] as int?;
          final status = first['status'];
          final statusLabel = status == null ? '' : status.toString();
          return MovideskTicketInfo(id: id, status: statusLabel);
        }
        throw const ProcessingException(
          'Não foi possível identificar o ticket retornado pelo Movidesk.',
        );
      } on ProcessingException {
        rethrow;
      } catch (_) {
        if (attempt == maxAttempts) {
          return null;
        }
        await Future<void>.delayed(Duration(milliseconds: 350 * attempt));
      }
    }
    return null;
  }

  Future<MovideskPersonInfo?> fetchPersonByBusinessName(String businessName, String token) async {
    final trimmed = businessName.trim();
    if (token.isEmpty || trimmed.isEmpty) {
      return null;
    }

    final escapedBusinessName = trimmed.replaceAll("'", "''");
    final uri = Uri.https('api.movidesk.com', '/public/v1/persons', {
      'token': token,
      r'$select': 'id,businessName,personType,profileType',
      r'$filter': "businessName eq '$escapedBusinessName'",
      r'$top': '1',
    });

    final response = await http.get(uri);
    if (response.statusCode != 200 || response.body.trim().isEmpty) {
      return null;
    }

    final dynamic data = jsonDecode(response.body);
    if (data is! List || data.isEmpty) {
      return null;
    }

    final first = data.first;
    if (first is! Map<String, dynamic>) {
      return null;
    }

    final id = first['id']?.toString() ?? '';
    if (id.isEmpty) return null;

    return MovideskPersonInfo(
      id: id,
      businessName: first['businessName']?.toString() ?? trimmed,
      personType: (first['personType'] as num?)?.toInt() ?? 2,
      profileType: (first['profileType'] as num?)?.toInt() ?? 2,
    );
  }

  Future<MovideskTicketInfo?> createTicket({
    required String token,
    required MovideskPersonInfo person,
    required String cnpj,
    required String razaoSocial,
    required String idCobranca,
    required String email,
    required String telefone,
    required DateTime? dataVencimento,
  }) async {
    if (token.isEmpty) return null;
    final uri = Uri.https('api.movidesk.com', '/public/v1/tickets', {
      'token': token,
    });

    final payload = <String, dynamic>{
      'subject': '#Cobrança - $razaoSocial',
      'type': 2,
      'origin': 2,
      'status': 'Iniciar Atendimento',
      'category': '03. Financeiro',
      'serviceThirdLevelId': 800889,
      'createdBy': {'id': '1382851390'},
      'owner': {'id': '98745869'},
      'ownerTeam': 'Financeiro',
      'clients': [
        {
          'id': person.id,
          'personType': person.personType,
          'profileType': person.profileType,
        }
      ],
      'customFieldValues': [
        {'customFieldId': 90531, 'customFieldRuleId': 82697, 'line': 1, 'value': cnpj},
        {'customFieldId': 91806, 'customFieldRuleId': 82697, 'line': 1, 'value': razaoSocial},
        {'customFieldId': 92031, 'customFieldRuleId': 77836, 'line': 1, 'value': idCobranca},
        {'customFieldId': 21504, 'customFieldRuleId': 18775, 'line': 1, 'value': email},
        {'customFieldId': 21503, 'customFieldRuleId': 18775, 'line': 1, 'value': telefone},
        {
          'customFieldId': 240980,
          'customFieldRuleId': 77836,
          'line': 1,
          'value': _formatMovideskDate(dataVencimento),
        },
      ],
      'actions': [
        {'type': 2, 'description': 'ticket criado via automação'}
      ],
    };

    final response = await http.post(
      uri,
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode != 200 && response.statusCode != 201) {
      return null;
    }
    if (response.body.trim().isEmpty) return null;

    final dynamic data = jsonDecode(response.body);
    if (data is! Map<String, dynamic>) return null;
    final id = (data['id'] as num?)?.toInt();
    if (id == null) return null;
    final status = data['status']?.toString() ?? 'Iniciar Atendimento';
    return MovideskTicketInfo(id: id, status: status);
  }

  Future<MovideskTicketInfo?> createOrFetchTicketAfterCreate({
    required String token,
    required MovideskPersonInfo person,
    required String cnpj,
    required String razaoSocial,
    required String idCobranca,
    required String email,
    required String telefone,
    required DateTime? dataVencimento,
  }) async {
    final createdTicket = await createTicket(
      token: token,
      person: person,
      cnpj: cnpj,
      razaoSocial: razaoSocial,
      idCobranca: idCobranca,
      email: email,
      telefone: telefone,
      dataVencimento: dataVencimento,
    );
    if (createdTicket?.id != null) {
      return createdTicket;
    }

    const retryDelays = [
      Duration(milliseconds: 400),
      Duration(milliseconds: 900),
      Duration(milliseconds: 1500),
      Duration(milliseconds: 2500),
      Duration(milliseconds: 3500),
    ];
    for (final delay in retryDelays) {
      await Future<void>.delayed(delay);
      final fetchedTicket = await fetchTicketInfo(cnpj, token);
      if (fetchedTicket?.id != null) {
        return fetchedTicket;
      }
    }
    return createdTicket;
  }

  String _formatMovideskDate(DateTime? date) {
    if (date == null) return '';
    final yyyy = date.year.toString().padLeft(4, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd 00:00:00';
  }
}
