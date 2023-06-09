USE [Tarea2]
GO
/****** Object:  StoredProcedure [dbo].[ProcesamientoDiario]    Script Date: 6/18/2023 8:55:26 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER PROCEDURE [dbo].[ProcesamientoDiario]
	@inRutaXML NVARCHAR(500)
	, @outResultCode INT OUTPUT
AS
BEGIN
	--BEGIN TRY
	SET NOCOUNT ON;
	DECLARE @Datos xml;
	DECLARE @Comando NVARCHAR(500)= 'SELECT @Datos = D FROM OPENROWSET (BULK '  + CHAR(39) + @inRutaXML + CHAR(39) + ', SINGLE_BLOB) AS Datos(D)' -- comando que va a ejecutar el sql dinamico
    DECLARE @Parametros NVARCHAR(500)
	DECLARE @hdoc int /*Creamos hdoc que va a ser un identificador*/

	SET @Parametros = N'@Datos xml OUTPUT'
	

	EXECUTE sp_executesql @Comando, @Parametros, @Datos OUTPUT -- ejecutamos el comando que hicimos dinamicamente

	EXEC sp_xml_preparedocument @hdoc OUTPUT, @Datos/*Toma el identificador y a la variable con el documento y las asocia*/
	DECLARE @Fechas TABLE (
			Fecha DATE
	);
	DECLARE @FechaItera DATE
			, @FechaFinal DATE
			, @EsMaestra INT; -- 0 si es FALSE, 1 si es TRUE
	DECLARE @NuevosTH TABLE (
			Id INT IDENTITY(1, 1)
			, Nombre VARCHAR(128)
			, TipoDocId VARCHAR(128)
			, ValorDocId VARCHAR(128)
			, Username VARCHAR(128)
			, Password VARCHAR(128)
			);
	DECLARE @NuevosTCM TABLE (
			Id INT IDENTITY (1, 1)
			, Codigo VARCHAR(128)
			, TipoCTM VARCHAR(128)
			, LimiteCredito MONEY
			, TarjetaHabiente VARCHAR(128)
			);
	DECLARE @NuevosTCA TABLE (
			Id INT IDENTITY (1, 1)
			, CodigoTCM VARCHAR(128)
			, CodigoTCA VARCHAR(128)
			, TarjetaHabiente VARCHAR(128)
			);
	DECLARE @NuevosTCATemp TABLE (
			IdCTA INT
			, CodigoTCA VARCHAR(128)
			);
	DECLARE @NuevosTF TABLE (
			Codigo VARCHAR(128)
			, CodigoCT VARCHAR(128)
			, FechaVencimiento VARCHAR(128)
			, CVV INT
			);
	DECLARE @NuevosMovimientos TABLE (
			Id INT IDENTITY(1, 1)
			, Nombre VARCHAR(128)
			, TF VARCHAR(128)
			, FechaMovimiento DATE
			, Monto MONEY
			, Descripcion VARCHAR(128)
			, Referencia VARCHAR(128)
			);
	DECLARE @MovimientosEspejo TABLE (
			Id INT IDENTITY(1, 1)
			, IdCuentaTarjeta INT
			, IdEstadoCuenta INT NULL
			, IdSubestadoCuenta INT NULL
			, IdTarjetaFisica INT
			, IdTipoMovimiento INT
			, Descripcion VARCHAR(128)
			, Fecha DATE
			, Monto MONEY
			, Referencia VARCHAR(128)
			, NuevoSaldo MONEY
			);
	DECLARE @MovimientoIntCorr TABLE (
			Id INT IDENTITY(1, 1)
			, IdCuentaTarjetaMaestra INT
			, IdTipoMovimientoIntCorr INT
			, Fecha DATE 
			, Monto MONEY
			, NuevoIntAcumCorriente MONEY
			);
	DECLARE @MovimientoIntMor TABLE (
			Id INT IDENTITY(1, 1)
			, IdCuentaTarjetaMaestra INT
			, IdTipoMovimientoIntMor INT
			, Fecha DATE
			, Monto MONEY
			, NuevoIntAcumMoratorio MONEY
			);
	DECLARE @MovimientoSospechoso TABLE (
			Id INT IDENTITY(1, 1)
			, IdCuentaTarjetaMaestra INT
			, IdTarjetaFisica INT 
			, Fecha DATE
			, Monto MONEY
			, Descripcion VARCHAR(128)
			, Referencia VARCHAR(128)
			);
	DECLARE @TarjetasSospechosas TABLE (
			IdNuevoMovimiento INT
			, Codigo VARCHAR(128)
			, Nombre VARCHAR(128)
			);
	DECLARE @TFRobadasPerdidas TABLE (
			IdNuevoMovimiento INT
			, Codigo VARCHAR(128)
			, Nombre VARCHAR(128)
			);
	DECLARE @CierraEC TABLE (
			IdCTM INT
			);
	DECLARE @CierraSubEC TABLE (
			IdCTA INT
			);
	DECLARE @ContadoresEC TABLE (
			IdCuentaTarjetaMaestra INT
			, QOperacionesATM INT
			, QOperacionesVentana INT
			, SumaPagosFechaPagoMinimo MONEY
			, SumaPagosMes MONEY
			, QPagosMes INT
			, SumaCompras MONEY
			, QCompras INT
			, SumaRetiros MONEY
			, QRetiros INT
			, SumaCreditos MONEY
			, QCreditos INT
			, SumaDebitos MONEY
			, QDebitos INT
			);
	DECLARE @ContadoresSubEC TABLE (
			IdCTA INT
			, QOperacionesATM INT
			, QOperacionesVentana INT
			, QCompras INT
			, SumaCompras MONEY
			, QRetiros INT
			, SumaRetiros MONEY
			, SumaCreditos MONEY
			, SumaDebitos MONEY
			);
	DECLARE @CTMItera TABLE (
			IdCuentaTarjeta INT
			);
	
	DECLARE @MovimientosCTMActual TABLE (
			Id INT IDENTITY(1, 1)
			, IdCuentaTarjeta INT
			, IdEstadoCuenta INT NULL
			, IdSubestadoCuenta INT NULL
			, IdTarjetaFisica INT
			, IdTipoMovimiento INT
			, Descripcion VARCHAR(128)
			, Fecha DATE
			, Monto MONEY
			, Referencia VARCHAR(128)
			, NuevoSaldo MONEY
			);
	DECLARE @SaldoItera MONEY
			, @InteresCorrienteCTMActual MONEY
			, @InteresMoratorioCTMActual MONEY
			, @InteresAcumCorr MONEY
			, @InteresAcumMor MONEY
			, @TotalCargosXServicio MONEY
			, @TotalCargosXMulta MONEY
			, @DiasExtraFechaPagoMinimo INT
			, @LastIdEC INT
			, @LastIdSEC INT;
	-- Se extraen todas las fechas --
	INSERT INTO @Fechas
		(
		[Fecha]
		)
	SELECT 
		fechaOP.Fecha
	FROM OPENXML (@hdoc, '/root/fechaOperacion', 1)
	WITH
		(
		Fecha DATE
		) AS fechaOP
	
	SELECT @FechaItera = MIN(F.Fecha)
	FROM @Fechas F

	SELECT @FechaFinal = MAX(F.Fecha)--CONVERT(DATE, '2023-07-08')
	FROM @Fechas F

	WHILE (@FechaItera <= @FechaFinal)
	BEGIN
	/*######################## DATOS DE OPERACION PARA FECHA ITERA ########################*/

		/*-----------------------INSERTAR NUEVOS TH-------------------*/
		INSERT INTO @NuevosTH
				(
				[Nombre]
				, [TipoDocId]
				, [ValorDocId]
				, [Username]
				, [Password]
				)
		SELECT 
			T.Item.value('@Nombre', 'VARCHAR(128)'),
			T.Item.value('@Tipo_Doc_Identidad', 'VARCHAR(128)'),
			T.Item.value('@Valor_Doc_Identidad', 'VARCHAR(128)'),
			T.Item.value('@NombreUsuario', 'VARCHAR(128)'),
			T.Item.value('@Password', 'VARCHAR(128)')
		FROM @Datos.nodes('/root/fechaOperacion[@Fecha = sql:variable("@FechaItera")]/TH/TH') AS T(Item);
		
		INSERT INTO [dbo].[TarjetaHabiente]
					(
					[IdTipoDocId]
					, [Nombre]
					, [ValorDocId]
					, [Username]
					, [Password]
					)
		SELECT
			TD.Id
			, NTH.Nombre
			, NTH.ValorDocId
			, NTH.Username
			, NTH.Password
		FROM @NuevosTH NTH
		INNER JOIN [dbo].[TipoDocId] TD ON TD.Nombre = NTH.TipoDocId
		
		DELETE @NuevosTH

		/*-----------------------INSERTAR NTCM-------------------*/
		INSERT INTO @NuevosTCM
					(
					[Codigo]
					, [TipoCTM]
					, [LimiteCredito]
					, [TarjetaHabiente]
					)
		SELECT 
			T.Item.value('@Codigo', 'VARCHAR(128)'),
			T.Item.value('@TipoCTM', 'VARCHAR(128)'),
			T.Item.value('@LimiteCredito', 'MONEY'),
			T.Item.value('@TH', 'VARCHAR(128)')
		FROM @Datos.nodes('/root/fechaOperacion[@Fecha = sql:variable("@FechaItera")]/NTCM/NTCM') AS T(Item);

		SET @EsMaestra = 1;
		
		INSERT INTO [dbo].[CuentaTarjeta]
					(
					[IdTarjetaHabiente]
					, [IdTipoCuentaTarjeta]
					, [Codigo]
					, [EsMaestra]
					, [FechaCreacion]
					)
		SELECT
			TH.Id
			, TCT.Id
			, NTCM.Codigo
			, @EsMaestra
			, @FechaItera
		FROM @NuevosTCM NTCM
		INNER JOIN [dbo].[TarjetaHabiente] TH ON TH.ValorDocId = NTCM.TarjetaHabiente
		INNER JOIN [dbo].[TipoCuentaTarjeta] TCT ON TCT.Nombre = NTCM.TipoCTM

		INSERT INTO [dbo].[CuentaTarjetaMaestra]
					(
					[IdCuentaTarjeta]
					, [LimiteCredito]
					, [Saldo]
					, [InteresAcumuladoCorriente]
					, [InteresAcumuladoMoratorio]
					, [LastId]
					)
		SELECT 
			CT.Id
			, NTCM.LimiteCredito
			, 0
			, 0
			, 0
			, 0
		FROM @NuevosTCM NTCM
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Codigo = NTCM.Codigo
		
		DELETE @NuevosTCM

		/*-----------------------INSERTAR NTCA-------------------*/
		INSERT INTO @NuevosTCA
					(
					[CodigoTCM]
					, [CodigoTCA]
					, [TarjetaHabiente]
					)
		SELECT 
			T.Item.value('@CodigoTCM', 'VARCHAR(128)'),
			T.Item.value('@CodigoTCA', 'VARCHAR(128)'),
			T.Item.value('@TH', 'VARCHAR(128)')
		FROM @Datos.nodes('/root/fechaOperacion[@Fecha = sql:variable("@FechaItera")]/NTCA/NTCA') AS T(Item);

		SET @EsMaestra = 0;

		INSERT INTO [dbo].[CuentaTarjeta]
					(
					[IdTarjetaHabiente]
					, [IdTipoCuentaTarjeta]
					, [Codigo]
					, [EsMaestra]
					, [FechaCreacion]
					)
		SELECT
			TH.Id
			, CT.IdTipoCuentaTarjeta
			, NTCA.CodigoTCA
			, @EsMaestra
			, @FechaItera
		FROM @NuevosTCA NTCA
		INNER JOIN [dbo].[TarjetaHabiente] TH ON TH.ValorDocId = NTCA.TarjetaHabiente
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Codigo = NTCA.CodigoTCM


		DELETE @NuevosTCATemp
		INSERT INTO @NuevosTCATemp -- Se inserta para poder mapear el id de la instancia CuentaTarjetaAdicional
					(
					[IdCTA]
					, [CodigoTCA]
					)
		SELECT 
			CT.Id
			, CT.Codigo
		FROM @NuevosTCA NTCA
		INNER JOIN [dbo].[TarjetaHabiente] TH ON TH.ValorDocId = NTCA.TarjetaHabiente
		INNER JOIN [dbo].[CuentaTarjeta] CT ON TH.Id = CT.IdTarjetaHabiente 


		INSERT INTO [dbo].[CuentaTarjetaAdicional]
					(
					[IdCuentaTarjeta]
					, [IdCuentaTarjetaMaestra]
					, [LastSECId]
					)
		SELECT 
			NTCATemp.IdCTA
			, CT.Id
			, 0
		FROM @NuevosTCA NTCA
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Codigo = NTCA.CodigoTCM
		INNER JOIN @NuevosTCATemp NTCATemp ON NTCATemp.CodigoTCA = NTCA.CodigoTCA

		DELETE @NuevosTCA
		
		/*-----------------------INSERTAR NTF-------------------*/
		INSERT INTO @NuevosTF
					(
					[Codigo]
					, [CodigoCT]
					, [FechaVencimiento]
					, [CVV]
					)
		SELECT 
			T.Item.value('@Codigo', 'VARCHAR(128)'),
			T.Item.value('@TCAsociada', 'VARCHAR(128)'),
			T.Item.value('@FechaVencimiento', 'VARCHAR(128)'),
			T.Item.value('@CCV', 'INT')
		FROM @Datos.nodes('/root/fechaOperacion[@Fecha = sql:variable("@FechaItera")]/NTF/NTF') AS T(Item);

		INSERT INTO [dbo].[TarjetaFisica]
					(
					[IdCuentaTarjeta]
					, [Codigo]
					, [AnnoVence]
					, [MesVence]
					, [CVV]
					, [Pin]
					, [FechaEmision]
					, [FechaInvalidacion]
					)
		SELECT
			CT.Id
			, NTF.Codigo
			, CAST(RIGHT(NTF.FechaVencimiento, 4) AS INT)
			, CAST(LEFT(NTF.FechaVencimiento, CHARINDEX('/', NTF.FechaVencimiento) - 1) AS INT)
			, NTF.CVV
			, 0
			, @FechaItera
			, CONVERT(DATE, '1/' + NTF.FechaVencimiento, 103)
		FROM @NuevosTF NTF
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Codigo = NTF.CodigoCT

		DELETE @NuevosTF

		/* #################################### INSERTAR MOVIMIENTOS #########################################*/
		INSERT INTO @NuevosMovimientos
					(
					[Nombre]
					, [TF]
					, [FechaMovimiento]
					, [Monto]
					, [Descripcion]
					, [Referencia]
					)
		SELECT 
			T.Item.value('@Nombre', 'VARCHAR(128)'),
			T.Item.value('@TF', 'VARCHAR(128)'),
			T.Item.value('@FechaMovimiento', 'DATE'),
			T.Item.value('@Monto', 'MONEY'),
			T.Item.value('@Descripcion', 'VARCHAR(128)'),
			T.Item.value('@Referencia', 'VARCHAR(128)')
		FROM @Datos.nodes('/root/fechaOperacion[@Fecha = sql:variable("@FechaItera")]/Movimiento/Movimiento') AS T(Item);

		/* ----------------------INSERCION EN @MovimientosEspejo POR MOVIMIENTOS DEL XML-----------------------*/

		DECLARE @IdTarjetaFisica INT;
		DECLARE @IdCuentaTarjeta INT;
		DECLARE @IdTipoMovimiento INT;
		DECLARE @Descripcion VARCHAR(128);
		DECLARE @Monto MONEY;
		DECLARE @Referencia VARCHAR(128);
		DECLARE @TF VARCHAR(128);
		DECLARE @Nombre VARCHAR(128);
		DECLARE @NuevaTF VARCHAR(128);
		DECLARE @NuevosMovimientosCursor CURSOR;

		SET @NuevosMovimientosCursor = CURSOR FOR
		SELECT NM.TF
			, NM.Nombre
			, NM.Descripcion
			, NM.Monto
			, NM.Referencia
		FROM @NuevosMovimientos NM

		OPEN @NuevosMovimientosCursor;

		FETCH NEXT FROM @NuevosMovimientosCursor INTO @TF, @Nombre, @Descripcion, @Monto, @Referencia;

		WHILE @@FETCH_STATUS = 0
		BEGIN

			SELECT @IdTarjetaFisica = TF.Id
			FROM [dbo].[TarjetaFisica] TF
			WHERE (TF.Codigo = @TF);

			SET @IdCuentaTarjeta = (SELECT TF.IdCuentaTarjeta
									FROM [dbo].[TarjetaFisica] TF
									WHERE (@IdTarjetaFisica = TF.Id))

			SELECT @IdTipoMovimiento = TM.Id
			FROM [dbo].[TipoMovimiento] TM
			WHERE (TM.Nombre = @Nombre);
				

			INSERT INTO @MovimientosEspejo
					(
					[IdCuentaTarjeta]
					, [IdEstadoCuenta]
					, [IdTarjetaFisica]
					, [IdTipoMovimiento]
					, [Descripcion]
					, [Fecha]
					, [Monto]
					, [Referencia]
					, [NuevoSaldo]
					)
			SELECT
				@IdCuentaTarjeta
				, EC.Id
				, @IdTarjetaFisica
				, @IdTipoMovimiento
				, @Descripcion
				, @FechaItera
				, @Monto
				, @Referencia
				, 0
			FROM [dbo].[EstadoCuenta] EC
			WHERE (EC.IdCuentaTarjetaMaestra = @IdCuentaTarjeta)
			AND ((SELECT CT.EsMaestra
					FROM [dbo].[CuentaTarjeta] CT
					WHERE (CT.Id = @IdCuentaTarjeta)) = 1)
				

			INSERT INTO @MovimientosEspejo
					(
					[IdCuentaTarjeta]
					, [IdSubestadoCuenta]
					, [IdTarjetaFisica]
					, [IdTipoMovimiento]
					, [Descripcion]
					, [Fecha]
					, [Monto]
					, [Referencia]
					, [NuevoSaldo]
					)
			SELECT
				@IdCuentaTarjeta
				, SC.Id
				, @IdTarjetaFisica
				, @IdTipoMovimiento
				, @Descripcion
				, @FechaItera
				, @Monto
				, @Referencia
				, 0
			FROM [dbo].[SubestadoCuenta] SC
			WHERE (SC.IdCuentaTarjetaAdicional = @IdCuentaTarjeta)
			AND ((SELECT CT.EsMaestra
					FROM [dbo].[CuentaTarjeta] CT
					WHERE (CT.Id = @IdCuentaTarjeta)) = 0)

			FETCH NEXT FROM @NuevosMovimientosCursor INTO @TF, @Nombre, @Descripcion, @Monto, @Referencia;

		END;

		CLOSE @NuevosMovimientosCursor;
		DEALLOCATE @NuevosMovimientosCursor;

		/* ----------------------INSERCION EN @MovimientosEspejo POR RENOVACION de CTM-----------------------*/
		DECLARE @IdMovType INT;
		DECLARE @IdTipoRN INT;
		SET @IdMovType = (SELECT TM.Id
								FROM [dbo].[TipoMovimiento] TM
								WHERE TM.Nombre = 'Renovacion de TF')
		SET @IdTipoRN = (SELECT TRN.Id
							FROM [dbo].[TipoReglaNegocio] TRN
							WHERE TRN.Nombre = 'Monto Monetario')

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CT.Id
			, EC.Id
			, TF.Id
			, @IdMovType
			, 'Cargo por renovacion de CTM'
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjeta] CT 
			INNER JOIN [dbo].[TarjetaFisica] TF ON CT.Id = TF.IdCuentaTarjeta
			INNER JOIN [dbo].[EstadoCuenta] EC ON EC.IdCuentaTarjetaMaestra = CT.Id
			INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
			INNER JOIN [dbo].[TCTxRN] TCTxRN ON (TCTxRN.IdReglaNegocio = RN.Id)
				AND (TCTxRN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta)
			INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRN.Id
		WHERE((@FechaItera >= TF.FechaInvalidacion) 
			AND (CT.EsMaestra = 1) 
			AND (RN.IdTipoRN = @IdTipoRN)
			AND (RN.Nombre = 'Cargo renovacion de TF de CTM'))

		
		/* -------------------------INSERCION EN @MovimientosEspejo POR RENOVACION de CTA----------------------- */
		SET @IdMovType = (SELECT TM.Id
								FROM [dbo].[TipoMovimiento] TM
								WHERE TM.Nombre = 'Renovacion de TF')
		SET @IdTipoRN = (SELECT TRN.Id
							FROM [dbo].[TipoReglaNegocio] TRN
							WHERE TRN.Nombre = 'Monto Monetario')

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdSubestadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CT.Id
			, SC.Id
			, TF.Id
			, @IdMovType
			, 'Cargo por renovacion de CTA'
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjeta] CT
			INNER JOIN [dbo].[TarjetaFisica] TF ON CT.Id = TF.IdCuentaTarjeta
			INNER JOIN [dbo].[SubestadoCuenta] SC ON SC.IdCuentaTarjetaAdicional = CT.Id
			INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.IdCuentaTarjeta = CT.Id
			INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
			INNER JOIN [dbo].[TCTxRN] TCTxRN ON (TCTxRN.IdReglaNegocio = RN.Id)
				AND (TCTxRN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta)
			INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRN.Id
		WHERE((@FechaItera >= TF.FechaInvalidacion)
			AND (CT.EsMaestra = 0)
			AND (RN.IdTipoRN = @IdTipoRN)
			AND (RN.Nombre = 'Cargo renovacion de TF de CTA'))


		/* ---------------------------INSERCION EN @MovimientoIntCorr--------------------------- */
		INSERT INTO @MovimientoIntCorr
				(
				[IdCuentaTarjetaMaestra]
				, [IdTipoMovimientoIntCorr]
				, [Fecha]
				, [Monto]
				, [NuevoIntAcumCorriente]
				)
		SELECT 
			CTM.IdCuentaTarjeta
			, (SELECT TMIC.Id 
				FROM [dbo].[TipoMovimientoIntCorriente] TMIC
				WHERE TMIC.Nombre = 'Credito Interes Diario')
			, @FechaItera
			, CTM.saldo * RNTasa.valor/100/30
			, ISNULL((SELECT MAX(NuevoIntAcumCorriente) 
						FROM @MovimientoIntCorr), 0) + (CTM.saldo * RNTasa.valor/100/30)
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNTasa] RNTasa ON RNTasa.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Tasa de interes corriente')


		/* ---------------------------INSERCION EN @MovimientoIntMor--------------------------- */
		INSERT INTO @MovimientoIntMor
				(
				[IdCuentaTarjetaMaestra]
				, [IdTipoMovimientoIntMor]
				, [Fecha]
				, [Monto]
				, [NuevoIntAcumMoratorio]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, (SELECT TMIM.Id 
				FROM [dbo].[TipoMovimientoIntMoratorio] TMIM 
				WHERE TMIM.Nombre = 'Debito por Redencion')
			, @FechaItera
			, (EC.PagoMinimo - EC.SumaPagosMes)/RNTasa.valor/100/30
			, ISNULL((SELECT MAX(MIM.NuevoIntAcumMoratorio) 
						FROM @MovimientoIntMor MIM), 0) + (EC.PagoMinimo - EC.SumaPagosMes)/RNTasa.valor/100/30
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN [dbo].[EstadoCuenta] EC ON EC.Id = CTM.LastId
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNTasa] RNTasa ON RNTasa.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Intereses Moratorios Pago no Realizado') 
			AND (EC.SumaPagosMes < EC.PagoMinimo) 
			AND (CTM.Saldo > 0)

		/* ---------------------------INSERCION EN @MovimientoSospechoso--------------------------- */
			
		INSERT INTO @TFRobadasPerdidas
				(
				[IdNuevoMovimiento]
				, [Codigo]
				, [Nombre]
				)
		SELECT 
			NM.Id
			, NM.TF
			, NM.Nombre
		FROM @NuevosMovimientos NM
		WHERE (NM.Nombre = 'Recuperacion por Robo') OR (NM.Nombre = 'Recuperacion por Perdida')

		INSERT INTO @TarjetasSospechosas
				(
				[IdNuevoMovimiento]
				, [Codigo]
				, [Nombre]
				)
		SELECT 
			0
			, TF.Codigo
			, 'Fecha Vencimiento'
		FROM [dbo].[TarjetaFisica] TF
		WHERE (@FechaItera >= TF.FechaInvalidacion) AND NOT EXISTS(SELECT 1
																	FROM @TarjetasSospechosas TS
																	WHERE TS.Codigo = TF.Codigo)

		INSERT INTO @TarjetasSospechosas
				(
				[IdNuevoMovimiento]
				, [Codigo]
				, [Nombre]
				)
		SELECT
			TFRobPer.IdNuevoMovimiento
			, TFRobPer.Codigo
			, TFRobPer.Nombre
		FROM @TFRobadasPerdidas TFRobPer
		WHERE NOT EXISTS(
				SELECT 1
				FROM @TarjetasSospechosas TS
				WHERE TS.Codigo = TFRobPer.Codigo)

		INSERT INTO @MovimientoSospechoso
				(
				[IdCuentaTarjetaMaestra]
				, [IdTarjetaFisica]
				, [Fecha]
				, [Monto]
				, [Descripcion]
				, [Referencia]
				)
		SELECT
			CT.Id
			, TF.Id
			, @FechaItera
			, NM.Monto
			, NM.Descripcion
			, NM.Referencia
		FROM @NuevosMovimientos NM
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.Codigo = NM.TF
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = TF.IdCuentaTarjeta
		WHERE (CT.EsMaestra = 1) 
				AND (EXISTS (SELECT 1 
							FROM @TarjetasSospechosas TS
							WHERE (TRIM(TS.Codigo) = TRIM(NM.TF))))
				AND (NM.Id > (SELECT TS.IdNuevoMovimiento
								FROM @TarjetasSospechosas TS
								WHERE NM.TF = TS.Codigo))
		INSERT INTO @MovimientoSospechoso
				(
				[IdCuentaTarjetaMaestra]
				, [IdTarjetaFisica]
				, [Fecha]
				, [Monto]
				, [Descripcion]
				, [Referencia]
				)
		SELECT
			CTA.IdCuentaTarjetaMaestra
			, TF.Id
			, @FechaItera
			, NM.Monto
			, NM.Descripcion
			, NM.Referencia
		FROM @NuevosMovimientos NM
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.Codigo = NM.TF
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = TF.IdCuentaTarjeta
		INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.IdCuentaTarjeta = CT.Id
		WHERE (CT.EsMaestra = 0) 
				AND (EXISTS (SELECT 1 
							FROM @TarjetasSospechosas TS
							WHERE (TRIM(TS.Codigo) = TRIM(NM.TF))))
				AND (NM.Id > (SELECT TS.IdNuevoMovimiento
								FROM @TarjetasSospechosas TS
								WHERE NM.TF = TS.Codigo))
		
		/* ---------------------------------PROCESO DE CIERRE DE ESTADOS DE CUENTA--------------------------------- */

		INSERT INTO @CierraEC
				(
				[IdCTM]
				)
		SELECT 
			CT.Id
		FROM [dbo].[CuentaTarjeta] CT
		WHERE (dbo.FNCierraEC(CT.FechaCreacion, @FechaItera) = 1) 
				AND (CT.EsMaestra = 1)

		/* ---------------------------------PROCESO DE CIERRE DE SUB-ESTADOS DE CUENTA--------------------------------- */
		
		INSERT INTO @CierraSubEC
				(
				[IdCTA]
				)
		SELECT
			CT.Id
		FROM [dbo].[CuentaTarjeta] CT
		WHERE (dbo.FNCierraEC(CT.FechaCreacion, @FechaItera) = 1) 
				AND (CT.EsMaestra = 0)

		/* -------------------INSERCION EN ESPEJO MOVIMIENTOS POR CARGOS SERVICIO DE CUENTAS CTM QUE CIERRAN------------------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, EC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE TM.Nombre = 'Cargos por Servicio')
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[EstadoCuenta] EC ON EC.Id = CTM.LastId
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Cargos Servicio Mensual CTM')


		/* -------------------INSERCION EN ESPEJO MOVIMIENTOS POR CARGOS SERVICIO DE CUENTAS CTA QUE CIERRAN------------------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdSubestadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CT.Id
			, SEC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE TM.Nombre = 'Cargos por Servicio')
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjeta] CT
		INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CT.Id
		INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.IdCuentaTarjeta = CT.Id
		INNER JOIN [dbo].[SubestadoCuenta] SEC ON SEC.Id = CTA.LastSECId
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CT.Id
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
				AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Cargos Servicio Mensual CTA')
			AND (CT.EsMaestra = 0)

		/* -----------INSERCION EN ESPEJO MOVIMIENTOS POR EXCESO OPERACIONES X VENTANA EN CUENTAS CTM QUE CIERRAN--------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, EC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso Ventana'))
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[EstadoCuenta] EC ON EC.Id = CTM.LastId
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CT.Id
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNQOperaciones] TCTxRNQOp ON TCTxRNQOp.IdTCTxRN =  TCTxRNeg.Id
		INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Multa exceso de operaciones Ventanilla')
				AND (CT.EsMaestra = 1)
				AND (EC.QOperacionesVentana > TCTxRNQOp.Valor)


		/* -----------INSERCION EN ESPEJO MOVIMIENTOS POR EXCESO OPERACIONES X VENTANA EN CUENTAS CTA QUE CIERRAN--------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdSubestadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CT.Id
			, SEC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso Ventana'))
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
		FROM [dbo].[CuentaTarjeta] CT
		INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CT.Id
		INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.IdCuentaTarjeta = CT.Id
		INNER JOIN [dbo].[SubestadoCuenta] SEC ON SEC.Id = CTA.LastSECId
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CT.Id
		INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
		INNER JOIN [dbo].[TCTxRNQOperaciones] TCTxRNQOp ON TCTxRNQOp.IdTCTxRN = TCTxRNeg.Id
		INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
		WHERE (RN.Nombre = 'Multa exceso de operaciones Ventanilla')
				AND (CT.EsMaestra = 0)
				AND (SEC.QOperacionesVentana > TCTxRNQOp.Valor)

		/* -----------INSERCION EN ESPEJO MOVIMIENTOS POR EXCESO OPERACIONES X ATM EN CUENTAS CTM QUE CIERRAN--------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta]
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, EC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso ATM'))
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
        FROM [CuentaTarjetaMaestra] CTM
        INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
        INNER JOIN [dbo].[EstadoCuenta] EC ON EC.id = CTM.LastId
        INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.id = CTM.IdCuentaTarjeta
        INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CT.Id
        INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRNQOperaciones] TCTxRNQOp ON TCTxRNQOp.IdTCTxRN =  TCTxRNeg.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
        WHERE (RN.Nombre = 'Multa exceso de operaciones ATM')
				AND (CT.EsMaestra = 1)
				AND (EC.QOperacionesATM > TCTxRNQOp.Valor)
		

		/* -----------INSERCION EN ESPEJO MOVIMIENTOS POR EXCESO OPERACIONES X ATM EN CUENTAS CTA QUE CIERRAN--------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdSubestadoCuenta] --Se hace un cambio aqui 
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CT.Id
			, SEC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso ATM'))
			, RN.Nombre
			, @FechaItera
			, TCTxRNMM.valor
			, ''
			, 0
        FROM [dbo].[CuentaTarjeta] CT 
        INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CT.Id 
		INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.IdCuentaTarjeta = CT.Id
        INNER JOIN [dbo].[SubestadoCuenta] SEC ON SEC.Id = CTA.LastSECId
        INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CT.Id
        INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
				AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRNQOperaciones] TCTxRNQOp ON TCTxRNQOp.IdTCTxRN =  TCTxRNeg.Id
					AND TCTxRNeg.IdTipoCuentaTarjeta = RN.IdTipoCuentaTarjeta
        INNER JOIN [dbo].[TCTxRNMontoMonetario] TCTxRNMM ON TCTxRNMM.IdTCTxRN = TCTxRNeg.Id
        WHERE (RN.Nombre = 'Multa exceso de operaciones ATM')
                AND (CT.EsMaestra = 0)
                AND (SEC.QOperacionesVentana > TCTxRNQOp.Valor)
		
		/* -------------INSERCION EN ESPEJO MOVIMIENTOS DE INTERESES CORRIENTES MENSUALES EN CTM QUE CIERRAN------------- */

		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta] 
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, EC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Intereses Corrientes sobre Saldo'))
			, 'Tasa de interes corriente'
			, @FechaItera
			, CTM.InteresAcumuladoCorriente + EC.IntCorrAcum--#############################################
			, ''
			, 0
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[EstadoCuenta] EC ON EC.Id = CTM.LastId
		INNER JOIN @MovimientoIntCorr MovIntCorr ON MovIntCorr.IdCuentaTarjetaMaestra = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CTM.IdCuentaTarjeta
		
		/* -------------INSERCION EN ESPEJO MOVIMIENTOS DE INTERESES MORATORIOS MENSUALES EN CTM QUE CIERRAN------------- */
		
		INSERT INTO @MovimientosEspejo
				(
				[IdCuentaTarjeta]
				, [IdEstadoCuenta] 
				, [IdTarjetaFisica]
				, [IdTipoMovimiento]
				, [Descripcion]
				, [Fecha]
				, [Monto]
				, [Referencia]
				, [NuevoSaldo]
				)
		SELECT
			CTM.IdCuentaTarjeta
			, EC.Id
			, TF.Id
			, (SELECT TM.Id
				FROM [dbo].[TipoMovimiento] TM
				WHERE (TM.Nombre = 'Intereses Moratorios Pago no Realizado'))
			, 'intereses moratorios'
			, @FechaItera
			, CTM.InteresAcumuladoMoratorio + EC.IntMoratorio--#############################################
			, ''
			, 0
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
		INNER JOIN @MovimientoIntMor MovIntMor ON MovIntMor.IdCuentaTarjetaMaestra = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = CTM.IdCuentaTarjeta
		INNER JOIN [dbo].[EstadoCuenta] EC ON EC.Id = CTM.LastId
		INNER JOIN [dbo].[TarjetaFisica] TF ON TF.IdCuentaTarjeta = CTM.IdCuentaTarjeta

		/* ------------- INSERCION EN ESPEJO MOVIMIENTOS DE COMPENSACION DE INTERESES CORRIENTES ------------- */
		/* -------------------------- EN CTM QUE CIERRAN Y PAGARON SALDO COMPLETO ------------------------------*/


		/* ---------------------------- PROCESAR CONTADORES DEL ESTADO DE CUENTA ---------------------------------*/
		DECLARE @IdRetiroATM INT
				, @IdPagoATM INT
				, @IdRetiroVentana INT
				, @IdPagoVentana INT
				, @IdPagoLinea INT
				, @IdCompra INT
				, @IdRecuperacionPerdida INT
				, @IdRecuperacionRobo INT
				, @IdRenovacionTF INT
				, @IdCargosXServicio INT
				, @IdMultaExcesoATM INT
				, @IdMultaExcesoVentana INT
				, @IdInteresCorriente INT
				, @IdInteresMoratorio INT

		SET @IdRetiroATM = (SELECT TM.Id
							FROM [dbo].[TipoMovimiento] TM
							WHERE (TM.Nombre = 'Retiro en ATM'))
		SET @IdPagoATM = (SELECT TM.Id
							FROM [dbo].[TipoMovimiento] TM
							WHERE (TM.Nombre = 'Pago en ATM'))
		SET @IdRetiroVentana = (SELECT TM.Id
								FROM [dbo].[TipoMovimiento] TM
								WHERE (TM.Nombre = 'Retiro en Ventana'))
		SET @IdPagoVentana = (SELECT TM.Id
								FROM [dbo].[TipoMovimiento] TM
								WHERE (TM.Nombre = 'Pago en Ventana'))
		SET @IdPagoLinea = (SELECT TM.Id
							FROM [dbo].[TipoMovimiento] TM
							WHERE (TM.Nombre = 'Pago en Linea'))
		SET @IdCompra = (SELECT TM.Id
							FROM [dbo].[TipoMovimiento] TM
							WHERE (TM.Nombre = 'Compra'))
		SET @IdRecuperacionPerdida = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Recuperacion por Perdida'))
		SET @IdRecuperacionRobo = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Recuperacion por Robo'))
		SET @IdRenovacionTF = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Renovacion de TF'))
		SET @IdCargosXServicio = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Cargos por Servicio'))
		SET @IdMultaExcesoATM = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso ATM'))
		SET @IdMultaExcesoVentana = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Cargos por Multa Exceso Uso Ventana'))
		SET @IdInteresCorriente = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Intereses Corrientes sobre Saldo'))
		SET @IdInteresMoratorio = (SELECT TM.Id
										FROM [dbo].[TipoMovimiento] TM
										WHERE (TM.Nombre = 'Intereses Moratorios Pago no Realizado'))

		INSERT INTO @ContadoresEC
				(
				[IdCuentaTarjetaMaestra]
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
			CTM.IdCuentaTarjeta
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM) 
							OR (ME.IdTipoMovimiento = @IdPagoATM) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroVentana)
							OR (ME.IdTipoMovimiento = @IdPagoVentana) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroVentana) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroVentana) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea)
							OR (ME.IdTipoMovimiento = @IdCargosXServicio)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoATM)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoVentana) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea)
							OR (ME.IdTipoMovimiento = @IdCargosXServicio)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoATM)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoVentana) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra)
							OR (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroVentana)
							OR (ME.IdTipoMovimiento = @IdRecuperacionPerdida)
							OR (ME.IdTipoMovimiento = @IdRecuperacionRobo)
							OR (ME.IdTipoMovimiento = @IdRenovacionTF)
							OR (ME.IdTipoMovimiento = @IdInteresCorriente)
							OR (ME.IdTipoMovimiento = @IdInteresMoratorio) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra)
							OR (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroVentana)
							OR (ME.IdTipoMovimiento = @IdRecuperacionPerdida)
							OR (ME.IdTipoMovimiento = @IdRecuperacionRobo)
							OR (ME.IdTipoMovimiento = @IdRenovacionTF)
							OR (ME.IdTipoMovimiento = @IdInteresCorriente)
							OR (ME.IdTipoMovimiento = @IdInteresMoratorio) THEN 1 ELSE 0 END)
		FROM [dbo].[CuentaTarjetaMaestra] CTM
		INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
		INNER JOIN @MovimientosEspejo ME ON ME.IdCuentaTarjeta = CTM.IdCuentaTarjeta
		GROUP BY CTM.IdCuentaTarjeta

		/* ---------------------------- PROCESAR CONTADORES DEL SUBESTADO DE CUENTA ---------------------------------*/

		INSERT INTO @ContadoresSubEC
				(
				[IdCTA]
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
			CTA.IdCuentaTarjeta
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdPagoATM) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroVentana)
							OR (ME.IdTipoMovimiento = @IdPagoVentana) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroATM) THEN 1 ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroATM) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdPagoATM)
							OR (ME.IdTipoMovimiento = @IdPagoVentana)
							OR (ME.IdTipoMovimiento = @IdPagoLinea)
							OR (ME.IdTipoMovimiento = @IdCargosXServicio)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoATM)
							OR (ME.IdTipoMovimiento = @IdMultaExcesoVentana) THEN ME.Monto ELSE 0 END)
			, SUM(CASE WHEN (ME.IdTipoMovimiento = @IdCompra)
							OR (ME.IdTipoMovimiento = @IdRetiroATM)
							OR (ME.IdTipoMovimiento = @IdRetiroVentana)
							OR (ME.IdTipoMovimiento = @IdRecuperacionPerdida)
							OR (ME.IdTipoMovimiento = @IdRecuperacionRobo)
							OR (ME.IdTipoMovimiento = @IdRenovacionTF)
							OR (ME.IdTipoMovimiento = @IdInteresCorriente)
							OR (ME.IdTipoMovimiento = @IdInteresMoratorio) THEN ME.Monto ELSE 0 END)
		FROM [dbo].[CuentaTarjetaAdicional] CTA
		INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CTA.IdCuentaTarjeta
		INNER JOIN @MovimientosEspejo ME ON ME.IdCuentaTarjeta = CTA.IdCuentaTarjeta
		GROUP BY CTA.IdCuentaTarjeta

		/* ---------------------------------- ITERAR POR CUENTAS CTM -------------------------------------*/
		INSERT INTO @CTMItera
				(
				[IdCuentaTarjeta]
				)
		SELECT CT.Id
		FROM [dbo].[CuentaTarjeta] CT
		ORDER BY CT.Id ASC;

		DECLARE @IdCTMActual INT
				, @IdCTMMax INT;

		SELECT @IdCTMActual = MIN(CT.Id)
		FROM [dbo].[CuentaTarjeta] CT

		SELECT @IdCTMMax = MAX(CT.Id)
		FROM [dbo].[CuentaTarjeta] CT

		WHILE (@IdCTMActual <= @IdCTMMax)
		BEGIN
			
			IF (EXISTS(SELECT ME.IdCuentaTarjeta 
						FROM @MovimientosEspejo ME 
						WHERE ME.IdCuentaTarjeta = @IdCTMActual))
				OR (EXISTS(SELECT CEC.IdCTM 
							FROM @CierraEC CEC 
							WHERE CEC.IdCTM = @IdCTMActual)
				OR (EXISTS(SELECT CSEC.IdCTA
							FROM @CierraSubEC CSEC
							WHERE CSEC.IdCTA = @IdCTMActual)))
			BEGIN

				INSERT INTO @MovimientosCTMActual
						(
						[IdCuentaTarjeta]
						, [IdEstadoCuenta]
						, [IdTarjetaFisica]
						, [IdTipoMovimiento]
						, [Descripcion]
						, [Fecha]
						, [Monto]
						, [Referencia]
						, [NuevoSaldo]
						)
				SELECT
					ME.IdCuentaTarjeta
					, ME.IdEstadoCuenta
					, ME.IdTarjetaFisica
					, ME.IdTipoMovimiento
					, ME.Descripcion
					, ME.Fecha
					, ME.Monto
					, ME.Referencia
					, ME.NuevoSaldo
				FROM @MovimientosEspejo ME
				INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = ME.IdCuentaTarjeta
				WHERE (ME.IdCuentaTarjeta = @IdCTMActual)
						AND (CT.EsMaestra = 1)

				INSERT INTO @MovimientosCTMActual
						(
						[IdCuentaTarjeta]
						, [IdSubestadoCuenta]
						, [IdTarjetaFisica]
						, [IdTipoMovimiento]
						, [Descripcion]
						, [Fecha]
						, [Monto]
						, [Referencia]
						, [NuevoSaldo]
						)
				SELECT
					ME.IdCuentaTarjeta
					, ME.IdSubestadoCuenta
					, ME.IdTarjetaFisica
					, ME.IdTipoMovimiento
					, ME.Descripcion
					, ME.Fecha
					, ME.Monto
					, ME.Referencia
					, ME.NuevoSaldo
				FROM @MovimientosEspejo ME
				INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = ME.IdCuentaTarjeta
				WHERE (ME.IdCuentaTarjeta = @IdCTMActual)
						AND (CT.EsMaestra = 0)

				--SELECT * FROM @MovimientosCTMActual

				SELECT @SaldoItera = CTM.Saldo
				FROM [dbo].[CuentaTarjetaMaestra] CTM
				WHERE (CTM.IdCuentaTarjeta = @IdCTMActual)
						

				SELECT @InteresCorrienteCTMActual = ISNULL(SUM(MIC.Monto), 0)
				FROM @MovimientoIntCorr MIC
				WHERE (MIC.IdCuentaTarjetaMaestra = @IdCTMActual)

				SELECT @InteresMoratorioCTMActual = ISNULL(SUM(MIM.Monto), 0)
				FROM @MovimientoIntMor MIM
				WHERE (MIM.IdCuentaTarjetaMaestra = @IdCTMActual)

				SELECT @InteresAcumCorr = CTM.InteresAcumuladoCorriente + @InteresCorrienteCTMActual
				FROM [dbo].[CuentaTarjetaMaestra] CTM
				WHERE (CTM.IdCuentaTarjeta = @IdCTMActual)

				SELECT @InteresAcumMor = CTM.InteresAcumuladoMoratorio + @InteresMoratorioCTMActual
				FROM [dbo].[CuentaTarjetaMaestra] CTM
				WHERE (CTM.IdCuentaTarjeta = @IdCTMActual)

				SELECT @TotalCargosXServicio = ISNULL(SUM(ME.Monto), 0)
				FROM @MovimientosEspejo ME
				WHERE (ME.IdTipoMovimiento = @IdCargosXServicio)
						AND (ME.IdCuentaTarjeta = @IdCTMActual)

				SELECT @TotalCargosXMulta = ISNULL(SUM(ME.Monto), 0)
				FROM @MovimientosEspejo ME
				WHERE (ME.IdCuentaTarjeta = @IdCTMActual)
						AND ((ME.IdTipoMovimiento = @IdMultaExcesoATM)
						OR (ME.IdTipoMovimiento = @IdMultaExcesoVentana))

				SET @DiasExtraFechaPagoMinimo = (SELECT TCTxRNQD.Valor
										FROM [dbo].[CuentaTarjeta] CT
										INNER JOIN @CierraEC CEC ON CEC.IdCTM = CT.Id
										INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
										INNER JOIN [dbo].[TCTxRN] TCTxRNeg ON TCTxRNeg.IdReglaNegocio = RN.Id
													AND TCTxRNeg.IdTipoCuentaTarjeta = CT.IdTipoCuentaTarjeta
										INNER JOIN [dbo].[TCTxRNQDias] TCTxRNQD ON TCTxRNQD.IdTCTxRN = TCTxRNeg.Id
										WHERE (CT.Id = @IdCTMActual)
												AND (RN.Nombre = 'Cantidad de dias para pago saldo de contado'))

				DECLARE @LO INT
						, @HI INT

				SELECT @LO = MIN(MCTMA.Id)
				FROM @MovimientosCTMActual MCTMA

				SELECT @HI = MAX(MCTMA.Id)
				FROM @MovimientosCTMActual MCTMA

				BEGIN TRANSACTION TProcesoDiarioCuentas
					
					INSERT INTO [dbo].[MovimientoIntCorriente]
							(
							[IdCuentaTarjetaMaestra]
							, [IdTipoMovimientoIntCorriente]
							, [Fecha]
							, [Monto]
							, [NuevoIntAcumCorriente]
							)
					SELECT 
						MIC.IdCuentaTarjetaMaestra
						, MIC.IdTipoMovimientoIntCorr
						, MIC.Fecha
						, MIC.Monto
						, @InteresAcumCorr
					FROM @MovimientoIntCorr MIC
					WHERE (MIC.IdCuentaTarjetaMaestra = @IdCTMActual)

					INSERT INTO [dbo].[MovimientoIntMoratorio]
							(
							[IdCuentaTarjetaMaestra]
							, [IdTipoMovimientoIntMoratorio]
							, [Fecha]
							, [Monto]
							, [NuevoIntAcumMoratorio]
							)
					SELECT
						MIM.IdCuentaTarjetaMaestra
						, MIM.IdTipoMovimientoIntMor
						, MIM.Fecha
						, MIM.Monto
						, @InteresAcumMor
					FROM @MovimientoIntMor MIM
					WHERE (MIM.IdCuentaTarjetaMaestra = @IdCTMActual)

					INSERT INTO [dbo].[MovimientoSospechoso]
							(
							[IdCuentaTarjetaMaestra]
							, [IdTarjetaFisica]
							, [Fecha]
							, [Monto]
							, [Descripcion]
							, [Referencia]
							)
					SELECT
						MS.IdCuentaTarjetaMaestra
						, MS.IdTarjetaFisica
						, MS.Fecha
						, MS.Monto
						, MS.Descripcion
						, MS.Referencia
					FROM @MovimientoSospechoso MS
					WHERE (MS.IdCuentaTarjetaMaestra = @IdCTMActual)

					WHILE (@LO <= @HI)
					BEGIN

						/* INSERCION DE MOVIMIENTOS DE CTM */
						INSERT INTO [dbo].[Movimiento]
								(
								[IdCuentaTarjeta]
								, [IdEstadoCuenta]
								, [IdTarjetaFisica]
								, [IdTipoMovimiento]
								, [Descripcion]
								, [Fecha]
								, [Monto]
								, [Referencia]
								, [NuevoSaldo]
								)
						SELECT
							MCTMA.IdCuentaTarjeta
							, MCTMA.IdEstadoCuenta
							, MCTMA.IdTarjetaFisica
							, MCTMA.IdTipoMovimiento
							, MCTMA.Descripcion
							, MCTMA.Fecha
							, MCTMA.Monto
							, MCTMA.Referencia
							, @SaldoItera + MCTMA.Monto
						FROM @MovimientosCTMActual MCTMA
						INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = MCTMA.IdCuentaTarjeta
						WHERE (MCTMA.Id = @LO)
								AND (CT.EsMaestra = 1)
						
						/* INSERCION DE MOVIMIENTOS DE CTA */
						INSERT INTO [dbo].[Movimiento]
								(
								[IdCuentaTarjeta]
								, [IdSubestadoCuenta]
								, [IdTarjetaFisica]
								, [IdTipoMovimiento]
								, [Descripcion]
								, [Fecha]
								, [Monto]
								, [Referencia]
								, [NuevoSaldo]
								)
						SELECT
							MCTMA.IdCuentaTarjeta
							, MCTMA.IdSubestadoCuenta
							, MCTMA.IdTarjetaFisica
							, MCTMA.IdTipoMovimiento
							, MCTMA.Descripcion
							, MCTMA.Fecha
							, MCTMA.Monto
							, MCTMA.Referencia
							, @SaldoItera + MCTMA.Monto
						FROM @MovimientosCTMActual MCTMA
						INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = MCTMA.IdCuentaTarjeta
						WHERE (MCTMA.Id = @LO)
								AND (CT.EsMaestra = 0)

						SELECT @SaldoItera = @SaldoItera + MCTMA.Monto
						FROM @MovimientosCTMActual MCTMA
						INNER JOIN [dbo].[CuentaTarjeta] CT ON CT.Id = MCTMA.IdCuentaTarjeta
						WHERE (MCTMA.Id = @LO)
								AND (CT.EsMaestra = 1)

						SET @LO = @LO + 1;

					END;
			
				/* CIERRRE ESTADO CUENTA */
				UPDATE [dbo].[EstadoCuenta]
				SET [Fecha] = @FechaItera
					, [SaldoActual] = @SaldoItera
					, [PagoMinimo] = (@SaldoItera - @TotalCargosXServicio - 
									@TotalCargosXMulta - @InteresAcumMor - @InteresAcumCorr) 
									/ 2
					, [FechaPagoMinimo] = DATEADD(DAY, @DiasExtraFechaPagoMinimo, @FechaItera)
					, [IntCorrAcum] = @InteresAcumCorr
					, [IntMoratorio] = @InteresAcumMor
					, [QOperacionesATM] = EC.QOperacionesATM + ContadoresEC.QOperacionesATM
					, [QOperacionesVentana] = EC.QOperacionesVentana + ContadoresEC.QOperacionesVentana
					, [SumaPagosFechaPagoMinimo] = EC.SumaPagosFechaPagoMinimo +
												(CASE WHEN (@FechaItera <= DATEADD(DAY, @DiasExtraFechaPagoMinimo, @FechaItera)) 
												THEN ContadoresEC.SumaPagosMes ELSE 0 END)
					, [SumaPagosMes] = EC.SumaPagosMes + ContadoresEC.SumaPagosMes
					, [QPagosMes] = EC.QPagosMes + ContadoresEC.QPagosMes
					, [SumaCompras] = EC.SumaCompras + ContadoresEC.SumaCompras
					, [QCompras] = EC.QCompras + ContadoresEC.QCompras
					, [SumaRetiros] = EC.SumaRetiros + ContadoresEC.SumaRetiros
					, [QRetiros] = EC.QRetiros + ContadoresEC.QRetiros
					, [SumaCreditos] = EC.SumaCreditos + ContadoresEC.SumaCreditos
					, [QCreditos] = EC.QCreditos + ContadoresEC.QCreditos
					, [SumaDebitos] = EC.SumaDebitos + ContadoresEC.SumaDebitos
					, [QDebitos] = EC.QDebitos + ContadoresEC.QDebitos
				FROM [dbo].[EstadoCuenta] EC
				INNER JOIN @CierraEC CEC ON CEC.IdCTM = EC.IdCuentaTarjetaMaestra
				INNER JOIN @ContadoresEC ContadoresEC ON ContadoresEC.IdCuentaTarjetaMaestra = EC.IdCuentaTarjetaMaestra
				INNER JOIN [CuentaTarjetaMaestra] CTM ON CTM.LastId = EC.Id
				WHERE (EC.IdCuentaTarjetaMaestra = @IdCTMActual)


				/* CIERRE SUB-ESTADO CUENTA */
				UPDATE [dbo].[SubestadoCuenta]
				SET [Fecha] = @FechaItera
					, [QOperacionesATM] = SEC.QOperacionesATM + ContadoresSEC.QOperacionesATM
					, [QOperacionesVentana] = SEC.QOperacionesVentana + ContadoresSEC.QOperacionesVentana
					, [QCompras] = SEC.QCompras + ContadoresSEC.QCompras
					, [SumaCompras] = SEC.SumaCompras + ContadoresSEC.SumaCompras
					, [Qretiros] = SEC.QRetiros + ContadoresSEC.QRetiros
					, [SumaRetiros] = SEC.SumaRetiros + ContadoresSEC.SumaRetiros
					, [SumaCreditos] = SEC.SumaCreditos + ContadoresSEC.SumaCreditos
					, [SumaDebitos] = SEC.SumaDebitos + ContadoresSEC.SumaDebitos
				FROM [dbo].[SubestadoCuenta] SEC
				INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = SEC.IdCuentaTarjetaAdicional
				INNER JOIN @ContadoresSubEC ContadoresSEC ON ContadoresSEC.IdCTA = SEC.IdCuentaTarjetaAdicional
				INNER JOIN [dbo].[CuentaTarjetaAdicional] CTA ON CTA.LastSECId = SEC.Id
				WHERE (SEC.IdCuentaTarjetaAdicional = @IdCTMActual)

				
				/* APERTURA NUEVO ESTADO CUENTA */
				INSERT INTO [dbo].[EstadoCuenta]
						(
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
					CTM.IdCuentaTarjeta
					, @FechaItera
					, @SaldoItera
					, (@SaldoItera - @TotalCargosXServicio - 
									@TotalCargosXMulta - @InteresAcumMor - @InteresAcumCorr) 
									/ 2
					, @FechaItera -- Este campo se actualiza correctamente en el UPDATE de arriba
					, @InteresAcumCorr
					, @InteresAcumMor
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
				FROM [dbo].[CuentaTarjetaMaestra] CTM
				INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
				INNER JOIN @ContadoresEC ContadoresEC ON ContadoresEC.IdCuentaTarjetaMaestra = CTM.IdCuentaTarjeta
				WHERE (CTM.IdCuentaTarjeta = @IdCTMActual)

				SET @LastIdEC = SCOPE_IDENTITY();

				UPDATE [dbo].[CuentaTarjetaMaestra]
				SET [Saldo] = @SaldoItera
					, [InteresAcumuladoCorriente] = @InteresAcumCorr
					, [InteresAcumuladoMoratorio] = @InteresAcumMor
					, [LastId] = @LastIdEC
				FROM [dbo].[CuentaTarjetaMaestra] CTM
				INNER JOIN @CierraEC CEC ON CEC.IdCTM = CTM.IdCuentaTarjeta
				WHERE (CTM.IdCuentaTarjeta = @IdCTMActual)

				/* APERTURA DE UN NUEVO SUB-ESTADO CUENTA */
				INSERT INTO [dbo].[SubestadoCuenta]
						(
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
					CTA.IdCuentaTarjeta
					, @FechaItera
					, 0
					, 0
					, 0
					, 0
					, 0
					, 0
					, 0
					, 0
				FROM [dbo].[CuentaTarjetaAdicional] CTA
				INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CTA.IdCuentaTarjeta
				WHERE (CTA.IdCuentaTarjeta = @IdCTMActual)

				SET @LastIdSEC = SCOPE_IDENTITY();

				UPDATE [dbo].[CuentaTarjetaAdicional]
				SET [LastSECId] = @LastIdSEC
				FROM [dbo].[CuentaTarjetaAdicional] CTA
				INNER JOIN @CierraSubEC CSEC ON CSEC.IdCTA = CTA.IdCuentaTarjeta
				WHERE (CTA.IdCuentaTarjeta = @IdCTMActual)

				COMMIT TRANSACTION TProcesoDiarioCuentas
			END;

			DELETE @MovimientosCTMActual

			SELECT @IdCTMActual = MIN(CTMI.IdCuentaTarjeta)
			FROM @CTMItera CTMI
			WHERE CTMI.IdCuentaTarjeta > @IdCTMActual
		END;

		DELETE @CierraEC
		DELETE @CierraSubEC
		DELETE @ContadoresEC
		DELETE @ContadoresSubEC
		--DELETE @MovimientosEspejo
		DELETE @MovimientoSospechoso
		DELETE @MovimientoIntCorr
		DELETE @MovimientoIntMor
		DELETE @NuevosMovimientos
		DELETE @CTMItera

		--SELECT * FROM @CierraEC
		--SELECT * FROM @CierraSubEC
		--SELECT * FROM @MovimientosEspejo
		--SELECT * FROM @ContadoresEC
		--SELECT * FROM @ContadoresSubEC
		--SELECT * FROM @MovimientoIntCorr
		--SELECT * FROM @MovimientoIntMor
		--SELECT * FROM @TarjetasSospechosas
		--SELECT * FROM @MovimientoSospechoso

		SELECT @FechaItera = MIN(F.Fecha)
		FROM @Fechas F
		WHERE F.Fecha > @FechaItera;
	END;

	EXEC sp_xml_removedocument @hdoc/*Remueve el documento XML de la memoria*/

END;