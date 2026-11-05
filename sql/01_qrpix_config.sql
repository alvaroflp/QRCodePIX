-- Configuração do PIX por filial. Script idempotente (ignora ORA-00955).
--
--   CHAVE_PIX    : chave PIX do recebedor (e-mail, CPF/CNPJ, telefone +55..., ou EVP/UUID).
--                  Se não houver linha para a filial, o pacote usa PCCOB.CHAVEBOLEPIX
--                  da cobrança do título.
--   URL_TEMPLATE : (opcional) modelo da URL que renderiza o QR Code como imagem. Deve conter
--                  o marcador {EMV}, substituído pelo BR Code (copia e cola) já codificado
--                  para URL. Se nulo, usa o padrão definido em PKG_QRCODEPIX.
BEGIN
  EXECUTE IMMEDIATE '
    CREATE TABLE qrpix_config (
      codfilial    VARCHAR2(2)   NOT NULL,
      chave_pix    VARCHAR2(77)  NOT NULL,
      url_template VARCHAR2(500),
      CONSTRAINT pk_qrpix_config PRIMARY KEY (codfilial)
    )';
EXCEPTION
  WHEN OTHERS THEN
    IF SQLCODE <> -955 THEN
      RAISE;
    END IF;
END;
/
