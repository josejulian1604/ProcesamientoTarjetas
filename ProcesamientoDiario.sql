SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		<Author,,Name>
-- Create date: <Create Date,,>
-- Description:	<Description,,>
-- =============================================
CREATE PROCEDURE ProcesamientoDiario
	@inRutaXML NVARCHAR(500)
	, @outResultCode INT OUTPUT
AS
BEGIN
	
	SET NOCOUNT ON;

	DECLARE @Datos xml;
	DECLARE @Comando NVARCHAR(500)= 'SELECT @Datos = D FROM OPENROWSET (BULK '  + CHAR(39) + @inRutaXML + CHAR(39) + ', SINGLE_BLOB) AS Datos(D)' -- comando que va a ejecutar el sql dinamico
    DECLARE @Parametros NVARCHAR(500)
	DECLARE @hdoc int /*Creamos hdoc que va a ser un identificador*/

	SET @Parametros = N'@Datos xml OUTPUT'

	EXECUTE sp_executesql @Comando, @Parametros, @Datos OUTPUT -- ejecutamos el comando que hicimos dinamicamente

	EXEC sp_xml_preparedocument @hdoc OUTPUT, @Datos/*Toma el identificador y a la variable con el documento y las asocia*/

    BEGIN TRY
		DECLARE @Fechas TABLE (
			Fecha DATE
		);
		DECLARE @FechaItera DATE
				, @FechaFinal DATE;
		DECLARE @NuevosTH TABLE (
				Nombre VARCHAR(128)
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
			/*SELECT  CarId as [@CarID],  				Name  AS [CarInfo/Name],  				Make [CarInfo/Make],  				Model [CarInfo/Model],  				Price,  				Type			FROM Car 			FOR XML PATH ('Car'), ROOT('Cars')*/
			/*DECLARE @xmlData XML				SET @xmlData = '				<Root>				  <Person>					<Name>John Doe</Name>					<Age>30</Age>				  </Person>				</Root>'				DECLARE @name VARCHAR(50)				SELECT @name = @xmlData.value('(/Root/Person/Name)[1]', 'varchar(50)')				SELECT @name AS PersonName*/
		SELECT
			OpDate.Fecha
		FROM OPENXML (@hdoc, '/root/fechaOperacion', 1)
		WITH
			(
			Fecha DATE
			) AS OpDate;
	END TRY
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
	END CATCH

	EXEC sp_xml_removedocument @hdoc/*Remueve el documento XML de la memoria*/

END
GO
