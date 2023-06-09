USE [Tarea2]
GO
/****** Object:  Trigger [dbo].[TriggerAfterCTAInsert]    Script Date: 6/18/2023 2:10:16 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER TRIGGER [dbo].[TriggerAfterCTAInsert]
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
			, [SumaCreditos]
			, [SumaDebitos]
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
		, 0
		, 0
	FROM inserted;

	UPDATE [dbo].[CuentaTarjetaAdicional] 
	SET LastSECId = SEC.Id
	FROM [dbo].[CuentaTarjetaAdicional] CTA
	INNER JOIN [dbo].[SubestadoCuenta] SEC ON SEC.IdCuentaTarjetaAdicional = CTA.IdCuentaTarjeta
    SET NOCOUNT OFF;

END;
