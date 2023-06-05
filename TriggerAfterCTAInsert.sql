SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE TRIGGER TriggerAfterCTAInsert
   ON  [dbo].[CuentaTarjetaAdicional]
   AFTER INSERT
AS 
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[SubestadoCuenta](
			[IdCuentaTarjetaAdicional]
			, [Fecha]
			, [QOperacionesATM]
			, [QOperacionesVentana]
			, [QCompras]
			, [SumaCompras]
			, [QRetiros]
			, [SumaRetiros]
			)
	SELECT
		[IdCuentaTarjeta]
		, CONVERT(DATE, '1-1-1')
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
	FROM inserted;

    SET NOCOUNT OFF;

END;
GO
