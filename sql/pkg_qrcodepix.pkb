CREATE OR REPLACE PACKAGE BODY pkg_qrcodepix AS

  ---------------------------------------------------------------------------
  -- Utilitários do BR Code
  ---------------------------------------------------------------------------
  FUNCTION tlv(p_id IN VARCHAR2, p_valor IN VARCHAR2) RETURN VARCHAR2 IS
  BEGIN
    IF LENGTH(p_valor) > 99 THEN
      RAISE_APPLICATION_ERROR(-20101, 'Campo ' || p_id || ' excede 99 caracteres.');
    END IF;
    RETURN p_id || LPAD(LENGTH(p_valor), 2, '0') || p_valor;
  END tlv;

  FUNCTION bxor(p_a IN PLS_INTEGER, p_b IN PLS_INTEGER) RETURN PLS_INTEGER IS
  BEGIN
    RETURN p_a + p_b - 2 * BITAND(p_a, p_b);
  END bxor;

  FUNCTION sanitizar(p_texto IN VARCHAR2, p_tamanho IN PLS_INTEGER) RETURN VARCHAR2 IS
  BEGIN
    RETURN SUBSTR(TRIM(REGEXP_REPLACE(UPPER(CONVERT(p_texto, 'US7ASCII')),
                                      '[^A-Z0-9 ]',
                                      '')),
                  1,
                  p_tamanho);
  END sanitizar;

  FUNCTION crc16(p_payload IN VARCHAR2) RETURN VARCHAR2 IS
    v_crc PLS_INTEGER := 65535; -- 0xFFFF
  BEGIN
    FOR i IN 1 .. LENGTH(p_payload) LOOP
      v_crc := bxor(v_crc, ASCII(SUBSTR(p_payload, i, 1)) * 256);
      FOR j IN 1 .. 8 LOOP
        IF BITAND(v_crc, 32768) <> 0 THEN
          v_crc := bxor(MOD(v_crc * 2, 65536), 4129); -- 0x1021
        ELSE
          v_crc := MOD(v_crc * 2, 65536);
        END IF;
      END LOOP;
    END LOOP;
    RETURN LPAD(TO_CHAR(v_crc, 'FMXXXX'), 4, '0');
  END crc16;

  FUNCTION txid_titulo(p_numtransvenda IN NUMBER, p_prest IN VARCHAR2)
    RETURN VARCHAR2 IS
  BEGIN
    RETURN 'WT' || LPAD(TO_CHAR(p_numtransvenda, 'FM9999999999'), 10, '0') ||
           REGEXP_REPLACE(UPPER(p_prest), '[^A-Z0-9]', '');
  END txid_titulo;

  FUNCTION gerar_emv(p_chave  IN VARCHAR2,
                     p_valor  IN NUMBER,
                     p_nome   IN VARCHAR2,
                     p_cidade IN VARCHAR2,
                     p_txid   IN VARCHAR2) RETURN VARCHAR2 IS
    v_payload VARCHAR2(512);
    v_nome    VARCHAR2(25) := NVL(sanitizar(p_nome, 25), 'RECEBEDOR');
    v_cidade  VARCHAR2(15) := NVL(sanitizar(p_cidade, 15), 'BRASIL');
  BEGIN
    IF p_chave IS NULL OR LENGTH(p_chave) > 77 OR
       NOT REGEXP_LIKE(p_chave, '^[ -~]+$') THEN
      RAISE_APPLICATION_ERROR(-20101, 'Chave PIX inválida (1-77 caracteres ASCII).');
    END IF;
    IF p_valor IS NULL OR ROUND(p_valor, 2) <= 0 OR ROUND(p_valor, 2) > 9999999999.99 THEN
      RAISE_APPLICATION_ERROR(-20101, 'Valor inválido para o PIX.');
    END IF;
    IF p_txid IS NULL OR NOT REGEXP_LIKE(p_txid, '^[A-Za-z0-9]{1,25}$') THEN
      RAISE_APPLICATION_ERROR(-20101, 'TXID inválido (1-25 caracteres alfanuméricos).');
    END IF;

    v_payload := tlv('00', '01') || -- versão do payload
                 tlv('01', '11') || -- estático (reutilizável; conciliar pelo TXID)
                 tlv('26', tlv('00', 'br.gov.bcb.pix') || tlv('01', p_chave)) ||
                 tlv('52', '0000') || -- categoria do comerciante
                 tlv('53', '986') || -- moeda BRL
                 tlv('54', TO_CHAR(ROUND(p_valor, 2), 'FM9999999990.00', 'NLS_NUMERIC_CHARACTERS=''.,''')) ||
                 tlv('58', 'BR') ||
                 tlv('59', v_nome) ||
                 tlv('60', v_cidade) ||
                 tlv('62', tlv('05', p_txid)) ||
                 '6304';
    RETURN v_payload || crc16(v_payload);
  END gerar_emv;

  FUNCTION montar_url(p_emv IN VARCHAR2, p_template IN VARCHAR2 DEFAULT NULL)
    RETURN VARCHAR2 IS
    v_tpl VARCHAR2(500) := NVL(p_template, c_url_template_padrao);
    v_url VARCHAR2(4000);
  BEGIN
    IF INSTR(v_tpl, '{EMV}') = 0 THEN
      RAISE_APPLICATION_ERROR(-20104, 'O modelo de URL deve conter o marcador {EMV}.');
    END IF;
    v_url := REPLACE(v_tpl, '{EMV}', UTL_URL.ESCAPE(p_emv, TRUE, 'AL32UTF8'));
    IF LENGTH(v_url) > 1000 THEN
      RAISE_APPLICATION_ERROR(-20104, 'URL gerada excede 1000 caracteres (PCPREST.URLPIX).');
    END IF;
    RETURN v_url;
  END montar_url;

  ---------------------------------------------------------------------------
  -- PCPREST
  ---------------------------------------------------------------------------
  FUNCTION gerar_titulo(p_numtransvenda   IN NUMBER,
                        p_prest           IN VARCHAR2,
                        p_regravar        IN BOOLEAN DEFAULT FALSE,
                        p_gravar_emv_txid IN BOOLEAN DEFAULT TRUE)
    RETURN VARCHAR2 IS
    v_valor    pcprest.valor%TYPE;
    v_dtpag    pcprest.dtpag%TYPE;
    v_dtcancel pcprest.dtcancel%TYPE;
    v_baixapix pcprest.baixadoviapix%TYPE;
    v_urlpix   pcprest.urlpix%TYPE;
    v_filial   pcprest.codfilial%TYPE;
    v_chave    VARCHAR2(260);
    v_template VARCHAR2(500);
    v_nome     VARCHAR2(60);
    v_cidade   VARCHAR2(30);
    v_txid     VARCHAR2(25);
    v_emv      VARCHAR2(512);
    v_url      VARCHAR2(1000);
  BEGIN
    BEGIN
      SELECT p.valor,
             p.dtpag,
             p.dtcancel,
             p.baixadoviapix,
             p.urlpix,
             p.codfilial,
             NVL(c.chave_pix, b.chavebolepix),
             c.url_template,
             NVL(f.fantasia, f.razaosocial),
             f.cidade
        INTO v_valor,
             v_dtpag,
             v_dtcancel,
             v_baixapix,
             v_urlpix,
             v_filial,
             v_chave,
             v_template,
             v_nome,
             v_cidade
        FROM pcprest p
        LEFT JOIN pcfilial f ON f.codigo = p.codfilial
        LEFT JOIN pccob b ON b.codcob = p.codcob
        LEFT JOIN qrpix_config c ON c.codfilial = p.codfilial
       WHERE p.numtransvenda = p_numtransvenda
         AND p.prest = p_prest;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20102,
                                'Título não encontrado: NUMTRANSVENDA=' ||
                                p_numtransvenda || ' PREST=' || p_prest);
    END;

    IF v_dtpag IS NOT NULL OR v_dtcancel IS NOT NULL OR NVL(v_baixapix, 'N') = 'S' THEN
      RETURN 'QUITADO';
    END IF;
    IF v_urlpix IS NOT NULL AND NOT p_regravar THEN
      RETURN 'JA_POSSUI';
    END IF;
    IF v_chave IS NULL THEN
      RAISE_APPLICATION_ERROR(-20103,
                              'Sem chave PIX para a filial ' || v_filial ||
                              ' (QRPIX_CONFIG ou PCCOB.CHAVEBOLEPIX).');
    END IF;

    v_txid := txid_titulo(p_numtransvenda, p_prest);
    v_emv  := gerar_emv(v_chave, v_valor, v_nome, v_cidade, v_txid);
    v_url  := montar_url(v_emv, v_template);

    IF p_gravar_emv_txid THEN
      UPDATE pcprest
         SET urlpix = v_url, txidpix = v_txid, emvpix = v_emv
       WHERE numtransvenda = p_numtransvenda
         AND prest = p_prest;
    ELSE
      UPDATE pcprest
         SET urlpix = v_url
       WHERE numtransvenda = p_numtransvenda
         AND prest = p_prest;
    END IF;
    RETURN 'GERADO';
  END gerar_titulo;

  PROCEDURE gerar_pendentes(p_codfilial       IN VARCHAR2 DEFAULT NULL,
                            p_codcob          IN VARCHAR2 DEFAULT NULL,
                            p_dtvenc_ini      IN DATE DEFAULT NULL,
                            p_dtvenc_fim      IN DATE DEFAULT NULL,
                            p_regravar        IN BOOLEAN DEFAULT FALSE,
                            p_limite          IN PLS_INTEGER DEFAULT NULL,
                            p_gravar_emv_txid IN BOOLEAN DEFAULT TRUE,
                            p_commit          IN BOOLEAN DEFAULT TRUE,
                            p_gerados         OUT PLS_INTEGER,
                            p_erros           OUT PLS_INTEGER) IS
    v_regravar VARCHAR2(1) := CASE WHEN p_regravar THEN 'S' ELSE 'N' END;
    v_status   VARCHAR2(20);
  BEGIN
    p_gerados := 0;
    p_erros   := 0;
    FOR t IN (SELECT numtransvenda, prest
                FROM pcprest
               WHERE dtpag IS NULL
                 AND dtcancel IS NULL
                 AND NVL(baixadoviapix, 'N') <> 'S'
                 AND valor > 0
                 AND (v_regravar = 'S' OR urlpix IS NULL)
                 AND (p_codfilial IS NULL OR codfilial = p_codfilial)
                 AND (p_codcob IS NULL OR codcob = p_codcob)
                 AND (p_dtvenc_ini IS NULL OR dtvenc >= p_dtvenc_ini)
                 AND (p_dtvenc_fim IS NULL OR dtvenc <= p_dtvenc_fim)
                 AND ROWNUM <= NVL(p_limite, 999999999)) LOOP
      BEGIN
        v_status := gerar_titulo(t.numtransvenda,
                                 t.prest,
                                 p_regravar,
                                 p_gravar_emv_txid);
        IF v_status = 'GERADO' THEN
          p_gerados := p_gerados + 1;
        END IF;
      EXCEPTION
        WHEN OTHERS THEN
          p_erros := p_erros + 1;
          DBMS_OUTPUT.PUT_LINE('ERRO NUMTRANSVENDA=' || t.numtransvenda ||
                               ' PREST=' || t.prest || ': ' || SQLERRM);
      END;
    END LOOP;
    IF p_commit THEN
      COMMIT;
    END IF;
  END gerar_pendentes;

END pkg_qrcodepix;
/
