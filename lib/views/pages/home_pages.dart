import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/app_colors.dart';
import '../../core/base_tenex.dart';
import '../../core/partner_commission_rates.dart';
import '../../models/linha_detalhe_tenex.dart';
import '../../models/movidesk_models.dart';
import '../../models/step_status.dart';
import '../../services/movidesk_api_service.dart';

// =============================================================================
// Processing page
// =============================================================================

part 'processing_page.dart';
part 'commissions_page.dart';
part '../../core/home_page_helpers.dart';

// =============================================================================
// UI helpers
// =============================================================================

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final StepStatus status;

  @override
  Widget build(BuildContext context) {
    late final String label;
    late final Color fg;
    late final Color bg;
    switch (status) {
      case StepStatus.pendente:
        label = 'Pendente';
        fg = AppColors.textMuted;
        bg = AppColors.neutralSoft;
        break;
      case StepStatus.carregando:
        label = 'Carregando';
        fg = AppColors.warning;
        bg = AppColors.warningSoft;
        break;
      case StepStatus.pronto:
        label = 'Pronto';
        fg = AppColors.success;
        bg = AppColors.successSoft;
        break;
      case StepStatus.processando:
        label = 'Processando';
        fg = AppColors.primary;
        bg = AppColors.primarySoft;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RegraBadge extends StatelessWidget {
  const _RegraBadge({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final is3 = value.trim() == '3';
    final fg = is3 ? AppColors.primary : AppColors.textSecondary;
    final bg = is3 ? AppColors.primarySoft : AppColors.neutralSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value.isEmpty ? '-' : value,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }
}

class _GrupoChip extends StatelessWidget {
  const _GrupoChip({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.trim().isEmpty) {
      return const Text(
        '—',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AppColors.textMuted,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Text(
        value.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _CobrarBadge extends StatelessWidget {
  const _CobrarBadge({required this.value});
  final String value;

  @override
  Widget build(BuildContext context) {
    final normalized = value.trim().toLowerCase();
    final shouldCharge = normalized == 'realizar cobrança';
    final dueToday = normalized == 'vence hoje';
    final fg = shouldCharge
        ? AppColors.danger
        : dueToday
            ? AppColors.warning
            : AppColors.successStrong;
    final bg = shouldCharge
        ? AppColors.dangerSoft
        : dueToday
            ? AppColors.warningSoft
            : AppColors.successSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        value.isEmpty ? '—' : value,
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _TicketCell extends StatelessWidget {
  const _TicketCell({
    required this.ticketId,
    required this.ticketStatus,
  });
  final String ticketId;
  final String ticketStatus;

  @override
  Widget build(BuildContext context) {
    if (ticketId.isEmpty) {
      return const Text(
        '—',
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 13,
          color: AppColors.textMuted,
        ),
      );
    }
    final hasStatus = ticketStatus.trim().isNotEmpty;
    final ticketColor = hasStatus ? AppColors.successStrong : AppColors.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '#$ticketId',
            style: TextStyle(
              fontFamily: 'JetBrains Mono',
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: ticketColor,
              decoration: TextDecoration.underline,
              decorationColor: ticketColor.withOpacity(0.45),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.open_in_new_rounded,
            size: 14,
            color: ticketColor,
          ),
          if (hasStatus) ...[
            const SizedBox(width: 6),
            Text(
              ticketStatus,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: ticketColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageIconButton extends StatelessWidget {
  const _PageIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 32,
        height: 32,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(8),
            child: Icon(
              icon,
              size: 18,
              color: onPressed == null
                  ? AppColors.textMuted.withOpacity(0.5)
                  : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Modelos
// =============================================================================

class LocalizaRow {
  LocalizaRow({
    required this.cnpj,
    required this.grupo,
    required this.modalidade,
  });

  final String cnpj;
  final String grupo;
  final String modalidade;
}

class ConexaRow {
  ConexaRow({
    required this.idCobranca,
    required this.cpfCnpj,
    required this.razaoSocialCliente,
    required this.valor,
    required this.vencimento,
    required this.emails,
    required this.telefone,
  });

  final String idCobranca;
  final String cpfCnpj;
  final String razaoSocialCliente;
  final String valor;
  final String vencimento;
  final String emails;
  final String telefone;
}

class OutputRow {
  OutputRow({
    required this.idCobranca,
    required this.cpfCnpj,
    required this.razaoSocialCliente,
    required this.valor,
    required this.vencimento,
    required this.prazoCobranca,
    required this.dataCobranca,
    required this.dataCobrancaTransferida,
    required this.ticketId,
    required this.ticketStatus,
    required this.ticketMovideskUrl,
    required this.grupo,
    required this.modalidade,
    required this.cobrar,
    required this.emails,
    required this.telefone,
  });

  final String idCobranca;
  final String cpfCnpj;
  final String razaoSocialCliente;
  final String valor;
  final String vencimento;
  final String prazoCobranca;
  final String dataCobranca;
  final bool dataCobrancaTransferida;
  final String ticketId;
  final String ticketStatus;
  final String ticketMovideskUrl;
  final String grupo;
  final String modalidade;
  final String cobrar;
  final String emails;
  final String telefone;
}

class AdminCobrancaRow {
  AdminCobrancaRow(this.values);

  final Map<String, String> values;

  String get idCliente => values['ID Cliente'] ?? '';

  String get servicoItem => values['Serviço/Item'] ?? '';

  set servicoItem(String value) => values['Serviço/Item'] = value;
  set grupo(String value) => values['Grupo'] = value;
  set vendedor(String value) => values['Vendedor'] = value;
  set parceiro(String value) => values['Parceiro'] = value;
  set issRetido(String value) => values['ISS Retido'] = value;
  set quantidadeCnpj(String value) => values['Quantidade CNPJ'] = value;
  set customSistema(String value) => values['Custom Sistema'] = value;
  set percentualComissao(String value) => values['% Comissão'] = value;

  static const List<String> columns = [
    'ID da Cobrança',
    'Faturamento',
    'ID Cliente',
    'CPF/CNPJ',
    'Razão Social Cliente',
    'Nome Fantasia Cliente',
    'Telefone',
    'Emails',
    'Emails Recado',
    'Telefones Pessoas',
    'Emails Pessoas',
    'Endereços Pessoas',
    'Plano(s) Contratado(s)',
    'Tipo',
    'Status',
    'Parcela',
    'Valor Bruto',
    'Valor',
    'Valor Atual',
    'Valor Recebido',
    'Valor Desconto',
    'Valor NFSe com Desconto',
    'Vencimento',
    'Quitação',
    'Competência',
    'Visu.',
    'Rem.',
    'Status Registro no Banco',
    'Emissão',
    'Data Crédito',
    'Cód. Remessa',
    'Conta',
    'Retém ISS',
    'Número Nota Fiscal',
    'Data de operação da quitação',
    'Data cancelamento',
    'Observações',
    'Serviço/Item',
    'Grupo',
    'Vendedor',
    'Parceiro',
    'ISS Retido',
    'Quantidade CNPJ',
    'Custom Sistema',
    '% Comissão',
  ];

  List<String> toValues() => columns.map((c) => values[c] ?? '').toList();
}
