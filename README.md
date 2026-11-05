# QRCodePIX

Gera o **BR Code PIX** (padrão EMV do Banco Central) dos títulos do contas a receber do WinThor (`PCPREST`) e grava em `PCPREST.URLPIX` a URL do QR Code.

## O que é gravado

| Coluna (PCPREST) | Conteúdo |
|---|---|
| `URLPIX` | URL da imagem do QR Code (modelo configurável, com o BR Code já codificado) |
| `TXIDPIX` | TXID determinístico: `WT` + `NUMTRANSVENDA` (10 dígitos) + `PREST` |
| `EMVPIX` | BR Code "copia e cola" |

`TXIDPIX` e `EMVPIX` podem ser desligados com `p_gravar_emv_txid => FALSE` (aí só `URLPIX` é alterada). Nenhuma outra coluna é tocada.

## Instalação

```bash
sqlplus usuario/senha@banco @install.sql
sqlplus usuario/senha@banco @tests/test_qrcodepix.sql   # funções puras, não altera PCPREST
```

## Configuração

Chave PIX do recebedor, nesta ordem de prioridade:

1. Tabela `QRPIX_CONFIG` (uma linha por `CODFILIAL`);
2. `PCCOB.CHAVEBOLEPIX` da cobrança (`CODCOB`) do título.

```sql
INSERT INTO qrpix_config (codfilial, chave_pix) VALUES ('1', 'financeiro@suaempresa.com.br');
COMMIT;
```

Nome e cidade do recebedor vêm de `PCFILIAL` (`FANTASIA` ou `RAZAOSOCIAL`, e `CIDADE`).

**URL do QR Code:** o QR em si é a imagem do BR Code; PL/SQL não gera imagem, então `URLPIX` aponta para um renderizador. O padrão é `https://api.qrserver.com/v1/create-qr-code/?size=300x300&data={EMV}`. Ao abrir essa URL, o BR Code (chave, valor, TXID) é enviado ao serviço externo. Para evitar isso, hospede seu próprio renderizador e informe o modelo em `QRPIX_CONFIG.URL_TEMPLATE` (deve conter `{EMV}`).

## Uso

```sql
-- um título
DECLARE v VARCHAR2(20);
BEGIN
  v := pkg_qrcodepix.gerar_titulo(p_numtransvenda => 123456, p_prest => '1');
  COMMIT;  -- gerar_titulo não faz commit
END;
/

-- em lote: títulos em aberto sem URLPIX
SET SERVEROUTPUT ON
DECLARE
  v_ok PLS_INTEGER; v_err PLS_INTEGER;
BEGIN
  pkg_qrcodepix.gerar_pendentes(p_codfilial => '1',
                                p_dtvenc_ini => TRUNC(SYSDATE),
                                p_dtvenc_fim => TRUNC(SYSDATE) + 30,
                                p_limite => 500,
                                p_gerados => v_ok, p_erros => v_err);
  DBMS_OUTPUT.PUT_LINE(v_ok || ' gerados, ' || v_err || ' com erro');
END;
/
```

Entram no lote títulos com `DTPAG` e `DTCANCEL` nulos, `BAIXADOVIAPIX` diferente de `S`, `VALOR > 0` e `URLPIX` vazia (ou todos, com `p_regravar => TRUE`).

## Limitações

- O valor do QR é `PCPREST.VALOR`; juros, multa e descontos **não** são calculados.
- O BR Code é estático (reutilizável): a conciliação deve usar o `TXIDPIX`. A baixa automática não faz parte deste projeto.
- O `UPDATE` em `PCPREST` pode disparar triggers do WinThor; teste em homologação primeiro.
- Cadeias com acentos dependem da conversão `CONVERT(..., 'US7ASCII')` do seu banco.
