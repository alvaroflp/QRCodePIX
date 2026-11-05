-- Execute na raiz do repositório, conectado no mesmo schema que contém PCPREST
-- (ou em outro schema com SELECT/UPDATE em PCPREST e SELECT em PCFILIAL e PCCOB):
--   sqlplus usuario/senha@banco @install.sql
SET DEFINE OFF
WHENEVER SQLERROR EXIT FAILURE ROLLBACK
@sql/01_qrpix_config.sql
@sql/pkg_qrcodepix.pks
@sql/pkg_qrcodepix.pkb
PROMPT Instalado.
