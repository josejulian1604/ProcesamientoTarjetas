USE [Tarea2]
GO
/****** Object:  Trigger [dbo].[TriggerAfterCTMInsert]    Script Date: 6/3/2023 9:01:45 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER TRIGGER [dbo].[TriggerAfterCTMInsert]
	ON [dbo].[CuentaTarjetaMaestra]
	AFTER INSERT 
AS
BEGIN
	
	SET NOCOUNT ON;

	INSERT INTO [dbo].[EstadoCuenta] (
			[IdCuentaTarjetaMaestra]
			, [Fecha]
			, [SaldoActual]
			, [PagoMinimo]
			, [FechaPagoMinimo]
			, [IntCorrAcum]
			, [IntMoratorio]
			, [QOperacionesATM]
			, [QOperacionesVentana]
			, [SumaPagosFechaPagoMinimo]
			, [SumaPagosMes]
			, [QPagosMes]
			, [SumaCompras]
			, [QCompras]
			, [SumaRetiros]
			, [QRetiros]
			, [SumaCreditos]
			, [QCreditos]
			, [SumaDebitos]
			, [QDebitos]
			)
	SELECT 
		[IdCuentaTarjeta]
		, (SELECT CONVERT(DATE, '1-1-1'))
		, 0
		, 0
		, (SELECT CONVERT(DATE, '1-1-1'))
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
		, 0
	FROM inserted;

	SET NOCOUNT OFF;
END;