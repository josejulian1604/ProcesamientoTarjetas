USE [Tarea2]
GO
/****** Object:  StoredProcedure [dbo].[ProcesamientoDiario]    Script Date: 6/14/2023 12:41:15 PM ******/
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
	--BEGIN TRY
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

	SET @FechaFinal = CONVERT(DATE, '2023-07-08')

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
					)
		SELECT 
			NTCATemp.IdCTA
			, CT.Id
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
			, (SELECT TM.Id 
				FROM [dbo].[TipoMovimiento] TM 
				WHERE TM.Nombre = 'Intereses Corrientes sobre Saldo')
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
			, (SELECT TM.Id 
				FROM [dbo].[TipoMovimiento] TM 
				WHERE TM.Nombre = 'Intereses Moratorios Pago no Realizado')
			, @FechaItera
			, (EC.PagoMinimo - EC.SumaPagosMes)/RNTasa.valor/100/30
			, ISNULL((SELECT MAX(NuevoIntAcumMoratorio) 
						FROM @MovimientoIntMor), 0) + (EC.PagoMinimo - EC.SumaPagosMes)/RNTasa.valor/100/30
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

		DELETE @NuevosMovimientos

		--SELECT * FROM @MovimientosEspejo
		--SELECT * FROM @CierraEC
		SELECT * FROM @TarjetasSospechosas
		--SELECT * FROM @TarjetasSospechosas
		SELECT * FROM @MovimientoSospechoso
		--SELECT * FROM @MovimientosEspejo
		SELECT @FechaItera = MIN(F.Fecha)
		FROM @Fechas F
		WHERE F.Fecha > @FechaItera;
	END;
	--DELETE @TarjetasSospechosas
	/*END TRY
	
	BEGIN CATCH
		INSERT INTO dbo.DBErrors	
		VALUES (
				SUSER_SNAME(),
				ERROR_NUMBER(),
				ERROR_STATE(),
				ERROR_SEVERITY(),
				ERROR_LINE(),
				ERROR_PROCEDURE(),
				ERROR_MESSAGE(),
				GETDATE()
			);

			SET @outResultCode=50005; -- Error en el try-catch
	END CATCH*/
	EXEC sp_xml_removedocument @hdoc/*Remueve el documento XML de la memoria*/
	--SELECT * FROM @NuevosTH

END;