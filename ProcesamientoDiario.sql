SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
ALTER PROCEDURE ProcesamientoDiario
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
			, @FechaFinal DATE;
	DECLARE @NuevosTH TABLE (
			Id INT IDENTITY(1, 1)
			, Nombre VARCHAR(128)
			, TipoDocId VARCHAR(128)
			, ValorDocId VARCHAR(128)
			, Username VARCHAR(128)
			, Password VARCHAR(128)
			);
	
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

	SET @FechaFinal = CONVERT(DATE, '2023-05-20')

	WHILE (@FechaItera < @FechaFinal)
	BEGIN

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
		SELECT TOP 6
			TD.Id
			, NTH.Nombre
			, NTH.ValorDocId
			, NTH.Username
			, NTH.Password
		FROM @NuevosTH NTH
		INNER JOIN [dbo].[TipoDocId] TD ON TD.Nombre = NTH.TipoDocId
		ORDER BY NTH.Id DESC;

		/*-----------------------INSERTAR NTCM-------------------*/


		SELECT @FechaItera = MIN(F.Fecha)
		FROM @Fechas F
		WHERE F.Fecha > @FechaItera;
	END;
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
	SELECT * FROM @NuevosTH
END
GO