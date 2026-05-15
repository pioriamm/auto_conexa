# Documentação do grid da tela Cobrança

Este documento descreve como o grid de resultados da tela **Fluxo de cobrança** é preenchido, quais arquivos alimentam cada campo e quais regras de transformação são aplicadas antes da exibição.

## Visão geral do fluxo

1. O usuário envia dois arquivos na tela:
   - **Base Localiza**: usada como base de complemento por CNPJ/CPF.
   - **Planilha Conexa**: usada como lista principal de cobranças a processar.
2. A aplicação lê a primeira aba do arquivo Excel ou o conteúdo do CSV enviado.
3. Cada linha válida da planilha Conexa vira uma linha do grid.
4. Para cada linha da Conexa, a aplicação procura o CNPJ/CPF correspondente na Base Localiza, usando apenas os dígitos do documento.
5. A aplicação consulta o Movidesk pelo CNPJ formatado para identificar ticket de cobrança já existente.
6. Dependendo da data de cobrança calculada e da situação do ticket, a aplicação pode criar um novo ticket no Movidesk.
7. A linha final é montada em memória e adicionada ao grid de resultados.

## Arquivos de entrada

### Base Localiza

A Base Localiza pode ser enviada em Excel ou CSV. Ela precisa conter as colunas abaixo:

| Coluna aceita | Uso no processamento |
| --- | --- |
| `CNPJ`, `CNPJ/CPF` ou `cpfcnpj` | Chave de relacionamento com a planilha Conexa. O sistema remove caracteres não numéricos antes de comparar. |
| `Grupo` | Preenche a coluna **GRUPO** do grid e também é usado para procurar a pessoa no Movidesk ao abrir ticket. |
| `Modalidade` | Define se a linha é **WHITE LABEL** ou **CLIENTE FINAL**, o que determina a regra de dias da cobrança. |

Se houver mais de uma linha com o mesmo documento na Base Localiza, a aplicação mantém a primeira ocorrência encontrada.

### Planilha Conexa

A Planilha Conexa pode ser enviada em Excel ou CSV. Ela é a fonte principal das linhas do grid e precisa conter:

| Coluna aceita | Uso no processamento |
| --- | --- |
| `ID da Cobrança` ou `idcobranca` | Identificador da cobrança. |
| `CPF/CNPJ` ou `cpf/cnpj` | Documento usado para relacionar com Localiza e consultar/criar ticket no Movidesk. |
| `Razão Social Cliente` ou `razaosocial` | Razão social exibida no grid e enviada para o assunto/campo customizado do ticket. |
| `Valor` | Valor da cobrança, formatado como moeda brasileira no grid. |
| `Vencimento` | Data base para calcular a data de cobrança. |
| `Emails`, `E-mails` ou `Email` | E-mails normalizados para exibição e para criação de ticket. |
| `Telefone`, `Telefones` ou `Celular` | Primeiro telefone válido formatado para exibição e para criação de ticket. |

Linhas da Conexa sem dígitos no campo `CPF/CNPJ` são ignoradas.

## Relacionamento entre Conexa e Localiza

O relacionamento é feito da seguinte forma:

1. A Base Localiza é transformada em um mapa por documento, usando `digitsOnly(CNPJ/CPF)` como chave.
2. Para cada linha da Conexa, o sistema calcula `digitsOnly(CPF/CNPJ)`.
3. O sistema busca esse documento no mapa da Localiza.
4. Se encontrar, usa `Grupo` e `Modalidade` da Localiza.
5. Se não encontrar, `Grupo` fica vazio e `Modalidade` assume o padrão **CLIENTE FINAL**.

## Regras de cálculo e normalização

### Modalidade

A modalidade exibida no grid não é o texto cru da Base Localiza. Ela é normalizada assim:

| Valor da Base Localiza | Valor exibido |
| --- | --- |
| Vazio ou sem correspondência na Localiza | `CLIENTE FINAL` |
| Texto que contenha `whitelabel` após normalização | `WHITE LABEL` |
| Qualquer outro texto | `CLIENTE FINAL` |

### Regra de cobrança

A coluna **REGRA** é calculada pela modalidade normalizada:

| Modalidade | Regra exibida | Significado |
| --- | ---: | --- |
| `WHITE LABEL` | `3` | Cobra 3 dias após o vencimento. |
| `CLIENTE FINAL` | `7` | Cobra 7 dias após o vencimento. |

### Data cobrança

A coluna **DATA COBRANÇA** é calculada em três etapas:

1. O sistema interpreta o campo `Vencimento` da Conexa. São aceitos:
   - data ISO reconhecida pelo Dart;
   - data brasileira no formato `dd/mm/aaaa`;
   - número serial de data do Excel.
2. Soma a quantidade de dias da coluna **REGRA**.
3. Se a data cair em fim de semana ou feriado nacional brasileiro cadastrado no código, transfere para o próximo dia útil.

Quando a data é transferida para o próximo dia útil, o grid mostra um ícone de informação ao lado da data com a mensagem `transferida para o próximo dia util`.

Se o vencimento não puder ser interpretado, a coluna **DATA COBRANÇA** fica `—`.

### Cobrar

A coluna **COBRAR** compara a data de cobrança calculada com a data atual do processamento:

| Condição | Valor exibido |
| --- | --- |
| Data de cobrança menor que hoje | `Realizar cobrança` |
| Data de cobrança igual a hoje | `Vence hoje` |
| Data de cobrança maior que hoje ou data inválida | `No prazo` |

### Valor

O campo `Valor` da Conexa é exibido em formato brasileiro, por exemplo `R$ 1.234,56`. Se o valor não puder ser convertido para número, o texto original é mantido.

### E-mails

O campo `Emails` da Conexa é normalizado por expressão regular:

- extrai apenas textos com formato de e-mail válido;
- converte para minúsculas;
- remove duplicados;
- junta os e-mails com `; `.

### Telefone

O campo `Telefone` da Conexa é normalizado assim:

- usa apenas dígitos;
- procura o primeiro número com 10 ou 11 dígitos;
- formata 11 dígitos como `(DD) 99999-9999`;
- formata 10 dígitos como `(DD) 9999-9999`;
- se não encontrar telefone válido, exibe vazio.

## Colunas do grid

| Coluna no grid | Origem dos dados | Regra de preenchimento |
| --- | --- | --- |
| **ID COBRANÇA** | Planilha Conexa | Usa o valor da coluna `ID da Cobrança` / `idcobranca` sem transformação. |
| **CPF/CNPJ** | Planilha Conexa | Usa o valor da coluna `CPF/CNPJ` / `cpf/cnpj` como veio na planilha. O documento sem máscara é usado apenas internamente para relacionamento e Movidesk. |
| **RAZÃO SOCIAL** | Planilha Conexa | Usa o valor da coluna `Razão Social Cliente` / `razaosocial`. |
| **VALOR** | Planilha Conexa | Usa a coluna `Valor` e tenta formatar como moeda brasileira. |
| **VENCIMENTO** | Planilha Conexa | Usa o valor original da coluna `Vencimento`. |
| **REGRA** | Calculado | `3` para `WHITE LABEL`; `7` para `CLIENTE FINAL`. |
| **DATA COBRANÇA** | Calculado a partir do vencimento | Vencimento + regra de dias, ajustado para próximo dia útil se cair em fim de semana ou feriado nacional brasileiro. |
| **COBRAR** | Calculado | `Realizar cobrança`, `Vence hoje` ou `No prazo`, conforme comparação entre a data de cobrança e a data atual. |
| **GRUPO** | Base Localiza | Usa `Grupo` da Localiza quando o CNPJ/CPF da Conexa encontra correspondência. Caso contrário, fica vazio. |
| **MODALIDADE** | Base Localiza + regra de normalização | Exibe `WHITE LABEL` quando a modalidade da Localiza contém `whitelabel`; caso contrário, `CLIENTE FINAL`. |
| **EMAILS** | Planilha Conexa | Usa `Emails` / `E-mails` / `Email`, normalizando e-mails válidos e removendo duplicados. |
| **TELEFONE** | Planilha Conexa | Usa `Telefone` / `Telefones` / `Celular` e exibe o primeiro telefone válido formatado. |
| **TICKET** | Movidesk | Exibe o ID do ticket retornado/criado no Movidesk. Se não houver ticket, fica `—` na célula visual. |

## Consulta e criação de ticket no Movidesk

Para cada documento processado, a aplicação procura no Movidesk o ticket de cobrança mais recente com:

- assunto iniciado por `#Cobrança`;
- campo customizado de CNPJ igual ao CNPJ formatado;
- retorno limitado a `id` e `status`;
- ordenação por `id desc` e `top 1`.

A aplicação guarda em cache o ticket por CNPJ durante o processamento, evitando consultar ou criar mais de uma vez para o mesmo documento na mesma execução.

Um novo ticket pode ser criado quando as duas condições abaixo forem verdadeiras:

1. A coluna **COBRAR** for `Realizar cobrança`; ou for `Vence hoje` e a opção de abrir ticket no vencimento estiver ativada.
2. Não existir ticket encontrado; ou o ticket encontrado tiver status considerado fechado.

Status considerado fechado é qualquer texto que, após normalização, contenha:

- `fechado`;
- `resolvido`;
- `cancelado`.

Ao criar ticket, a aplicação envia ao Movidesk dados vindos da linha e/ou calculados:

| Campo enviado | Origem |
| --- | --- |
| Assunto `#Cobrança - razão social` | `Razão Social Cliente` da Conexa |
| CNPJ | `CPF/CNPJ` da Conexa, somente dígitos e formatado como CNPJ quando tiver 14 dígitos |
| Razão social | `Razão Social Cliente` da Conexa |
| ID da cobrança | `ID da Cobrança` da Conexa |
| E-mail | E-mails normalizados da Conexa |
| Telefone | Primeiro telefone válido da Conexa |
| Data de vencimento | Vencimento da Conexa convertido para data |
| Pessoa/cliente do ticket | Pessoa Movidesk encontrada pelo `Grupo` da Localiza; se não encontrar, usa a pessoa fallback configurada no código |

## Ordenação e filtro do grid

Antes de exibir, as linhas podem ser filtradas pelo campo de busca da tela:

1. Primeiro o sistema tenta buscar pelo texto digitado dentro do **GRUPO** normalizado.
2. Se nenhum grupo corresponder, tenta buscar os dígitos digitados dentro do **CPF/CNPJ**.

As linhas exibidas são ordenadas pelo campo **VENCIMENTO**, do vencimento mais antigo para o mais recente. Linhas com vencimento inválido ficam no fim da lista.

## Exportação CSV

A exportação CSV usa os mesmos dados do grid, com cabeçalhos equivalentes, e acrescenta informações de status e URL do ticket:

- `ID da Cobrança`
- `CPF/CNPJ`
- `Razão Social Cliente`
- `Valor`
- `Vencimento`
- `Pagamento regra`
- `Data cobrança`
- `Cobrar`
- `Grupo`
- `Modalidade`
- `Emails`
- `Telefone`
- `Ticket`
- `Status Ticket`
- `Ticket URL`

## Resumo rápido por fonte

| Fonte | Campos do grid alimentados |
| --- | --- |
| Planilha Conexa | **ID COBRANÇA**, **CPF/CNPJ**, **RAZÃO SOCIAL**, **VALOR**, **VENCIMENTO**, **EMAILS**, **TELEFONE** |
| Base Localiza | **GRUPO**, base para **MODALIDADE** |
| Cálculos internos | **REGRA**, **DATA COBRANÇA**, **COBRAR**, normalização de **VALOR**, **EMAILS** e **TELEFONE** |
| Movidesk | **TICKET** e status/URL usados na exportação |
