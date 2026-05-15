part of '../views/pages/home_pages.dart';





class ChargeDateResult {
  const ChargeDateResult({
    required this.date,
    required this.wasTransferred,
  });

  final DateTime date;
  final bool wasTransferred;
}

// =============================================================================
// Utilitários
// =============================================================================

String digitsOnly(String input) => input.replaceAll(RegExp(r'\D'), '');

DateTime? _parseFlexibleDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;

  final iso = DateTime.tryParse(text);
  if (iso != null) return DateTime(iso.year, iso.month, iso.day);

  final brMatch = RegExp(r'^(\d{1,2})/(\d{1,2})/(\d{4})$').firstMatch(text);
  if (brMatch != null) {
    final day = int.parse(brMatch.group(1)!);
    final month = int.parse(brMatch.group(2)!);
    final year = int.parse(brMatch.group(3)!);
    return DateTime(year, month, day);
  }

  final serial = double.tryParse(text.replaceAll(',', '.'));
  if (serial != null) {
    final excelEpoch = DateTime(1899, 12, 30);
    final parsed = excelEpoch.add(Duration(days: serial.floor()));
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  return null;
}

ChargeDateResult _adjustToNextBusinessDay(DateTime date) {
  var adjusted = DateTime(date.year, date.month, date.day);
  var wasTransferred = false;

  while (_isWeekend(adjusted) || _isBrazilNationalHoliday(adjusted)) {
    adjusted = adjusted.add(const Duration(days: 1));
    wasTransferred = true;
  }

  return ChargeDateResult(date: adjusted, wasTransferred: wasTransferred);
}

bool _isWeekend(DateTime date) {
  return date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
}

bool _isBrazilNationalHoliday(DateTime date) {
  final d = DateTime(date.year, date.month, date.day);
  final easter = _easterSunday(d.year);

  final holidays = <DateTime>{
    DateTime(d.year, 1, 1),
    DateTime(d.year, 4, 21),
    DateTime(d.year, 5, 1),
    DateTime(d.year, 9, 7),
    DateTime(d.year, 10, 12),
    DateTime(d.year, 11, 2),
    DateTime(d.year, 11, 15),
    DateTime(d.year, 11, 20),
    DateTime(d.year, 12, 25),
    easter.subtract(const Duration(days: 48)),
    easter.subtract(const Duration(days: 47)),
    easter.subtract(const Duration(days: 2)),
    easter,
    easter.add(const Duration(days: 60)),
  };

  return holidays.contains(d);
}

DateTime _easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;

  return DateTime(year, month, day);
}

String formattedCnpj(String digits) {
  if (digits.length != 14) {
    return digits;
  }
  return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12, 14)}';
}

String normalizeEmails(String input) {
  final matches = RegExp(
    r'[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}',
    caseSensitive: false,
  ).allMatches(input);

  final emails = <String>{};
  for (final match in matches) {
    final email = match.group(0);
    if (email == null) continue;
    emails.add(email.toLowerCase());
  }

  return emails.join('; ');
}

String formatFirstPhone(String input) {
  if (input.trim().isEmpty) return '';

  final match = RegExp(r'\d{10,11}').firstMatch(digitsOnly(input));
  final digits = match?.group(0) ?? '';

  if (digits.length == 11) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 7)}-${digits.substring(7, 11)}';
  }
  if (digits.length == 10) {
    return '(${digits.substring(0, 2)}) ${digits.substring(2, 6)}-${digits.substring(6, 10)}';
  }

  return '';
}

// =============================================================================
// Parsing de planilhas (funções top-level para uso com compute/isolate)
// =============================================================================

/// Tenta fazer o decode do Excel de forma segura.
excel.Excel _decodeExcel(Uint8List bytes) {
  try {
    return excel.Excel.decodeBytes(bytes);
  } catch (e) {
    throw const ProcessingException(
      'Não foi possível abrir o arquivo. '
      'Abra-o no Excel ou LibreOffice, salve novamente como .xlsx e tente outra vez.',
    );
  }
}

/// Cede o controle ao event loop para a UI poder renderizar um frame.
Future<void> _yield() => Future<void>.delayed(Duration.zero);

typedef ProgressCallback = void Function(int current, int total);

Future<Map<String, LocalizaRow>> parseLocalizaBytes(
  Uint8List bytes, {
  ProgressCallback? onProgress,
}) async {
  await _yield();
  final excel = _decodeExcel(bytes);
  await _yield();

  if (excel.tables.isEmpty) {
    throw const ProcessingException(
      'A planilha Localiza está vazia ou sem aba válida.',
    );
  }

  final table = excel.tables.values.first;
  if (table.maxRows == 0) {
    throw const ProcessingException('A planilha Localiza está vazia.');
  }

  final header = _headerMap(table.rows.first);
  final cnpjCol = _findColumn(header, ['CNPJ', 'CNPJ/CPF', 'cpfcnpj']);
  final grupoCol = _findColumn(header, ['Grupo']);
  final modalidadeCol = _findColumn(header, ['Modalidade']);

  if (cnpjCol == null || grupoCol == null || modalidadeCol == null) {
    throw const ProcessingException(
      'A planilha Localiza precisa conter colunas de CNPJ/CPF, Grupo e Modalidade.',
    );
  }

  final total = table.rows.length - 1;
  onProgress?.call(0, total);

  final map = <String, LocalizaRow>{};
  for (var i = 1; i < table.rows.length; i++) {
    if (i % 100 == 0) {
      onProgress?.call(i, total);
      await _yield();
    }
    try {
      final row = table.rows[i];
      final cnpj = digitsOnly(_cellValue(row, cnpjCol));
      if (cnpj.isEmpty) continue;

      map.putIfAbsent(
        cnpj,
        () => LocalizaRow(
          cnpj: cnpj,
          grupo: _cellValue(row, grupoCol),
          modalidade: _cellValue(row, modalidadeCol),
        ),
      );
    } catch (_) {
      continue;
    }
  }

  onProgress?.call(total, total);
  return map;
}

Future<List<ConexaRow>> parseConexaBytes(
  Uint8List bytes, {
  ProgressCallback? onProgress,
}) async {
  await _yield();
  final excel = _decodeExcel(bytes);
  await _yield();

  if (excel.tables.isEmpty) {
    throw const ProcessingException(
      'A planilha Conexa está vazia ou sem aba válida.',
    );
  }

  final table = excel.tables.values.first;
  if (table.maxRows == 0) {
    throw const ProcessingException('A planilha Conexa está vazia.');
  }

  final header = _headerMap(table.rows.first);
  final idCol = _findColumn(header, ['ID da Cobrança', 'idcobranca']);
  final cpfCnpjCol = _findColumn(header, ['CPF/CNPJ', 'cpf/cnpj']);
  final razaoCol =
      _findColumn(header, ['Razão Social Cliente', 'razaosocial']);
  final valorCol = _findColumn(header, ['Valor']);
  final vencimentoCol = _findColumn(header, ['Vencimento']);
  final emailsCol = _findColumn(header, ['Emails', 'E-mails', 'Email']);
  final telefoneCol = _findColumn(header, ['Telefone', 'Telefones', 'Celular']);

  if (idCol == null ||
      cpfCnpjCol == null ||
      razaoCol == null ||
      valorCol == null ||
      vencimentoCol == null ||
      emailsCol == null ||
      telefoneCol == null) {
    throw const ProcessingException(
      'A planilha Conexa precisa conter: ID da Cobrança, CPF/CNPJ, Razão Social Cliente, Valor, Vencimento, Emails e Telefone.',
    );
  }

  final total = table.rows.length - 1;
  onProgress?.call(0, total);

  final rows = <ConexaRow>[];
  for (var i = 1; i < table.rows.length; i++) {
    if (i % 100 == 0) {
      onProgress?.call(i, total);
      await _yield();
    }
    try {
      final row = table.rows[i];
      final cpfCnpj = _cellValue(row, cpfCnpjCol);
      if (digitsOnly(cpfCnpj).isEmpty) continue;

      rows.add(
        ConexaRow(
          idCobranca: _cellValue(row, idCol),
          cpfCnpj: cpfCnpj,
          razaoSocialCliente: _cellValue(row, razaoCol),
          valor: _cellValue(row, valorCol),
          vencimento: _cellValue(row, vencimentoCol),
          emails: _cellValue(row, emailsCol),
          telefone: _cellValue(row, telefoneCol),
        ),
      );
    } catch (_) {
      continue;
    }
  }

  onProgress?.call(total, total);
  return rows;
}

const Map<String, String> _servicoItemDePara = {
  'cobranca parceiro': 'Cobrança Parceiro',
  'mensal': 'Mensal',
  'treinamento por hora': 'Treinamento por Hora',
  'taxa adesao': 'Taxa Adesão',
  'recorrencia': 'Mensal',
  'treinamento especializado': 'Treinamento Especializado',
  '1 recorrencia': '1º recorrencia',
  '1o recorrencia': '1º recorrencia',
  '1º recorrencia': '1º recorrencia',
};

String _mapServicoItem(String raw) {
  final normalized = normalizeKey(raw).replaceAll('º', 'o');
  for (final entry in _servicoItemDePara.entries) {
    if (normalized.contains(normalizeKey(entry.key))) {
      return entry.value;
    }
  }
  return raw.trim();
}

Future<Map<String, String>> parseAdminVendaBytes(Uint8List bytes) async {
  await _yield();
  final file = _decodeExcel(bytes);
  if (file.tables.isEmpty) {
    throw const ProcessingException('A planilha Admin Venda está vazia.');
  }
  final table = file.tables.values.first;
  if (table.rows.isEmpty) {
    throw const ProcessingException('A planilha Admin Venda está vazia.');
  }

  final header = _headerMap(table.rows.first);
  final clienteIdCol = _findColumn(header, ['Cliente ID', 'ID Cliente']);
  final servicoItemCol = _findColumn(header, ['Serviço/Item', 'Servico/Item']);
  if (clienteIdCol == null || servicoItemCol == null) {
    throw const ProcessingException(
      'A planilha Admin Venda precisa conter as colunas Cliente ID e Serviço/Item.',
    );
  }

  final mapped = <String, String>{};
  for (var i = 1; i < table.rows.length; i++) {
    final row = table.rows[i];
    final clienteId = _cellValue(row, clienteIdCol);
    final servicoItem = _mapServicoItem(_cellValue(row, servicoItemCol));
    if (servicoItem.isEmpty) continue;
    for (final key in clientIdLookupKeys(clienteId)) {
      mapped[key] = servicoItem;
    }
  }
  return mapped;
}

List<String> _adminCobrancaColumnCandidates(String column) {
  switch (column) {
    case 'ID Cliente':
      return ['ID Cliente', 'Cliente ID'];
    case 'CPF/CNPJ':
      return ['CPF/CNPJ', 'CNPJ/CPF', 'CPF CNPJ', 'CNPJ CPF'];
    default:
      return [column];
  }
}

Future<List<AdminCobrancaRow>> parseAdminCobrancaBytes(Uint8List bytes) async {
  await _yield();
  final file = _decodeExcel(bytes);
  if (file.tables.isEmpty) {
    throw const ProcessingException('A planilha Admin Cobrança está vazia.');
  }
  final table = file.tables.values.first;
  if (table.rows.isEmpty) {
    throw const ProcessingException('A planilha Admin Cobrança está vazia.');
  }

  final header = _headerMap(table.rows.first);
  final columnIndexes = <String, int>{};
  for (final col in AdminCobrancaRow.columns) {
    final index = _findColumn(header, _adminCobrancaColumnCandidates(col));
    if (index != null) {
      columnIndexes[col] = index;
    }
  }

  if (!columnIndexes.containsKey('ID Cliente')) {
    throw const ProcessingException(
      'A planilha Admin Cobrança precisa conter a coluna ID Cliente.',
    );
  }


  final rows = <AdminCobrancaRow>[];
  for (var i = 1; i < table.rows.length; i++) {
    final source = table.rows[i];
    final values = <String, String>{};
    for (final col in AdminCobrancaRow.columns) {
      final index = columnIndexes[col];
      values[col] = index == null ? '' : _cellValue(source, index);
    }
    if ((values['ID Cliente'] ?? '').trim().isEmpty) continue;
    rows.add(AdminCobrancaRow(values));
  }
  return rows;
}

Future<Map<String, LinhaDetalhaTenex>> parseClientesDetalhesBytes(
    Uint8List bytes,
    ) async {
  await _yield();
  final file = _decodeExcel(bytes);
  if (file.tables.isEmpty) {
    throw const ProcessingException('A planilha Tenex está vazia.');
  }
  final table = file.tables.values.first;
  if (table.rows.isEmpty) {
    throw const ProcessingException('A planilha Tenex está vazia.');
  }

  final header = _headerMap(table.rows.first);

  // Aceita variações com/sem espaço, case e acentos diferentes.
  final idCol = _findColumn(header, [
    'id',
    'ID',
    'ID Cliente',
    'Cliente ID',
    'idCliente',
    'id_cliente',
  ]);
  final grupoCol = _findColumn(header, ['grupo', 'Grupo']);
  final vendedorCol = _findColumn(header, [
    'vendedor',
    'Vendedor',
    'Nome Vendedor',
    'Vendedor Responsável',
    'Consultor',
  ]);
  final parceiroCol = _findColumn(header, [
    'parceiro',
    'Parceiro',
    'Nome Parceiro',
    'Cobrança Parceiro',
    'Cobranca Parceiro',
  ]);
  final customSistemaCol = _findColumn(header, [
    'custom sistema',
    'Custom Sistema',
    'customSistema',
    'Custom_sistema',
    'custom_sistema',
    'Custom',
    'Sistema',
    'Sistemas',
    'Nome Sistema',
  ]);
  final percentualComissaoCol = _findColumn(header, [
    '% comissão',
    '% comissao',
    'percentual comissão',
    'percentual comissao',
    'percentual',
    'porcentagem',
    'comissão',
    'comissao',
  ]);

  if (idCol == null ||
      grupoCol == null ||
      vendedorCol == null ||
      parceiroCol == null ||
      customSistemaCol == null) {
    throw ProcessingException(
      'A planilha Tenex precisa conter as colunas ID, Grupo, Vendedor, '
          'Parceiro e Custom Sistema. '
          'Detectado: id=$idCol, grupo=$grupoCol, vendedor=$vendedorCol, '
          'parceiro=$parceiroCol, customSistema=$customSistemaCol. '
          'Cabeçalho lido: ${header.keys.toList()}',
    );
  }

  print('=== PARSE TENEX ===');
  print('Header normalizado:');
  header.forEach((k, v) => print('  "$k" -> $v'));
  print('idCol=$idCol grupoCol=$grupoCol vendedorCol=$vendedorCol parceiroCol=$parceiroCol customSistemaCol=$customSistemaCol percentualComissaoCol=$percentualComissaoCol');

  for (var i = 1; i < table.rows.length; i++) {
    final row = table.rows[i];
    final idRaw = _cellValue(row, idCol!);
    if (idRaw.contains('11567')) {
      print('=== LINHA 11567 (i=$i, tamanho=${row.length}) ===');
      for (var j = 0; j < row.length; j++) {
        print('  col $j: "${row[j]?.value}"');
      }
      break;
    }
  }
  final mapped = <String, LinhaDetalhaTenex>{};

  for (var i = 1; i < table.rows.length; i++) {
    final row = table.rows[i];
    final idRaw = _cellValue(row, idCol);
    final id = normalizeClientId(idRaw);
    if (id.isEmpty) continue;

    final candidate = LinhaDetalhaTenex(
      id: id,
      grupo: _cellValue(row, grupoCol).trim(),
      vendedor: _cellValue(row, vendedorCol).trim(),
      parceiro: _cellValue(row, parceiroCol).trim(),
      customSistema: _cellValue(row, customSistemaCol).trim(),
      percentualComissao: percentualComissaoCol == null
          ? ''
          : _cellValue(row, percentualComissaoCol).trim(),
    );

    // Gera todas as variantes de chave para o mesmo cliente.
    final keys = <String>{
      ...clientIdLookupKeys(idRaw),
      ...clientIdLookupKeys(id),
    }..removeWhere((k) => k.isEmpty);

    for (final key in keys) {
      final existing = mapped[key];
      if (existing == null ||
          _scoreLinhaTenex(candidate) > _scoreLinhaTenex(existing)) {
        mapped[key] = candidate;
      }
    }
  }

  return mapped;
}

/// Conta quantos campos relevantes (fora o `id`) estão preenchidos.
/// Usado para escolher a versão mais completa quando há duplicatas.
int _scoreLinhaTenex(LinhaDetalhaTenex l) {
  var score = 0;
  if (l.grupo.isNotEmpty) score++;
  if (l.vendedor.isNotEmpty) score++;
  if (l.parceiro.isNotEmpty) score++;
  if (l.customSistema.isNotEmpty) score++;
  if (l.percentualComissao.isNotEmpty) score++;
  return score;
}

// =============================================================================
// Parsing CSV (streaming linha-a-linha, memória constante)
// =============================================================================

String _decodeCsvText(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return latin1.decode(bytes);
  }
}

String _detectCsvSeparator(String text) {
  final sample = text.length > 2048 ? text.substring(0, 2048) : text;
  final nlIdx = sample.indexOf('\n');
  final firstLine = nlIdx < 0 ? sample : sample.substring(0, nlIdx);
  final semi = ';'.allMatches(firstLine).length;
  final comma = ','.allMatches(firstLine).length;
  final tab = '\t'.allMatches(firstLine).length;
  if (tab > semi && tab > comma) return '\t';
  if (semi >= comma) return ';';
  return ',';
}

List<String> _parseCsvLine(String line, String sep) {
  final fields = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  var i = 0;
  while (i < line.length) {
    final ch = line[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < line.length && line[i + 1] == '"') {
          buf.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
      } else {
        buf.write(ch);
        i++;
      }
    } else {
      if (ch == '"' && buf.isEmpty) {
        inQuotes = true;
        i++;
      } else if (ch == sep) {
        fields.add(buf.toString());
        buf.clear();
        i++;
      } else {
        buf.write(ch);
        i++;
      }
    }
  }
  fields.add(buf.toString());
  return fields;
}

Map<String, int> _csvHeaderMap(List<String> headerRow) {
  final map = <String, int>{};
  for (var i = 0; i < headerRow.length; i++) {
    final key = normalizeKey(headerRow[i]);
    if (key.isNotEmpty) map[key] = i;
  }
  return map;
}

int? _csvFindColumn(Map<String, int> header, List<String> candidates) {
  for (final candidate in candidates) {
    final normalized = normalizeKey(candidate);
    if (header.containsKey(normalized)) return header[normalized];
  }
  for (final entry in header.entries) {
    for (final candidate in candidates) {
      final normalized = normalizeKey(candidate);
      if (_isCompatibleHeaderKey(entry.key, normalized)) {
        return entry.value;
      }
    }
  }
  return null;
}

String _csvField(List<String> row, int index) {
  if (index < 0 || index >= row.length) return '';
  return row[index].trim();
}

/// Quebra o texto do CSV em linhas lógicas, respeitando quebras de linha
/// que estão dentro de campos com aspas (que devem ser preservadas como
/// parte do mesmo registro).
List<String> _csvSplitLogicalLines(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < normalized.length; i++) {
    final ch = normalized[i];

    if (ch == '"') {
      // Aspa escapada ("") dentro de campo — não muda o estado.
      if (inQuotes && i + 1 < normalized.length && normalized[i + 1] == '"') {
        buf.write('""');
        i++; // consome a segunda aspa
        continue;
      }
      inQuotes = !inQuotes;
      buf.write(ch);
    } else if (ch == '\n' && !inQuotes) {
      lines.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }

  if (buf.isNotEmpty) lines.add(buf.toString());
  return lines;
}

Future<Map<String, LocalizaRow>> parseLocalizaCsvBytes(
  Uint8List bytes, {
  ProgressCallback? onProgress,
}) async {
  await _yield();
  final text = _decodeCsvText(bytes);
  await _yield();

  final sep = _detectCsvSeparator(text);
  final lines = _csvSplitLogicalLines(text);
  await _yield();

  if (lines.isEmpty) {
    throw const ProcessingException('CSV do Localiza está vazio.');
  }

  final header = _csvHeaderMap(_parseCsvLine(lines.first, sep));
  final cnpjCol = _csvFindColumn(header, ['CNPJ', 'CNPJ/CPF', 'cpfcnpj']);
  final grupoCol = _csvFindColumn(header, ['Grupo']);
  final modalidadeCol = _csvFindColumn(header, ['Modalidade']);

  if (cnpjCol == null || grupoCol == null || modalidadeCol == null) {
    throw const ProcessingException(
      'O CSV do Localiza precisa conter colunas de CNPJ/CPF, Grupo e Modalidade.',
    );
  }

  final total = lines.length - 1;
  onProgress?.call(0, total);

  final map = <String, LocalizaRow>{};
  for (var i = 1; i < lines.length; i++) {
    if (i % 500 == 0) {
      onProgress?.call(i, total);
      await _yield();
    }
    final raw = lines[i];
    if (raw.isEmpty) continue;
    try {
      final row = _parseCsvLine(raw, sep);
      final cnpj = digitsOnly(_csvField(row, cnpjCol));
      if (cnpj.isEmpty) continue;
      map.putIfAbsent(
        cnpj,
        () => LocalizaRow(
          cnpj: cnpj,
          grupo: _csvField(row, grupoCol),
          modalidade: _csvField(row, modalidadeCol),
        ),
      );
    } catch (_) {
      continue;
    }
  }

  onProgress?.call(total, total);
  return map;
}

Future<List<ConexaRow>> parseConexaCsvBytes(
  Uint8List bytes, {
  ProgressCallback? onProgress,
}) async {
  await _yield();
  final text = _decodeCsvText(bytes);
  await _yield();

  final sep = _detectCsvSeparator(text);
  final lines = _csvSplitLogicalLines(text);
  await _yield();

  if (lines.isEmpty) {
    throw const ProcessingException('CSV da Conexa está vazio.');
  }

  final header = _csvHeaderMap(_parseCsvLine(lines.first, sep));
  final idCol = _csvFindColumn(header, ['ID da Cobrança', 'idcobranca']);
  final cpfCnpjCol = _csvFindColumn(header, ['CPF/CNPJ', 'cpf/cnpj']);
  final razaoCol =
      _csvFindColumn(header, ['Razão Social Cliente', 'razaosocial']);
  final valorCol = _csvFindColumn(header, ['Valor']);
  final vencimentoCol = _csvFindColumn(header, ['Vencimento']);
  final emailsCol = _csvFindColumn(header, ['Emails', 'E-mails', 'Email']);
  final telefoneCol =
      _csvFindColumn(header, ['Telefone', 'Telefones', 'Celular']);

  if (idCol == null ||
      cpfCnpjCol == null ||
      razaoCol == null ||
      valorCol == null ||
      vencimentoCol == null ||
      emailsCol == null ||
      telefoneCol == null) {
    throw const ProcessingException(
      'O CSV da Conexa precisa conter: ID da Cobrança, CPF/CNPJ, Razão Social Cliente, Valor, Vencimento, Emails e Telefone.',
    );
  }

  final total = lines.length - 1;
  onProgress?.call(0, total);

  final rows = <ConexaRow>[];
  for (var i = 1; i < lines.length; i++) {
    if (i % 500 == 0) {
      onProgress?.call(i, total);
      await _yield();
    }
    final raw = lines[i];
    if (raw.isEmpty) continue;
    try {
      final row = _parseCsvLine(raw, sep);
      final cpfCnpj = _csvField(row, cpfCnpjCol);
      if (digitsOnly(cpfCnpj).isEmpty) continue;
      rows.add(
        ConexaRow(
          idCobranca: _csvField(row, idCol),
          cpfCnpj: cpfCnpj,
          razaoSocialCliente: _csvField(row, razaoCol),
          valor: _csvField(row, valorCol),
          vencimento: _csvField(row, vencimentoCol),
          emails: _csvField(row, emailsCol),
          telefone: _csvField(row, telefoneCol),
        ),
      );
    } catch (_) {
      continue;
    }
  }

  onProgress?.call(total, total);
  return rows;
}

Future<Map<String, String>> parseAdminVendaCsvBytes(Uint8List bytes) async {
  await _yield();
  final text = _decodeCsvText(bytes);
  final sep = _detectCsvSeparator(text);
  final lines = _csvSplitLogicalLines(text);
  if (lines.isEmpty) {
    throw const ProcessingException('CSV Admin Venda está vazio.');
  }

  final header = _csvHeaderMap(_parseCsvLine(lines.first, sep));
  final clienteIdCol = _csvFindColumn(header, ['Cliente ID', 'ID Cliente']);
  final servicoItemCol =
      _csvFindColumn(header, ['Serviço/Item', 'Servico/Item']);
  if (clienteIdCol == null || servicoItemCol == null) {
    throw const ProcessingException(
      'O CSV Admin Venda precisa conter as colunas Cliente ID e Serviço/Item.',
    );
  }

  final mapped = <String, String>{};
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final row = _parseCsvLine(lines[i], sep);
    final clienteId = _csvField(row, clienteIdCol);
    final servicoItem = _mapServicoItem(_csvField(row, servicoItemCol));
    if (servicoItem.isEmpty) continue;
    for (final key in clientIdLookupKeys(clienteId)) {
      mapped[key] = servicoItem;
    }
  }
  return mapped;
}

Future<List<AdminCobrancaRow>> parseAdminCobrancaCsvBytes(
  Uint8List bytes,
) async {
  await _yield();
  final text = _decodeCsvText(bytes);
  final sep = _detectCsvSeparator(text);
  final lines = _csvSplitLogicalLines(text);
  if (lines.isEmpty) {
    throw const ProcessingException('CSV Admin Cobrança está vazio.');
  }

  final header = _csvHeaderMap(_parseCsvLine(lines.first, sep));
  final columnIndexes = <String, int>{};
  for (final col in AdminCobrancaRow.columns) {
    final index = _csvFindColumn(header, _adminCobrancaColumnCandidates(col));
    if (index != null) columnIndexes[col] = index;
  }
  if (!columnIndexes.containsKey('ID Cliente')) {
    throw const ProcessingException(
      'O CSV Admin Cobrança precisa conter a coluna ID Cliente.',
    );
  }

  final rows = <AdminCobrancaRow>[];
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final source = _parseCsvLine(lines[i], sep);
    final values = <String, String>{};
    for (final col in AdminCobrancaRow.columns) {
      final index = columnIndexes[col];
      values[col] = index == null ? '' : _csvField(source, index);
    }
    if ((values['ID Cliente'] ?? '').trim().isEmpty) continue;
    rows.add(AdminCobrancaRow(values));
  }
  return rows;
}

Future<Map<String, LinhaDetalhaTenex>> parseClientesDetalhesCsvBytes(
  Uint8List bytes,
) async {
  await _yield();
  final text = _decodeCsvText(bytes);
  final sep = _detectCsvSeparator(text);
  final lines = _csvSplitLogicalLines(text);
  if (lines.isEmpty) {
    throw const ProcessingException('CSV Tenex está vazio.');
  }

  final header = _csvHeaderMap(_parseCsvLine(lines.first, sep));
  final idCol = _csvFindColumn(header, ['ID Cliente', 'Cliente ID', 'id']);
  final grupoCol = _csvFindColumn(header, ['grupo']);
  final vendedorCol = _csvFindColumn(header, [
    'vendedor',
    'nome vendedor',
    'vendedor responsavel',
    'consultor',
  ]);
  final parceiroCol = _csvFindColumn(header, [
    'parceiro',
    'nome parceiro',
    'cobranca parceiro',
  ]);
  final customSistemaCol = _csvFindColumn(header, [
    'Custom Sistema',
    'Custom_sistema',
    'Custom',
    'custom sistema',
    'sistema',
    'sistemas',
    'nome sistema',
  ]);
  final percentualComissaoCol = _csvFindColumn(header, [
    '% comissão',
    '% comissao',
    'percentual comissão',
    'percentual comissao',
    'percentual',
    'porcentagem',
    'comissão',
    'comissao',
  ]);

  if (idCol == null ||
      grupoCol == null ||
      vendedorCol == null ||
      parceiroCol == null ||
      customSistemaCol == null) {
    throw const ProcessingException(
      'O CSV Tenex precisa conter as colunas ID Cliente, Grupo, Vendedor, Parceiro e Custom Sistema.',
    );
  }

  print('=== PARSE TENEX CSV ===');
  print('Separador: "$sep"');
  print('Header normalizado:');
  header.forEach((k, v) => print('  "$k" -> $v'));
  print('idCol=$idCol grupoCol=$grupoCol vendedorCol=$vendedorCol parceiroCol=$parceiroCol customSistemaCol=$customSistemaCol percentualComissaoCol=$percentualComissaoCol');

  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final row = _parseCsvLine(lines[i], sep);
    final idRaw = _csvField(row, idCol!);
    if (idRaw.contains('11567')) {
      print('=== LINHA 11567 (i=$i, tamanho=${row.length}) ===');
      for (var j = 0; j < row.length; j++) {
        print('  col $j: "${row[j]}"');
      }
      print('idRaw="$idRaw"');
      print('grupo cell ($grupoCol)="${_csvField(row, grupoCol!)}"');
      print('vendedor cell ($vendedorCol)="${_csvField(row, vendedorCol!)}"');
      print('parceiro cell ($parceiroCol)="${_csvField(row, parceiroCol!)}"');
      print('customSistema cell ($customSistemaCol)="${_csvField(row, customSistemaCol!)}"');
      break;
    }
  }

  final mapped = <String, LinhaDetalhaTenex>{};
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim().isEmpty) continue;
    final row = _parseCsvLine(lines[i], sep);
    final idRaw = _csvField(row, idCol);
    final id = normalizeClientId(idRaw);
    if (id.isEmpty) continue;
    final detalhes = LinhaDetalhaTenex(
      id: id,
      grupo: _csvField(row, grupoCol),
      vendedor: _csvField(row, vendedorCol),
      parceiro: _csvField(row, parceiroCol),
      customSistema: _csvField(row, customSistemaCol),
      percentualComissao: percentualComissaoCol == null
          ? ''
          : _csvField(row, percentualComissaoCol),
    );
    for (final key in clientIdLookupKeys(idRaw)) {
      mapped[key] = detalhes;
    }
  }
  return mapped;
}

Map<String, int> _headerMap(List<excel.Data?> headerRow) {
  final map = <String, int>{};
  for (var i = 0; i < headerRow.length; i++) {
    try {
      final raw = headerRow[i]?.value?.toString() ?? '';
      final key = normalizeKey(raw);
      if (key.isNotEmpty) map[key] = i;
    } catch (_) {
      continue;
    }
  }
  return map;
}

int? _findColumn(Map<String, int> header, List<String> candidates) {
  for (final candidate in candidates) {
    final normalized = normalizeKey(candidate);
    if (header.containsKey(normalized)) {
      return header[normalized];
    }
  }

  for (final entry in header.entries) {
    for (final candidate in candidates) {
      final normalized = normalizeKey(candidate);
      if (_isCompatibleHeaderKey(entry.key, normalized)) {
        return entry.value;
      }
    }
  }

  return null;
}


bool _isCompatibleHeaderKey(String headerKey, String candidateKey) {
  if (headerKey.isEmpty || candidateKey.isEmpty) return false;

  if (headerKey == candidateKey) return true;

  final minLength = headerKey.length < candidateKey.length
      ? headerKey.length
      : candidateKey.length;
  if (minLength < 4) return false;

  return headerKey.contains(candidateKey) || candidateKey.contains(headerKey);
}

String _cellValue(List<excel.Data?> row, int index) {
  try {
    if (index < 0 || index >= row.length) return '';
    final cell = row[index];
    if (cell == null) return '';
    final value = cell.value;
    if (value == null) return '';
    if (value is DateTime) {
      final m = value.month.toString().padLeft(2, '0');
      final d = value.day.toString().padLeft(2, '0');
      return '${value.year}-$m-$d';
    }
    return value.toString().trim();
  } catch (_) {
    return '';
  }
}


String normalizeClientId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';

  final number = double.tryParse(trimmed.replaceAll(',', '.'));
  if (number != null) {
    return number.toStringAsFixed(0);
  }

  final digits = digitsOnly(trimmed);
  return digits.isNotEmpty ? digits : trimmed;
}


List<String> clientIdLookupKeys(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const [];

  final keys = <String>{};

  final normalized = normalizeClientId(raw);
  if (normalized.isNotEmpty) keys.add(normalized);

  final digits = digitsOnly(raw);
  if (digits.isNotEmpty) keys.add(digits);

  final compact = raw.replaceAll(RegExp(r'\s+'), '');
  if (compact.isNotEmpty) keys.add(compact);

  keys.add(raw);

  return keys.toList(growable: false);
}

/// Converte um valor em texto para o padrão brasileiro "R$ 1.234,56".
String formatReal(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  var cleaned = trimmed.replaceAll(RegExp(r'[R\$\s]'), '');
  if (cleaned.isEmpty) return trimmed;

  final hasDot = cleaned.contains('.');
  final hasComma = cleaned.contains(',');

  if (hasDot && hasComma) {
    if (cleaned.lastIndexOf(',') > cleaned.lastIndexOf('.')) {
      cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
    } else {
      cleaned = cleaned.replaceAll(',', '');
    }
  } else if (hasComma) {
    cleaned = cleaned.replaceAll(',', '.');
  }

  final value = double.tryParse(cleaned);
  if (value == null) return trimmed;

  final negative = value < 0;
  final abs = value.abs();
  final parts = abs.toStringAsFixed(2).split('.');
  final intPart = parts[0];
  final decPart = parts[1];

  final buffer = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write('.');
    buffer.write(intPart[i]);
  }

  return 'R\$ ${negative ? '-' : ''}${buffer.toString()},$decPart';
}

String? formatDateBr(DateTime? value) {
  if (value == null) return null;
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String normalizeKey(String input) {
  var text = input.toLowerCase();

  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };

  accents.forEach((key, value) {
    text = text.replaceAll(key, value);
  });

  return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
