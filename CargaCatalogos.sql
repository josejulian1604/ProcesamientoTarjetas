USE [Tarea2]
GO
/****** Object:  StoredProcedure [dbo].[CargaCatalogos]    Script Date: 6/3/2023 9:54:48 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER PROCEDURE [dbo].[CargaCatalogos]
	@inRutaXML NVARCHAR(500)
AS
BEGIN
	SET NOCOUNT ON;

	DECLARE @RNTemp TABLE (
		IdTCTM INT
		, IdTipoRN INT
		, Nombre VARCHAR(128)
		, Valor VARCHAR(128)
	);

	DECLARE @TipoRNTable TABLE (
		IdTCTM INT
		, IdTipoRN INT
		, Nombre VARCHAR(128)
		, Valor VARCHAR(128)
	);

	DECLARE @IdRN TABLE (
			Id INT
			);
	DECLARE @IdTCTxRN TABLE (
			Id INT
	);
	
	DECLARE @Datos xml;
	DECLARE @Comando NVARCHAR(500)= 'SELECT @Datos = D FROM OPENROWSET (BULK '  + CHAR(39) + @inRutaXML + CHAR(39) + ', SINGLE_BLOB) AS Datos(D)' -- comando que va a ejecutar el sql dinamico
    DECLARE @Parametros NVARCHAR(500)
	SET @Parametros = N'@Datos xml OUTPUT'

	EXECUTE sp_executesql @Comando, @Parametros, @Datos OUTPUT -- ejecutamos el comando que hicimos dinamicamente

	DECLARE @hdoc int /*Creamos hdoc que va a ser un identificador*/

	EXEC sp_xml_preparedocument @hdoc OUTPUT, @Datos/*Toma el identificador y a la variable con el documento y las asocia*/

	------- Insertar TipoDocId---------
	INSERT INTO [dbo].[TipoDocId]
				(
				[Nombre]
				, [Formato]
				)
	SELECT
		TDI.Nombre
		, TDI.Formato
	FROM OPENXML (@hdoc, '/root/TDI/TDI', 1)
	WITH
		(
		Nombre VARCHAR(128)
		, Formato VARCHAR(128)
		) AS TDI

	--------Insertar TipoCuentaTarjeta------------
	INSERT INTO [dbo].[TipoCuentaTarjeta]
				(
				[Nombre]
				)
	SELECT
		TCT.Nombre
	FROM OPENXML (@hdoc, '/root/TCTM/TCTM', 1)
	WITH
		(
		Nombre VARCHAR(128)
		) AS TCT

	--------Insertar TipoReglaNegocio------------
	INSERT INTO [dbo].[TipoReglaNegocio]
				(
				[Nombre]
				)
	SELECT
		TRN.Nombre
	FROM OPENXML (@hdoc, '/root/TRN/TRN', 1)
	WITH
		(
		Nombre VARCHAR(128)
		) AS TRN

	--------Insertar ReglaNegocio / TCTxRN / Clase Hija------------
	INSERT INTO @RNTemp
				(
				[IdTCTM]
				, [IdTipoRN]
				, [Nombre]
				, [Valor]
				)
	SELECT
		TCT.Id
		, TRN.Id
		, RN.Nombre
		, RN.Valor
	FROM OPENXML (@hdoc, '/root/RN/RN', 1)
	WITH
		(
		Nombre VARCHAR(128)
		, TCTM VARCHAR(128)
		, TipoRN VARCHAR(128)
		, Valor VARCHAR(128)
		) AS RN
		INNER JOIN [dbo].[TipoCuentaTarjeta] TCT ON TCT.Nombre = RN.TCTM
		INNER JOIN [dbo].[TipoReglaNegocio] TRN ON TRN.Nombre = RN.TipoRN;

	INSERT INTO [dbo].[ReglaNegocio]
				(
				[IdTipoCuentaTarjeta]
				, [IdTipoRN]
				, [Nombre]
				)
	OUTPUT inserted.Id INTO @IdRN
	SELECT
		RNTemp.IdTCTM
		, RNTemp.IdTipoRN
		, RNTemp.Nombre
	FROM @RNTemp RNTemp


	INSERT INTO [dbo].[TCTxRN]
				(
				[IdReglaNegocio]
				, [IdTipoCuentaTarjeta]
				)
	OUTPUT inserted.Id INTO @IdTCTxRN
	SELECT
		RN.Id
		, RN.IdTipoCuentaTarjeta
	FROM [dbo].[ReglaNegocio] RN

	-------Insercion Clases Hijas-------

	/*-----------------------------------TCTxRNTasa-----------------------------------*/
	INSERT INTO @TipoRNTable 
				(
				IdTCTM
				, IdTipoRN
				, Nombre
				, Valor
				)
	SELECT 
		RN.IdTCTm
		, RN.IdTipoRN
		, RN.Nombre
		, RN.Valor
	FROM @RNTemp RN
	INNER JOIN [dbo].[TipoReglaNegocio] TRN ON TRN.Id = RN.IdTipoRN
	WHERE TRN.Nombre = 'Porcentaje'

	INSERT INTO [dbo].[TCTxRNTasa]
				(
				[IdTCTxRN]
				, [Valor]
				)
	SELECT
		TipoCuentaxRN.Id
		, TRNTable.Valor
	FROM @TipoRNTable TRNTable
	INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoRN = TRNTable.IdTipoRN
	INNER JOIN [dbo].[TCTxRN] TipoCuentaxRN ON TipoCuentaxRN.IdReglaNegocio = RN.Id
	WHERE (RN.IdTipoCuentaTarjeta = TRNTable.IdTCTM) AND (RN.Nombre = TRNTable.Nombre)

	DELETE @TipoRNTable

	/*-----------------------------------TCTxRNQDias-----------------------------------*/
	INSERT INTO @TipoRNTable 
				(
				IdTCTM
				, IdTipoRN
				, Nombre
				, Valor
				)
	SELECT 
		RN.IdTCTm
		, RN.IdTipoRN
		, RN.Nombre
		, RN.Valor
	FROM @RNTemp RN
	INNER JOIN [dbo].[TipoReglaNegocio] TRN ON TRN.Id = RN.IdTipoRN
	WHERE TRN.Nombre = 'Cantidad de Dias'

	INSERT INTO [dbo].[TCTxRNQDias]
				(
				[IdTCTxRN]
				, [Valor]
				)
	SELECT
		TipoCuentaxRN.Id
		, TRNTable.Valor
	FROM @TipoRNTable TRNTable
	INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoRN = TRNTable.IdTipoRN
	INNER JOIN [dbo].[TCTxRN] TipoCuentaxRN ON TipoCuentaxRN.IdReglaNegocio = RN.Id
	WHERE (RN.IdTipoCuentaTarjeta = TRNTable.IdTCTM) AND (RN.Nombre = TRNTable.Nombre)

	DELETE @TipoRNTable

	/*-----------------------------------TCTxRNQOperaciones-----------------------------------*/
	INSERT INTO @TipoRNTable 
				(
				IdTCTM
				, IdTipoRN
				, Nombre
				, Valor
				)
	SELECT 
		RN.IdTCTm
		, RN.IdTipoRN
		, RN.Nombre
		, RN.Valor
	FROM @RNTemp RN
	INNER JOIN [dbo].[TipoReglaNegocio] TRN ON TRN.Id = RN.IdTipoRN
	WHERE TRN.Nombre = 'Cantidad de Operaciones'

	INSERT INTO [dbo].[TCTxRNQOperaciones]
				(
				[IdTCTxRN]
				, [Valor]
				)
	SELECT
		TipoCuentaxRN.Id
		, TRNTable.Valor
	FROM @TipoRNTable TRNTable
	INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoRN = TRNTable.IdTipoRN
	INNER JOIN [dbo].[TCTxRN] TipoCuentaxRN ON TipoCuentaxRN.IdReglaNegocio = RN.Id
	WHERE (RN.IdTipoCuentaTarjeta = TRNTable.IdTCTM) AND (RN.Nombre = TRNTable.Nombre)

	DELETE @TipoRNTable

	/*-----------------------------------TCTxRNMontoMonetario----------------------------------------*/
	INSERT INTO @TipoRNTable 
				(
				IdTCTM
				, IdTipoRN
				, Nombre
				, Valor
				)
	SELECT 
		RN.IdTCTm
		, RN.IdTipoRN
		, RN.Nombre
		, RN.Valor
	FROM @RNTemp RN
	INNER JOIN [dbo].[TipoReglaNegocio] TRN ON TRN.Id = RN.IdTipoRN
	WHERE TRN.Nombre = 'Monto Monetario'

	INSERT INTO [dbo].[TCTxRNMontoMonetario]
				(
				[IdTCTxRN]
				, [Valor]
				)
	SELECT
		TipoCuentaxRN.Id
		, TRNTable.Valor
	FROM @TipoRNTable TRNTable
	INNER JOIN [dbo].[ReglaNegocio] RN ON RN.IdTipoRN = TRNTable.IdTipoRN
	INNER JOIN [dbo].[TCTxRN] TipoCuentaxRN ON TipoCuentaxRN.IdReglaNegocio = RN.Id
	WHERE (RN.IdTipoCuentaTarjeta = TRNTable.IdTCTM) AND (RN.Nombre = TRNTable.Nombre)
	
	/*-----------------------------------Insertar Motivo Invalidacion Tarjeta-----------------------------------*/
	INSERT INTO [dbo].[MotivoInvalidacion]
				(
				[Nombre]
				)
	SELECT
		MIT.Nombre
	FROM OPENXML (@hdoc, '/root/MIT/MIT', 1)
	WITH
		(
		Nombre VARCHAR(128)
		) AS MIT

	/*-----------------------------------Insertar Tipo Movimiento-----------------------------------*/
	INSERT INTO [dbo].[TipoMovimiento]
				(
				[Nombre]
				, [Accion]
				, [AcumulaATM]
				, [AcumulaVentana]
				)
	SELECT
		TM.Nombre
		, TM.Accion
		, TM.Acumula_Operacion_ATM
		, TM.Acumula_Operacion_Ventana
	FROM OPENXML (@hdoc, '/root/TM/TM', 1)
	WITH
		(
		Nombre VARCHAR(128)
		, Accion VARCHAR(128)
		, Acumula_Operacion_ATM VARCHAR(64)
		, Acumula_Operacion_Ventana VARCHAR(64)
		) AS TM

	/*-----------------------------------Insertar Usuario Administrador-----------------------------------*/
	INSERT INTO [dbo].[UsuarioAdministrador]
				(
				[Username]
				, [Password]
				)
	SELECT 
		UA.Nombre
		, UA.Password
	FROM OPENXML (@hdoc, '/root/UA/Usuario', 1)
	WITH
		(
		Nombre VARCHAR(128)
		, Password VARCHAR(128)
		) AS UA
	EXEC sp_xml_removedocument @hdoc/*Remueve el documento XML de la memoria*/
END;
