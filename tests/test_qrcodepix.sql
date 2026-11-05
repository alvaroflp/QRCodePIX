-- Testes das funções puras (não alteram PCPREST). Valores esperados calculados por uma
-- implementação independente do padrão (CRC16-CCITT-FALSE, "123456789" = 29B1).
SET SERVEROUTPUT ON
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
DECLARE
  v_emv VARCHAR2(512);
  PROCEDURE eq(p_nome VARCHAR2, p_esp VARCHAR2, p_obt VARCHAR2) IS
  BEGIN
    IF p_esp = p_obt THEN
      DBMS_OUTPUT.PUT_LINE('OK    ' || p_nome);
    ELSE
      RAISE_APPLICATION_ERROR(-20999, 'FALHOU ' || p_nome || ': esperado=' || p_esp || ' obtido=' || p_obt);
    END IF;
  END;
  PROCEDURE erro(p_nome VARCHAR2, p_cod NUMBER, p_chave VARCHAR2, p_valor NUMBER, p_txid VARCHAR2) IS
    v VARCHAR2(512);
  BEGIN
    v := pkg_qrcodepix.gerar_emv(p_chave, p_valor, 'X', 'Y', p_txid);
    RAISE_APPLICATION_ERROR(-20999, 'FALHOU ' || p_nome || ': esperava erro');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = p_cod THEN
        DBMS_OUTPUT.PUT_LINE('OK    ' || p_nome);
      ELSE
        RAISE;
      END IF;
  END;
BEGIN
  eq('crc16 vetor padrão', '29B1', pkg_qrcodepix.crc16('123456789'));
  eq('txid do título', 'WT000000123451', pkg_qrcodepix.txid_titulo(12345, '1'));
  eq('sanitizar acentos', 'ACAO SAO JOSE', pkg_qrcodepix.sanitizar(UNISTR('A\00E7\00E3o S\00E3o Jos\00E9 #!'), 25));

  v_emv := pkg_qrcodepix.gerar_emv('teste@exemplo.com', 123.45, 'EMPRESA TESTE LTDA', 'SAO PAULO', 'WT000000123451');
  eq('BR Code completo',
     '00020101021126390014br.gov.bcb.pix0117teste@exemplo.com5204000053039865406123.455802BR5918EMPRESA TESTE LTDA6009SAO PAULO62180514WT0000001234516304DB05',
     v_emv);
  eq('CRC do BR Code confere', SUBSTR(v_emv, -4), pkg_qrcodepix.crc16(SUBSTR(v_emv, 1, LENGTH(v_emv) - 4)));
  eq('valor com ponto decimal (nunca vírgula)', '5406123.45', SUBSTR(v_emv, INSTR(v_emv, '5406'), 10));

  eq('url padrão', 'https://api.qrserver.com/v1/create-qr-code/?size=300x300&data=ABC%40D%2F1',
     pkg_qrcodepix.montar_url('ABC@D/1'));
  eq('url com modelo próprio', 'https://qr.exemplo.com.br/i?c=A%20B',
     pkg_qrcodepix.montar_url('A B', 'https://qr.exemplo.com.br/i?c={EMV}'));

  erro('valor zero', -20101, 'chave@x.com', 0, 'WT1');
  erro('chave vazia', -20101, NULL, 10, 'WT1');
  erro('txid inválido', -20101, 'chave@x.com', 10, 'WT-1');
  BEGIN
    v_emv := pkg_qrcodepix.montar_url('X', 'https://sem-marcador');
    RAISE_APPLICATION_ERROR(-20999, 'FALHOU modelo sem marcador');
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLCODE = -20104 THEN DBMS_OUTPUT.PUT_LINE('OK    modelo sem {EMV}'); ELSE RAISE; END IF;
  END;
END;
/
EXIT
