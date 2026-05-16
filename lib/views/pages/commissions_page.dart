part of 'home_pages.dart';

class CommissionsPage extends StatefulWidget {
  const CommissionsPage({super.key});

  @override
  State<CommissionsPage> createState() => _CommissionsPageState();
}

enum _GroupingMode { none, partner, seller, customSystem }

enum _GroupingSortMode { quantity, alphabetical }

class _CommissionsPageState extends State<CommissionsPage> {
  static const _apiBase = 'https://alianca.conexa.app/index.php/api/v2';
  static const _chargesEndpoint = 'charges';
  static const _apiToken =
      'a9e23e88f3283927119b49d8a8e91fd30d37cc8ea5f17b45470f23c0c10c0ae1';
  static const List<int> _pageSizeOptions = [10, 20, 30];
  static const List<String> _gridColumns = [
    'ID da Cobrança',
    'ID Cliente',
    'CPF/CNPJ',
    'Razão Social Cliente',
    'Grupo',
    'Parceiro',
    'Vendedor',
    'Serviço/Item',
    'Custom Sistema',
    '% Comissão',
    'Valor',
    'Valor Recebido',
    'Vencimento',
    'Quitação',
    'Status',
  ];
  static const Set<String> _textColumns = {
    'Razão Social Cliente',
    'Grupo',
    'Parceiro',
    'Vendedor',
    'Serviço/Item',
    'Custom Sistema',
    'Status',
  };
  static const Set<String> _tenexLookupFields = {'id', 'cnpj', 'razaoSocial'};

  DateTime? _startDate;
  DateTime? _endDate;
  bool _loading = false;
  String _status = '';
  bool _hasError = false;
  List<AdminCobrancaRow> _rows = [];
  int _fetchedCount = 0;
  int _totalApiCount = 0;
  int _currentPage = 0;
  int _pageSize = 10;
  _GroupingMode _groupingMode = _GroupingMode.none;
  _GroupingSortMode _groupingSortMode = _GroupingSortMode.quantity;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, String>> _tenexJsonList = [];
  late final List<Map<String, String>> _commissionRatesByPartnerName =
      _buildCommissionRatesByPartnerName();

  @override
  void initState() {
    super.initState();
    _loadSystemTenexBase();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Tenex base ─────────────────────────────────────────────────────────────

  void _loadSystemTenexBase() {
    try {
      _tenexJsonList = _parseSystemTenexBase(baseTenexJson);
    } on FormatException catch (e) {
      _hasError = true;
      _status = 'Base Tenex do sistema inválida: ${e.message}';
    }
  }

  List<Map<String, String>> _parseSystemTenexBase(Object? source) {
    final decoded = source is String ? jsonDecode(source) : source;
    final rows = _extractTenexRows(decoded);
    final byId = <String, Map<String, String>>{};
    for (final row in rows) {
      final item = _normalizeTenexJsonEntry(row);
      final key = _tenexDedupKey(item);
      if (key.isEmpty) continue;
      final existing = byId[key];
      if (existing == null || _scoreCompleteness(item) > _scoreCompleteness(existing)) {
        byId[key] = item;
      }
    }
    return byId.values.toList(growable: false);
  }

  Iterable<Map<String, Object?>> _extractTenexRows(Object? decoded) {
    if (decoded == null) return const [];
    if (decoded is List) {
      return decoded.whereType<Map>().map<Map<String, Object?>>(
        (item) => _normalizeJsonKeys(
          item.map<String, Object?>((k, v) => MapEntry(k.toString(), v)),
        ),
      );
    }
    if (decoded is Map) {
      final nm = _normalizeJsonKeys(
        decoded.map<String, Object?>((k, v) => MapEntry(k.toString(), v)),
      );
      for (final key in const ['data', 'items', 'clientes', 'registros']) {
        final v = nm[key];
        if (v is List) return _extractTenexRows(v);
      }
      return nm.entries.where((e) => e.value is Map).map((e) {
        final value = _normalizeJsonKeys(
          (e.value as Map).map<String, Object?>((k, v) => MapEntry(k.toString(), v)),
        );
        value.putIfAbsent('id', () => e.key);
        return value;
      });
    }
    throw const FormatException(
        'use uma lista JSON, um objeto com lista ou um objeto indexado por ID.');
  }

  Map<String, Object?> _normalizeJsonKeys(Map<String, Object?> row) =>
      row.map((k, v) => MapEntry(_normalizeJsonKey(k), v));

  String _normalizeJsonKey(String key) =>
      key.trim().replaceAll(RegExp(r'\s+'), '_');

  Map<String, String> _normalizeTenexJsonEntry(Map<String, Object?> row) {
    row = _normalizeJsonKeys(row);
    final id = normalizeClientId(_readJsonString(row, const [
      'id', 'ID', 'ID Cliente', 'Cliente ID', 'idCliente', 'id_cliente',
      'numero_id', 'número_id',
    ]));
    final cnpj = digitsOnly(_readJsonString(row, const [
      'cnpj', 'CNPJ', 'CPF/CNPJ', 'CNPJ/CPF', 'cpfCnpj', 'cpf_cnpj',
    ]));
    final idDigits = digitsOnly(id);
    return <String, String>{
      'id': id,
      'cnpj': cnpj.isNotEmpty || (idDigits.length != 14 && idDigits.length != 11)
          ? cnpj
          : idDigits,
      'razaoSocial': _readJsonString(row, const [
        'razao_social', 'razão_social', 'razao social', 'razão social',
        'Razão Social', 'Razão Social Cliente', 'razaoSocial', 'businessName',
      ]).trim(),
      'grupo': _readJsonString(row, const ['grupo', 'Grupo']).trim(),
      'vendedor': _readJsonString(row, const [
        'vendedor', 'Vendedor', 'Nome Vendedor', 'Vendedor Responsável',
        'Consultor', 'vendedor_parceiro', 'vendedor parceiro',
      ]).trim(),
      'parceiro': _readJsonString(row, const [
        'parceiro', 'Parceiro', 'Nome Parceiro', 'Cobrança Parceiro',
        'Cobranca Parceiro', 'vendedor_parceiro', 'vendedor parceiro',
      ]).trim(),
      'customSistema': _readJsonString(row, const [
        'customSistema', 'custom_sistema', 'custom sistema', 'Custom Sistema',
        'Custom', 'Sistema', 'Sistemas', 'Nome Sistema',
      ]).trim(),
      'percentualComissao': _readJsonString(row, const [
        'percentualComissao', '% comissão', '% comissao',
        'percentual comissão', 'percentual', 'comissão',
      ]).trim(),
    };
  }

  String _tenexDedupKey(Map<String, String> item) {
    final id = (item['id'] ?? '').trim();
    return id.isEmpty ? '' : 'id:$id';
  }

  String _readJsonString(Map<String, Object?> row, List<String> candidates) {
    final normalized = <String, Object?>{};
    for (final e in row.entries) {
      normalized[normalizeKey(_normalizeJsonKey(e.key))] = e.value;
    }
    for (final c in candidates) {
      final v = normalized[normalizeKey(_normalizeJsonKey(c))];
      if (v != null) return _cleanTenexValue(v);
    }
    return '';
  }

  String _cleanTenexValue(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (normalizeKey(text) == 'null') return '';
    return _fixMojibake(text);
  }

  /// Corrige textos cujos bytes Latin-1 foram armazenados como codepoints Unicode
  /// (mojibake clássico de UTF-8 lido como Latin-1).
  /// Ex: "FarmÃ¡cia" → "Farmácia", "AlemÃ£o" → "Alemão".
  String _fixMojibake(String text) {
    try {
      // Se algum codeUnit > 0xFF, não é Latin-1 puro — devolve sem alterar
      final bytes = <int>[];
      for (final cu in text.codeUnits) {
        if (cu > 0xFF) return text;
        bytes.add(cu);
      }
      final fixed = utf8.decode(bytes, allowMalformed: false);
      // Sanidade: se o resultado ficou maior (indica dupla conversão errada), mantém original
      return fixed.length <= text.length ? fixed : text;
    } catch (_) {
      return text;
    }
  }

  void _putTenexIndex(
    Map<String, Map<String, String>> index,
    String key,
    Map<String, String> item,
  ) {
    if (key.isEmpty) return;
    final existing = index[key];
    if (existing == null || _scoreCompleteness(item) > _scoreCompleteness(existing)) {
      index[key] = item;
    }
  }

  int _scoreCompleteness(Map<String, String> m) => m.entries
      .where((e) => !_tenexLookupFields.contains(e.key) && e.value.trim().isNotEmpty)
      .length;

  String _tenexValueOrCurrent(Map<String, String>? details, String key, String current) {
    final v = details?[key]?.trim() ?? '';
    return v.isEmpty ? current : v;
  }

  T? _lookupByClientId<T>(Map<String, T> source, dynamic rawId) {
    if (rawId == null) return null;
    for (final key in clientIdLookupKeys(rawId.toString())) {
      final found = source[key];
      if (found != null) return found;
    }
    return null;
  }

  Map<String, Map<String, String>> _buildTenexIndex() {
    final tenexById = <String, Map<String, String>>{};
    for (final item in _tenexJsonList) {
      // índice por ID
      final id = (item['id'] ?? '').toString();
      for (final key in clientIdLookupKeys(id)) {
        _putTenexIndex(tenexById, key, item);
      }
      // índice por CNPJ (dígitos), para fallback quando o ID não bater
      final cnpjDigits = digitsOnly(item['cnpj'] ?? '');
      if (cnpjDigits.isNotEmpty) {
        _putTenexIndex(tenexById, cnpjDigits, item);
      }
    }
    return tenexById;
  }

  // ── Date helpers ───────────────────────────────────────────────────────────

  String _formatDateApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatDateDisplay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatDateFromApiString(String raw) {
    if (raw.isEmpty) return '';
    try {
      final d = DateTime.parse(raw);
      return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    } catch (_) {
      return raw;
    }
  }

  String? _validateDateRange() {
    if (_startDate == null || _endDate == null) return 'Selecione o período completo.';
    if (_endDate!.isBefore(_startDate!)) return 'A data final deve ser após a data inicial.';
    if (_endDate!.difference(_startDate!).inDays > 30) {
      return 'O período não pode exceder 30 dias.';
    }
    return null;
  }

  Future<void> _selectDate(bool isStart) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? _startDate ?? DateTime.now());
    final first = isStart ? DateTime(2020) : (_startDate ?? DateTime(2020));
    final last = isStart
        ? (_endDate ?? DateTime.now())
        : DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(last) ? last : initial,
      firstDate: first,
      lastDate: last,
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
      _hasError = false;
      _status = '';
    });
  }

  // ── API fetch ──────────────────────────────────────────────────────────────

  /// Faz uma requisição XHR autenticada. Lança Exception em caso de falha de rede
  /// ou status != 200. Retorna o body decodificado como JSON.
  Future<dynamic> _apiGet(String url) async {
    final html.HttpRequest xhr;
    try {
      xhr = await html.HttpRequest.request(
        url,
        method: 'GET',
        requestHeaders: {'Authorization': 'Bearer $_apiToken'},
        withCredentials: false,
      );
    } catch (e) {
      throw Exception(
        'Erro de rede (possível bloqueio CORS). Execute o Chrome com '
        '--disable-web-security para testes locais, ou solicite à equipe da API '
        'que libere o header Access-Control-Allow-Origin. Detalhe: $e',
      );
    }
    if ((xhr.status ?? 0) != 200) {
      throw Exception('API retornou status ${xhr.status}');
    }
    return jsonDecode(xhr.responseText ?? '[]');
  }

  /// Extrai lista de itens e totalCount de uma resposta da API (lista direta ou wrapper).
  ({List<dynamic> items, int? total}) _parseApiResponse(dynamic decoded) {
    if (decoded is List) return (items: decoded, total: null);
    if (decoded is Map) {
      final inner = decoded['data'] ?? decoded['items'] ??
          decoded['records'] ?? decoded['result'];
      final total = decoded['totalCount'] ?? decoded['total'] ?? decoded['count'];
      return (
        items: inner is List ? inner : [],
        total: total is int ? total : null,
      );
    }
    return (items: [], total: null);
  }

  /// Busca todas as páginas de charges e retorna a lista completa.
  Future<List<Map<String, dynamic>>> _fetchAllCharges(
      String dateFrom, String dateTo) async {
    final all = <Map<String, dynamic>>[];
    var page = 1;
    const limit = 100;

    while (true) {
      if (!mounted) return all;
      setState(() => _status = 'Baixando cobranças (página $page)...');

      final decoded = await _apiGet(
        '$_apiBase/$_chargesEndpoint'
        '?competenceDateFrom=$dateFrom&competenceDateTo=$dateTo'
        '&limit=$limit&page=$page',
      );
      final (:items, :total) = _parseApiResponse(decoded);

      if (total != null && _totalApiCount == 0) {
        setState(() => _totalApiCount = total);
      }
      for (final item in items) {
        if (item is Map<String, dynamic>) all.add(item);
      }
      if (items.length < limit) break;
      page++;
    }
    return all;
  }

  /// Busca product.name para uma lista de customerIds via endpoint sales.
  /// Envia em lotes de até 20 IDs por chamada.
  Future<Map<String, String>> _fetchProductNames(
    Set<String> customerIds,
    String dateFrom,
    String dateTo,
  ) async {
    final productByCustomerId = <String, String>{};
    const batchSize = 20;
    final ids = customerIds.toList();

    for (var i = 0; i < ids.length; i += batchSize) {
      if (!mounted) return productByCustomerId;
      final batch = ids.skip(i).take(batchSize).toList();
      final idParams = batch.map((id) => 'customerId[]=$id').join('&');
      final url =
          '$_apiBase/sales?$idParams&dateFrom=$dateFrom&dateTo=$dateTo&limit=100';

      setState(() =>
          _status = 'Buscando serviço/item (${i + batch.length}/${ids.length} clientes)...');

      try {
        var salesPage = 1;
        while (true) {
          final decoded = await _apiGet(
            '$url&page=$salesPage',
          );
          final (:items, total: _) = _parseApiResponse(decoded);
          for (final item in items) {
            if (item is! Map<String, dynamic>) continue;
            final cId = item['customerId']?.toString() ?? '';
            if (cId.isEmpty || productByCustomerId.containsKey(cId)) continue;
            final product = item['product'];
            final name = product is Map
                ? (product['name']?.toString() ?? '')
                : '';
            if (name.isNotEmpty) productByCustomerId[cId] = name;
          }
          if (items.length < 100) break;
          salesPage++;
        }
      } catch (_) {
        // Ignora erros parciais — o campo ficará N/A para os clientes afetados
      }

      await Future<void>.delayed(Duration.zero);
    }
    return productByCustomerId;
  }

  /// Para customerIds não encontrados no base_tenex, busca CNPJ e nome
  /// no endpoint /customer/{id} e tenta novo lookup no tenex pelo CNPJ.
  Future<Map<String, _CustomerApiData>> _fetchCustomerDetails(
    Set<String> missingIds,
    Map<String, Map<String, String>> tenexById,
  ) async {
    final result = <String, _CustomerApiData>{};
    var processed = 0;

    for (final customerId in missingIds) {
      if (!mounted) return result;
      processed++;
      setState(() => _status =
          'Buscando cliente na API ($processed/${missingIds.length}): #$customerId...');

      try {
        final decoded =
            await _apiGet('$_apiBase/customer/$customerId') as Map<String, dynamic>;

        final name = decoded['name']?.toString() ?? '';
        final legalPerson = decoded['legalPerson'];
        final rawCnpj = legalPerson is Map
            ? (legalPerson['cnpj']?.toString() ?? '')
            : '';

        // Tenta achar no tenex pelo CNPJ
        final cnpjDigits = digitsOnly(rawCnpj);
        final tenex = cnpjDigits.isNotEmpty ? tenexById[cnpjDigits] : null;

        result[customerId] = _CustomerApiData(
          name: name,
          cnpj: rawCnpj,
          tenex: tenex,
        );
      } catch (_) {
        // Se a chamada falhar, o cliente ficará sem enriquecimento
      }

      if (processed % 5 == 0) await Future<void>.delayed(Duration.zero);
    }

    return result;
  }

  Future<void> _fetchFromApi() async {
    final rangeError = _validateDateRange();
    if (rangeError != null) {
      setState(() { _hasError = true; _status = rangeError; });
      return;
    }

    setState(() {
      _loading = true;
      _hasError = false;
      _fetchedCount = 0;
      _totalApiCount = 0;
      _rows = [];
      _currentPage = 0;
      _status = 'Consultando API...';
    });

    final dateFrom = _formatDateApi(_startDate!);
    final dateTo = _formatDateApi(_endDate!);
    final tenexById = _buildTenexIndex();

    try {
      // 1. Busca todos os charges
      final allCharges = await _fetchAllCharges(dateFrom, dateTo);
      if (!mounted) return;

      if (allCharges.isEmpty) {
        setState(() {
          _loading = false;
          _status = 'Nenhum registro encontrado para o período selecionado.';
        });
        return;
      }

      // 2. Coleta customerIds únicos
      final uniqueCustomerIds = allCharges
          .map((c) => c['customerId']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      // 3. Busca product.name via endpoint sales
      final productByCustomerId =
          await _fetchProductNames(uniqueCustomerIds, dateFrom, dateTo);
      if (!mounted) return;

      // 4. Para IDs não encontrados no base_tenex, busca dados via /customer/{id}
      final missingIds = uniqueCustomerIds
          .where((id) => _lookupByClientId(tenexById, id) == null)
          .toSet();
      final customerApiData = missingIds.isNotEmpty
          ? await _fetchCustomerDetails(missingIds, tenexById)
          : <String, _CustomerApiData>{};
      if (!mounted) return;

      // 5. Monta e exibe as linhas progressivamente
      setState(() {
        _totalApiCount = allCharges.length;
        _status = 'Processando ${allCharges.length} registros...';
      });

      for (var i = 0; i < allCharges.length; i++) {
        final row = _mapApiItemToRow(
          allCharges[i],
          tenexById,
          productByCustomerId,
          customerApiData,
        );
        if (!mounted) return;
        setState(() {
          _rows = [..._rows, row];
          _fetchedCount = _rows.length;
          _status = 'Processando: $_fetchedCount de $_totalApiCount registros...';
        });
        if (i % 20 == 0) await Future<void>.delayed(Duration.zero);
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _status = 'Consulta concluída: ${_rows.length} registros encontrados.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
        _status = 'Erro ao consultar API: $e';
      });
    }
  }

  AdminCobrancaRow _mapApiItemToRow(
    Map<String, dynamic> item,
    Map<String, Map<String, String>> tenexById,
    Map<String, String> productByCustomerId,
    Map<String, _CustomerApiData> customerApiData,
  ) {
    final customerId = item['customerId']?.toString() ?? '';

    // 1ª tentativa: lookup pelo customerId no base_tenex
    Map<String, String>? tenex = customerId.isNotEmpty
        ? _lookupByClientId(tenexById, customerId)
        : null;

    String razaoSocial;
    String cnpj;

    if (tenex != null) {
      // Encontrado pelo ID — usa dados do tenex normalmente
      razaoSocial = _tenexValueOrCurrent(tenex, 'razaoSocial', '');
      cnpj = _formatCnpj(_tenexValueOrCurrent(tenex, 'cnpj', ''));
    } else {
      // 2ª tentativa: dados vindos do endpoint /customer/{id}
      final apiData = customerApiData[customerId];
      // O tenex encontrado pelo CNPJ (já resolvido em _fetchCustomerDetails)
      tenex = apiData?.tenex;
      razaoSocial = apiData?.name ?? '';
      cnpj = _formatCnpj(apiData?.cnpj ?? '');
    }

    final grupo = _tenexValueOrCurrent(tenex, 'grupo', '');
    final parceiro = _tenexValueOrCurrent(tenex, 'parceiro', '');
    final vendedor = _tenexValueOrCurrent(tenex, 'vendedor', '');
    final customSistema = _tenexValueOrCurrent(tenex, 'customSistema', '');
    final percentualComissao = _tenexValueOrCurrent(tenex, 'percentualComissao', '');

    // product.name vem do endpoint sales, buscado separadamente por customerId
    final servicoItem = _normalizeServiceItem(productByCustomerId[customerId] ?? '');

    final rawAmount = item['amount'];
    final rawPaid = item['paidAmount'];
    final amount = rawAmount is num
        ? rawAmount.toDouble()
        : double.tryParse(rawAmount?.toString() ?? '') ?? 0.0;
    final paidAmount = rawPaid is num
        ? rawPaid.toDouble()
        : double.tryParse(rawPaid?.toString() ?? '') ?? 0.0;

    final status = _mapApiStatus(item['status']?.toString() ?? '');

    final values = <String, String>{
      'ID da Cobrança': item['chargeId']?.toString() ?? '',
      'ID Cliente': customerId,
      'CPF/CNPJ': cnpj,
      'Razão Social Cliente': razaoSocial,
      'Grupo': grupo,
      'Parceiro': parceiro,
      'Vendedor': vendedor,
      'Serviço/Item': servicoItem,
      'Custom Sistema': customSistema,
      '% Comissão': percentualComissao,
      'Valor': _formatMoney(amount),
      'Valor Recebido': _formatMoney(paidAmount),
      'Vencimento': _formatDateFromApiString(item['dueDate']?.toString() ?? ''),
      'Quitação': _formatDateFromApiString(item['paymentDate']?.toString() ?? ''),
      'Status': status,
    };

    return AdminCobrancaRow(values);
  }

  String _mapApiStatus(String raw) {
    final n = normalizeKey(raw);
    if (n.contains('paid') || n.contains('pago') || n.contains('quitad')) {
      return 'Quitada';
    }
    if (n.contains('cancel')) return 'Cancelada';
    if (n.contains('overdue') || n.contains('vencid') || n.contains('atraso')) {
      return 'Vencida';
    }
    if (n.contains('pending') || n.contains('pendente') || n.contains('aberto')) {
      return 'Pendente';
    }
    return raw.trim().isEmpty ? 'Pendente' : raw;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filteredRows = _filteredRows();
    final totalPages =
        filteredRows.isEmpty ? 1 : ((filteredRows.length - 1) ~/ _pageSize) + 1;
    final safePage = _currentPage.clamp(0, totalPages - 1);
    final startIdx = safePage * _pageSize;
    final endIdx = (startIdx + _pageSize) > filteredRows.length
        ? filteredRows.length
        : startIdx + _pageSize;
    final pageRows = filteredRows.isEmpty
        ? <AdminCobrancaRow>[]
        : filteredRows.sublist(startIdx, endIdx);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Comissões',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Selecione o período para buscar os dados de cobrança. Máximo de 30 dias.',
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),
              _buildDateRangePicker(),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _status,
                  style: TextStyle(
                    color: _hasError ? AppColors.danger : AppColors.textSecondary,
                    fontFamily: 'Inter',
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (_loading) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 8,
                    value: _totalApiCount > 0
                        ? (_fetchedCount / _totalApiCount).clamp(0.0, 1.0)
                        : null,
                    backgroundColor: AppColors.surfaceAlt,
                    color: AppColors.primary,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              if (_rows.isEmpty)
                _buildEmptyState()
              else
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x0A0F172A),
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
                        child: Row(
                          children: [
                            const Text(
                              'Resultado',
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: AppColors.borderLight),
                              ),
                              child: Text(
                                '${_formatInt(_rows.length)} registros',
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                            SizedBox(
                                width: MediaQuery.of(context).size.width * 0.3),
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) => setState(() {
                                  _searchQuery = value;
                                  _currentPage = 0;
                                }),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText:
                                      'Pesquisar Grupo, Parceiro, Vendedor ou Custom Sistema',
                                  prefixIcon:
                                      const Icon(Icons.search, size: 18),
                                  filled: true,
                                  fillColor: AppColors.surfaceAlt,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide.none,
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide.none,
                                  ),
                                  suffixIcon: _searchQuery.trim().isEmpty
                                      ? null
                                      : IconButton(
                                          tooltip: 'Limpar busca',
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() {
                                              _searchQuery = '';
                                              _currentPage = 0;
                                            });
                                          },
                                          icon: const Icon(Icons.close,
                                              size: 16),
                                        ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                    horizontal: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            _buildGroupingChip(
                              label: 'AGRUPAR PARCEIRO',
                              mode: _GroupingMode.partner,
                            ),
                            const SizedBox(width: 8),
                            _buildGroupingChip(
                              label: 'AGRUPAR VENDEDOR',
                              mode: _GroupingMode.seller,
                            ),
                            const SizedBox(width: 8),
                            _buildGroupingChip(
                              label: 'AGRUPAR SISTEMA',
                              mode: _GroupingMode.customSystem,
                            ),
                            if (_isGroupingEnabled) ...[
                              const SizedBox(width: 8),
                              _buildGroupingSortSelector(),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: AppColors.borderLight),
                      _isGroupingEnabled
                          ? _buildGroupedView(filteredRows)
                          : _buildCommissionsTable(pageRows),
                      const Divider(height: 1, color: AppColors.borderLight),
                      _isGroupingEnabled
                          ? _groupedFooter(filteredRows.length)
                          : _contadorPaginasRodape(
                              totalCount: filteredRows.length,
                              totalPages: totalPages,
                              safePage: safePage,
                              startIdx: startIdx,
                              endIdx: endIdx,
                            ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Date range picker ──────────────────────────────────────────────────────

  Widget _buildDateRangePicker() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: _buildDateField(isStart: true)),
          const SizedBox(width: 16),
          Expanded(child: _buildDateField(isStart: false)),
          const SizedBox(width: 20),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _loading ? null : _fetchFromApi,
              icon: _loading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_loading ? 'Buscando...' : 'Buscar'),
              style: FilledButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
              ),
            ),
          ),
          if (_rows.isNotEmpty) ...[
            const SizedBox(width: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _loading ? null : _clearResults,
                icon: const Icon(Icons.clear, size: 18),
                label: const Text('Limpar'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDateField({required bool isStart}) {
    final date = isStart ? _startDate : _endDate;
    final label = isStart ? 'Data início' : 'Data fim';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _loading ? null : () => _selectDate(isStart),
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: _hasError && date == null
                    ? AppColors.danger
                    : AppColors.borderLight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: date != null
                      ? AppColors.primary
                      : AppColors.textMuted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    date != null
                        ? _formatDateDisplay(date)
                        : 'Selecionar data',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 14,
                      color: date != null
                          ? AppColors.textPrimary
                          : AppColors.textMuted,
                    ),
                  ),
                ),
                if (date != null)
                  Icon(Icons.check_circle,
                      size: 16, color: AppColors.success),
              ],
            ),
          ),
        ),
      ],
    );
  }

  void _clearResults() {
    setState(() {
      _rows = [];
      _fetchedCount = 0;
      _totalApiCount = 0;
      _currentPage = 0;
      _status = '';
      _hasError = false;
      _searchQuery = '';
      _searchController.clear();
      _groupingMode = _GroupingMode.none;
    });
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyState() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        children: [
          Icon(
            _loading ? Icons.cloud_download_outlined : Icons.date_range_outlined,
            color: AppColors.textMuted,
            size: 36,
          ),
          const SizedBox(height: 14),
          Text(
            _loading ? 'Buscando dados...' : 'Nenhum dado carregado',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _loading
                ? 'Aguarde enquanto os registros são baixados e processados.'
                : 'Selecione o período acima e clique em Buscar para carregar as comissões.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ── Table ──────────────────────────────────────────────────────────────────

  Widget _buildCommissionsTable(List<AdminCobrancaRow> rows) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _HorizontalTableScroll(
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.surfaceAlt),
                headingTextStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                columns: _gridColumns
                    .map((c) => DataColumn(label: Text(c)))
                    .toList(),
                rows: rows.map((row) {
                  return DataRow(
                    cells: List.generate(_gridColumns.length, (i) {
                      final column = _gridColumns[i];
                      final value = column == '% Comissão'
                          ? _formatPercentFromRatio(
                              _commissionPercentForRow(row))
                          : _formatGridValue(column, row.values[column] ?? '');
                      final minWidth = math.max<double>(
                          120, (value.length * 9).toDouble());
                      return DataCell(SizedBox(
                        width: minWidth,
                        child: Text(value, overflow: TextOverflow.ellipsis),
                      ));
                    }),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Grouping ───────────────────────────────────────────────────────────────

  bool get _isGroupingEnabled => _groupingMode != _GroupingMode.none;

  String get _groupingLabel {
    switch (_groupingMode) {
      case _GroupingMode.partner:
        return 'PARCEIRO';
      case _GroupingMode.seller:
        return 'VENDEDOR';
      case _GroupingMode.customSystem:
        return 'SISTEMA';
      case _GroupingMode.none:
        return 'Nenhum';
    }
  }

  String get _groupingColumn {
    switch (_groupingMode) {
      case _GroupingMode.partner:
        return 'Parceiro';
      case _GroupingMode.seller:
        return 'Vendedor';
      case _GroupingMode.customSystem:
        return 'Custom Sistema';
      case _GroupingMode.none:
        return '';
    }
  }

  Widget _buildGroupingChip({required String label, required _GroupingMode mode}) {
    final selected = _groupingMode == mode;
    return FilterChip(
      selected: selected,
      label: Text(label, style: const TextStyle(color: Colors.white)),
      backgroundColor: const Color(0xFF103339),
      selectedColor: const Color(0xFF87B526),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      onSelected: (value) => setState(() {
        _groupingMode = value ? mode : _GroupingMode.none;
        _currentPage = 0;
      }),
    );
  }

  Widget _buildGroupingSortSelector() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<_GroupingSortMode>(
          value: _groupingSortMode,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrimary,
          ),
          onChanged: (v) {
            if (v == null) return;
            setState(() => _groupingSortMode = v);
          },
          items: const [
            DropdownMenuItem(
              value: _GroupingSortMode.quantity,
              child: Text('Ordenar: quantidade'),
            ),
            DropdownMenuItem(
              value: _GroupingSortMode.alphabetical,
              child: Text('Ordenar: A-Z'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedView(List<AdminCobrancaRow> rows) {
    final grouped = <String, List<AdminCobrancaRow>>{};
    for (final row in rows) {
      final v = _displayValue(row.values[_groupingColumn] ?? '');
      grouped.putIfAbsent(_normalizeGroupingName(v), () => []).add(row);
    }
    final sortedKeys = grouped.keys.toList()
      ..sort((a, b) {
        switch (_groupingSortMode) {
          case _GroupingSortMode.quantity:
            final cmp = grouped[b]!.length.compareTo(grouped[a]!.length);
            return cmp != 0 ? cmp : a.compareTo(b);
          case _GroupingSortMode.alphabetical:
            return a.compareTo(b);
        }
      });

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: sortedKeys.length,
        itemBuilder: (context, index) {
          final groupValue = sortedKeys[index];
          final transactions = grouped[groupValue]!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              controlAffinity: ListTileControlAffinity.leading,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide.none,
              ),
              collapsedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide.none,
              ),
              title: Text('$groupValue (${transactions.length})'),
              subtitle: const Text('Clique para expandir transações relacionadas'),
              trailing: Tooltip(
                message: 'Exportar relatório em Excel',
                child: IconButton(
                  icon: const Icon(Icons.download_outlined,
                      color: Color(0xFF87b526)),
                  onPressed: () => _exportGroupedReport(
                    groupValue: groupValue,
                    transactions: transactions,
                  ),
                ),
              ),
              children: [_buildCommissionsTable(transactions)],
            ),
          );
        },
      ),
    );
  }

  // ── Filtering ──────────────────────────────────────────────────────────────

  List<AdminCobrancaRow> _filteredRows() {
    final query = normalizeKey(_searchQuery.trim());
    if (query.isEmpty) return _rows;
    return _rows.where((row) {
      return normalizeKey(row.values['Grupo'] ?? '').contains(query) ||
          normalizeKey(row.values['Parceiro'] ?? '').contains(query) ||
          normalizeKey(row.values['Vendedor'] ?? '').contains(query) ||
          normalizeKey(row.values['Custom Sistema'] ?? '').contains(query);
    }).toList();
  }

  // ── Pagination footer ──────────────────────────────────────────────────────

  Widget _contadorPaginasRodape({
    required int totalCount,
    required int totalPages,
    required int safePage,
    required int startIdx,
    required int endIdx,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Row(
        children: [
          Text(
            'Itens por página',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _pageSize,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                color: AppColors.textPrimary,
              ),
              borderRadius: BorderRadius.circular(8),
              onChanged: (v) {
                if (v == null || v == _pageSize) return;
                setState(() { _pageSize = v; _currentPage = 0; });
              },
              items: _pageSizeOptions
                  .map((o) => DropdownMenuItem<int>(
                        value: o,
                        child: Text(o.toString()),
                      ))
                  .toList(),
            ),
          ),
          const SizedBox(width: 16),
          Text(
            'Mostrando ${startIdx + 1}–$endIdx de ${_formatInt(totalCount)}',
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          const Spacer(),
          _PageIconButton(
            tooltip: 'Primeira página',
            icon: Icons.first_page,
            onPressed:
                safePage > 0 ? () => setState(() => _currentPage = 0) : null,
          ),
          _PageIconButton(
            tooltip: 'Página anterior',
            icon: Icons.chevron_left,
            onPressed: safePage > 0
                ? () => setState(() => _currentPage = safePage - 1)
                : null,
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.borderLight),
            ),
            child: Text(
              'Página ${safePage + 1} de $totalPages',
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _PageIconButton(
            tooltip: 'Próxima página',
            icon: Icons.chevron_right,
            onPressed: safePage < totalPages - 1
                ? () => setState(() => _currentPage = safePage + 1)
                : null,
          ),
          _PageIconButton(
            tooltip: 'Última página',
            icon: Icons.last_page,
            onPressed: safePage < totalPages - 1
                ? () => setState(() => _currentPage = totalPages - 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _groupedFooter(int totalCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 16, 12),
      child: Text(
        '${_formatInt(totalCount)} transações filtradas e agrupadas por $_groupingLabel',
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  // ── Formatting helpers ─────────────────────────────────────────────────────

  String _formatCnpj(String raw) {
    final digits = digitsOnly(raw);
    if (digits.length == 14) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
    }
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
    }
    return raw;
  }

  String _normalizeServiceItem(String raw) {
    if (raw.trim().isEmpty) return '';
    if (normalizeKey(raw).contains('mensal')) return 'Mensal';
    return raw;
  }

  String _formatGridValue(String column, String value) {
    const moneyColumns = {'Valor', 'Valor Recebido'};

    if (column == 'Status') {
      final n = normalizeKey(value);
      if (n == normalizeKey('Quitada (Gerada por Negociação)')) return 'Quitada';
      return value;
    }
    if (column == 'Valor Recebido' &&
        (value.trim().isEmpty || normalizeKey(value) == 'null')) {
      return 'R\$ 0,00';
    }
    if (column == '% Comissão') return _formatPercentValue(value);
    if (moneyColumns.contains(column)) return formatReal(value);
    if (_textColumns.contains(column)) {
      return _displayValue(_capitalizeWords(value));
    }
    return _displayValue(value);
  }

  String _displayValue(String value) {
    if (value.trim().isEmpty || normalizeKey(value) == 'null') return 'N/A';
    return value.trim();
  }

  String _formatPercentValue(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || normalizeKey(trimmed) == 'null') return 'N/A';
    final normalized = trimmed.replaceAll('%', '').replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    if (value == null) return trimmed;
    if (value > 0 && value <= 1) return _formatPercentFromRatio(value);
    return '${value.toStringAsFixed(0)}%';
  }

  String _formatPercentFromRatio(double ratio) {
    if (ratio <= 0) return '0%';
    return '${(ratio * 100).toStringAsFixed(0)}%';
  }

  String _normalizeGroupingName(String value) {
    final n = _displayValue(value);
    return n == 'N/A' ? n : n.toUpperCase();
  }

  String _capitalizeWords(String value) {
    final n = value.trim().toLowerCase();
    if (n.isEmpty) return n;
    return n.split(RegExp(r'\s+')).map((w) {
      if (w.isEmpty) return w;
      return '${w[0].toUpperCase()}${w.substring(1)}';
    }).join(' ');
  }

  String _formatInt(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write('.');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ── Commission logic ───────────────────────────────────────────────────────

  double _commissionPercentForRow(AdminCobrancaRow row) =>
      _commissionPercentFor(
        row: row.values,
        rawService: row.values['Serviço/Item'] ?? '',
      );

  double _commissionPercentFor({
    required Map<String, String> row,
    required String rawService,
  }) {
    final normalizedService = normalizeKey(rawService);
    if (normalizedService.isEmpty ||
        normalizedService == 'n a' ||
        normalizedService == 'na') {
      return 0.0;
    }
    final serviceType = _commissionTypeForService(rawService);
    final partnerRate = _partnerCommissionRate(
      row: row,
      serviceType: serviceType,
    );
    if (partnerRate != null) return partnerRate;
    final tenexPercent = _parsePercent(row['% Comissão'], defaultPercent: 0.0);
    return tenexPercent > 0 ? tenexPercent : 0.0;
  }

  double? _partnerCommissionRate({
    required Map<String, String> row,
    required String serviceType,
  }) {
    final partnerValue = row['Parceiro']?.trim() ?? '';
    if (partnerValue.isEmpty) return null;
    final query = _normalizeRateMatchKey(partnerValue);
    if (query.isEmpty) return null;
    for (final rateRow in _commissionRatesByPartnerName) {
      final razaoSocial =
          _normalizeRateMatchKey(rateRow['razao_social'] ?? '');
      if (razaoSocial.isEmpty) continue;
      if (!razaoSocial.contains(query) && !query.contains(razaoSocial)) {
        continue;
      }
      return _parsePercent(rateRow[serviceType], defaultPercent: 0.0);
    }
    return null;
  }

  String _normalizeRateMatchKey(String input) {
    final normalized = normalizeKey(input);
    if (normalized.isEmpty) return '';
    return normalized.replaceAllMapped(
      RegExp(r'(.)\1+'),
      (m) => m.group(1)!,
    );
  }

  String _commissionTypeForService(String rawService) {
    final n = normalizeKey(rawService).replaceAll('º', 'o');
    if (n.contains('adesao')) return 'adesao';
    if (n.contains('1o') || n.contains('primeira') || n.contains('1 recorrencia')) {
      return 'primeira_mensalidade';
    }
    return 'mensalidade';
  }

  List<Map<String, String>> _buildCommissionRatesByPartnerName() =>
      List<Map<String, String>>.from(kPartnerCommissionRates);

  double _parsePercent(String? input, {double defaultPercent = 20.0}) {
    final normalized =
        (input ?? '').replaceAll('%', '').replaceAll(',', '.').trim();
    final value = double.tryParse(normalized);
    return ((value ?? defaultPercent) / 100).clamp(0.0, 1.0);
  }

  // ── Export ─────────────────────────────────────────────────────────────────

  Future<void> _exportGroupedReport({
    required String groupValue,
    required List<AdminCobrancaRow> transactions,
  }) async {
    if (transactions.isEmpty) return;

    final workbook = excel.Excel.createExcel();
    final reportSheet = workbook['Comissionamento'];
    final detailsSheet = workbook['Detalhamento'];

    _appendConsolidatedSheet(
      sheet: reportSheet,
      transactions: transactions,
      startDate: _startDate,
      endDate: _endDate,
    );
    _appendDetailsSheet(sheet: detailsSheet, transactions: transactions);

    if (detailsSheet.maxRows == 0) detailsSheet.appendRow(['Sem dados']);

    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty) return;

    final blob = html.Blob(
      [Uint8List.fromList(bytes)],
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', _buildGroupedReportFileName(groupValue))
      ..style.display = 'none';
    html.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    Future.delayed(
      const Duration(seconds: 1),
      () => html.Url.revokeObjectUrl(url),
    );
  }

  void _appendConsolidatedSheet({
    required excel.Sheet sheet,
    required List<AdminCobrancaRow> transactions,
    required DateTime? startDate,
    required DateTime? endDate,
  }) {
    final totalsByCategory = <String, _ConsolidadoTotais>{};
    for (final row in transactions) {
      final serviceItem = row.values['Serviço/Item'] ?? '';
      final category = _serviceGroupLabel(serviceItem);
      final carteira = _parseMoney(row.values['Valor'] ?? '');
      final recebido = _parseMoney(row.values['Valor Recebido'] ?? '');
      final status = row.values['Status'] ?? '';
      final carteiraQuitada = _isStatusQuitado(status) ? carteira : 0.0;
      final commissionPercent = _commissionPercentFor(
        row: row.values,
        rawService: serviceItem,
      );
      final comissao = carteiraQuitada * commissionPercent;
      final current =
          totalsByCategory[category] ?? const _ConsolidadoTotais.zero();
      totalsByCategory[category] = current.add(
        carteira: carteira,
        recebido: recebido,
        carteiraQuitada: carteiraQuitada,
        comissao: comissao,
      );
    }

    final periodText = startDate == null || endDate == null
        ? 'Sem período'
        : '${_formatDateDisplay(startDate)} a ${_formatDateDisplay(endDate)}';
    final sortedEntries = totalsByCategory.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    const titleColor = '#6C7300';
    const sectionColor = '#A3A51A';
    const headerColor = '#BBD56E';
    const totalColor = '#FFD966';
    const borderColor = '#333333';

    final titleStyle = excel.CellStyle(
      bold: true, fontSize: 18,
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      backgroundColorHex: titleColor, fontColorHex: '#FFFFFF',
    );
    final sectionStyle = excel.CellStyle(
      bold: true, fontSize: 13,
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      backgroundColorHex: sectionColor, fontColorHex: '#FFFFFF',
    );
    final headerStyle = excel.CellStyle(
      bold: true,
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      backgroundColorHex: headerColor,
      leftBorder: excel.Border(borderColorHex: borderColor),
      rightBorder: excel.Border(borderColorHex: borderColor),
      topBorder: excel.Border(borderColorHex: borderColor),
      bottomBorder: excel.Border(borderColorHex: borderColor),
    );
    final labelStyle = excel.CellStyle(
      bold: true,
      horizontalAlign: excel.HorizontalAlign.Left,
      verticalAlign: excel.VerticalAlign.Center,
      backgroundColorHex: headerColor,
      leftBorder: excel.Border(borderColorHex: borderColor),
      rightBorder: excel.Border(borderColorHex: borderColor),
      topBorder: excel.Border(borderColorHex: borderColor),
      bottomBorder: excel.Border(borderColorHex: borderColor),
    );
    final bodyTextStyle = excel.CellStyle(
      horizontalAlign: excel.HorizontalAlign.Left,
      verticalAlign: excel.VerticalAlign.Center,
      leftBorder: excel.Border(borderColorHex: borderColor),
      rightBorder: excel.Border(borderColorHex: borderColor),
      topBorder: excel.Border(borderColorHex: borderColor),
      bottomBorder: excel.Border(borderColorHex: borderColor),
    );
    final bodyValueStyle = excel.CellStyle(
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      leftBorder: excel.Border(borderColorHex: borderColor),
      rightBorder: excel.Border(borderColorHex: borderColor),
      topBorder: excel.Border(borderColorHex: borderColor),
      bottomBorder: excel.Border(borderColorHex: borderColor),
    );
    final totalStyle = excel.CellStyle(
      bold: true, fontSize: 13,
      horizontalAlign: excel.HorizontalAlign.Center,
      verticalAlign: excel.VerticalAlign.Center,
      backgroundColorHex: totalColor,
      leftBorder: excel.Border(borderColorHex: borderColor),
      rightBorder: excel.Border(borderColorHex: borderColor),
      topBorder: excel.Border(borderColorHex: borderColor),
      bottomBorder: excel.Border(borderColorHex: borderColor),
    );

    void setCell(int row, int col, dynamic value, excel.CellStyle style) {
      final cell = sheet.cell(
        excel.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row),
      );
      cell.value = value;
      cell.cellStyle = style;
    }

    sheet.setColumnWidth(0, 28);
    sheet.setColumnWidth(1, 10);
    sheet.setColumnWidth(2, 20);
    sheet.setColumnWidth(3, 20);
    sheet.setColumnWidth(4, 20);

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0),
    );
    setCell(0, 0, 'Comissionamento de Parceiro Revenda', titleStyle);

    setCell(2, 0, 'Período analisado', labelStyle);
    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2),
      excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2),
    );
    setCell(2, 1, periodText, headerStyle);

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 4),
      excel.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 4),
    );
    setCell(4, 0, 'Resultado Mês Atual', sectionStyle);
    setCell(5, 0, 'Serviço', headerStyle);
    setCell(5, 1, '%', headerStyle);
    setCell(5, 2, 'Carteira', headerStyle);
    setCell(5, 3, 'Recebido', headerStyle);
    setCell(5, 4, 'Comissão', headerStyle);

    double totalCarteira = 0;
    double totalRecebido = 0;
    double totalComissao = 0;
    var line = 6;

    for (final entry in sortedEntries) {
      final carteira = entry.value.carteira;
      final recebido = entry.value.recebido;
      final carteiraQuitada = entry.value.carteiraQuitada;
      final comissao = entry.value.comissao;
      final commissionPercent =
          carteiraQuitada > 0 ? (comissao / carteiraQuitada) : 0.0;
      totalCarteira += carteira;
      totalRecebido += recebido;
      totalComissao += comissao;
      setCell(line, 0, entry.key, bodyTextStyle);
      setCell(line, 1, '${(commissionPercent * 100).toStringAsFixed(0)}%',
          bodyValueStyle);
      setCell(line, 2, _formatMoney(carteira), bodyValueStyle);
      setCell(line, 3, _formatMoney(recebido), bodyValueStyle);
      setCell(line, 4, _formatMoney(comissao), bodyValueStyle);
      line++;
    }

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: line),
      excel.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: line),
    );
    setCell(line, 0, 'Totais', totalStyle);
    setCell(line, 2, _formatMoney(totalCarteira), totalStyle);
    setCell(line, 3, _formatMoney(totalRecebido), totalStyle);
    setCell(line, 4, _formatMoney(totalComissao), totalStyle);
  }

  void _appendDetailsSheet({
    required excel.Sheet sheet,
    required List<AdminCobrancaRow> transactions,
  }) {
    final detailsColumns = [..._gridColumns, '% Comissão', 'Comissão'];
    for (var c = 0; c < detailsColumns.length; c++) {
      sheet
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0))
          .value = detailsColumns[c];
      sheet.setColumnWidth(c, 22);
    }
    for (var r = 0; r < transactions.length; r++) {
      final row = transactions[r].values;
      final line = r + 1;
      for (var c = 0; c < detailsColumns.length; c++) {
        final column = detailsColumns[c];
        final cell = sheet.cell(
          excel.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: line),
        );
        if (column == '% Comissão') {
          final pct = _commissionPercentFor(
            row: row,
            rawService: row['Serviço/Item'] ?? '',
          );
          cell.value = '${(pct * 100).toStringAsFixed(0)}%';
        } else if (column == 'Comissão') {
          final pct = _commissionPercentFor(
            row: row,
            rawService: row['Serviço/Item'] ?? '',
          );
          final valor = _parseMoney(row['Valor'] ?? '');
          cell.value = _formatMoney(valor * pct);
        } else {
          cell.value = _formatGridValue(column, row[column] ?? '');
        }
      }
    }
  }

  bool _isStatusQuitado(String status) =>
      normalizeKey(status).contains('quitad');

  String _serviceGroupLabel(String rawService) {
    final n = normalizeKey(rawService).replaceAll('º', 'o');
    if (n.contains('adesao')) return 'Adesão';
    if (n.contains('1o') || n.contains('primeira') || n.contains('1 recorrencia')) {
      return '1° Mensalidade';
    }
    if (n.contains('recorrencia') || n.contains('mensal')) return 'Mensal';
    return rawService.trim().isEmpty ? 'Outros' : _capitalizeWords(rawService);
  }

  double _parseMoney(String raw) {
    var value = raw.trim().replaceAll('R\$', '').replaceAll(RegExp(r'\s+'), '').replaceAll(RegExp(r'[^0-9,.\-]'), '');
    if (value.isEmpty) return 0;
    final lastComma = value.lastIndexOf(',');
    final lastDot = value.lastIndexOf('.');
    String normalized;
    if (lastComma > lastDot) {
      normalized = value.replaceAll('.', '').replaceAll(',', '.');
    } else if (lastDot > lastComma) {
      normalized = value.replaceAll(',', '');
    } else {
      normalized = value;
    }
    return double.tryParse(normalized) ?? 0;
  }

  String _formatMoney(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts.first;
    final decimalPart = parts.last;
    final buf = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final indexFromEnd = intPart.length - i;
      buf.write(intPart[i]);
      if (indexFromEnd > 1 && indexFromEnd % 3 == 1) buf.write('.');
    }
    return 'R\$ ${buf.toString()},$decimalPart';
  }

  String _sanitizeFileName(String value) {
    final s = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), ' ')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
    return s.isEmpty ? 'relatorio_agrupamento' : s;
  }

  String _buildGroupedReportFileName(String groupValue) {
    final now = DateTime.now();
    final groupingType = _sanitizeFileName(_groupingLabel).toLowerCase();
    final safeGroupValue = _sanitizeFileName(groupValue).toLowerCase();
    return '${now.year}_${now.month.toString().padLeft(2, '0')}_${groupingType}_$safeGroupValue.xlsx';
  }
}

// ── Supporting types ───────────────────────────────────────────────────────────

class _CustomerApiData {
  const _CustomerApiData({
    required this.name,
    required this.cnpj,
    required this.tenex,
  });
  final String name;
  final String cnpj;
  final Map<String, String>? tenex;
}

class _ConsolidadoTotais {
  const _ConsolidadoTotais({
    required this.carteira,
    required this.recebido,
    required this.carteiraQuitada,
    required this.comissao,
  });
  const _ConsolidadoTotais.zero()
      : carteira = 0,
        recebido = 0,
        carteiraQuitada = 0,
        comissao = 0;
  final double carteira;
  final double recebido;
  final double carteiraQuitada;
  final double comissao;
  _ConsolidadoTotais add({
    required double carteira,
    required double recebido,
    required double carteiraQuitada,
    required double comissao,
  }) =>
      _ConsolidadoTotais(
        carteira: this.carteira + carteira,
        recebido: this.recebido + recebido,
        carteiraQuitada: this.carteiraQuitada + carteiraQuitada,
        comissao: this.comissao + comissao,
      );
}

class _HorizontalTableScroll extends StatefulWidget {
  const _HorizontalTableScroll({required this.child});
  final Widget child;

  @override
  State<_HorizontalTableScroll> createState() => _HorizontalTableScrollState();
}

class _HorizontalTableScrollState extends State<_HorizontalTableScroll> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      trackVisibility: true,
      interactive: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: widget.child,
        ),
      ),
    );
  }
}
