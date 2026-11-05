-- Gera o BR Code PIX (padrão EMV QRCPS-MPM do Banco Central) para títulos do contas a
-- receber (PCPREST) e grava em PCPREST.URLPIX a URL do QR Code correspondente.
--
-- Colunas de PCPREST usadas: NUMTRANSVENDA + PREST (chave), VALOR, DTPAG, DTCANCEL,
-- CODFILIAL, CODCOB, BAIXADOVIAPIX, URLPIX, TXIDPIX, EMVPIX.
-- Erros: ORA-20101 dado inválido para o BR Code | ORA-20102 título não encontrado
--        ORA-20103 chave PIX não configurada     | ORA-20104 URL do QR Code inválida
CREATE OR REPLACE PACKAGE pkg_qrcodepix AS

  c_url_template_padrao CONSTANT VARCHAR2(200) :=
    'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data={EMV}';

  -- Remove acentos/símbolos, deixa maiúsculo e trunca (campos do BR Code são ASCII)
  FUNCTION sanitizar(p_texto IN VARCHAR2, p_tamanho IN PLS_INTEGER) RETURN VARCHAR2;

  -- CRC16-CCITT (poly 0x1021, init 0xFFFF) em 4 hex maiúsculos
  FUNCTION crc16(p_payload IN VARCHAR2) RETURN VARCHAR2;

  -- TXID determinístico do título: 'WT' || NUMTRANSVENDA (10 dígitos) || PREST
  FUNCTION txid_titulo(p_numtransvenda IN NUMBER, p_prest IN VARCHAR2)
    RETURN VARCHAR2;

  -- BR Code estático com valor e TXID (o "copia e cola")
  FUNCTION gerar_emv(p_chave  IN VARCHAR2,
                     p_valor  IN NUMBER,
                     p_nome   IN VARCHAR2,
                     p_cidade IN VARCHAR2,
                     p_txid   IN VARCHAR2) RETURN VARCHAR2;

  -- URL da imagem do QR Code (substitui {EMV} no modelo pelo BR Code codificado)
  FUNCTION montar_url(p_emv IN VARCHAR2, p_template IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2;

  -- Gera para um título. Retorna 'GERADO', 'JA_POSSUI' (URLPIX preenchida e
  -- p_regravar = FALSE) ou 'QUITADO' (pago, cancelado ou baixado via PIX).
  -- Não faz COMMIT.
  FUNCTION gerar_titulo(p_numtransvenda   IN NUMBER,
                        p_prest           IN VARCHAR2,
                        p_regravar        IN BOOLEAN DEFAULT FALSE,
                        p_gravar_emv_txid IN BOOLEAN DEFAULT TRUE)
    RETURN VARCHAR2;

  -- Gera para todos os títulos em aberto que atendam aos filtros.
  -- Erros em um título são exibidos via DBMS_OUTPUT e não interrompem o lote.
  PROCEDURE gerar_pendentes(p_codfilial       IN VARCHAR2 DEFAULT NULL,
                            p_codcob          IN VARCHAR2 DEFAULT NULL,
                            p_dtvenc_ini      IN DATE DEFAULT NULL,
                            p_dtvenc_fim      IN DATE DEFAULT NULL,
                            p_regravar        IN BOOLEAN DEFAULT FALSE,
                            p_limite          IN PLS_INTEGER DEFAULT NULL,
                            p_gravar_emv_txid IN BOOLEAN DEFAULT TRUE,
                            p_commit          IN BOOLEAN DEFAULT TRUE,
                            p_gerados         OUT PLS_INTEGER,
                            p_erros           OUT PLS_INTEGER);

END pkg_qrcodepix;
/
