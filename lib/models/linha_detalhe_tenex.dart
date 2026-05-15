class LinhaDetalhaTenex {
  const LinhaDetalhaTenex({
    required this.id,
    required this.grupo,
    required this.vendedor,
    required this.parceiro,
    required this.customSistema,
    required this.percentualComissao,
  });

  final String id;
  final String grupo;
  final String vendedor;
  final String parceiro;
  final String customSistema;
  final String percentualComissao;
}
