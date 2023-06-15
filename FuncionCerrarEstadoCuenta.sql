SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Funcion que retorna 1 si ha pasado 1 mes
-- de lo contrario retorna 0
-- =============================================
ALTER FUNCTION FNCierraEC 
(
	@CTMFechaCreacion DATE
	, @FechaItera DATE
	
)
RETURNS INT
AS
BEGIN
	DECLARE @Result INT;

	IF (DATEADD(MONTH, 1, @CTMFechaCreacion) = @FechaItera) 
		OR (DATEADD(MONTH, 1, DATEADD(DAY, 1, @CTMFechaCreacion)) = @FechaItera)
		OR (DATEADD(MONTH, 1, DATEADD(DAY, -1, @CTMFechaCreacion)) = @FechaItera)
	BEGIN
		SET @Result = 1;
	END;

	ELSE IF (DATEADD(MONTH, 2, @CTMFechaCreacion) = @FechaItera)
			OR (DATEADD(MONTH, 2, DATEADD(DAY, 1, @CTMFechaCreacion)) = @FechaItera)
			OR (DATEADD(MONTH, 2, DATEADD(DAY, -1, @CTMFechaCreacion)) = @FechaItera)
	BEGIN
		SET @Result = 1;
	END;

	ELSE IF (DATEADD(MONTH, 3, @CTMFechaCreacion) = @FechaItera)
			OR (DATEADD(MONTH, 3, DATEADD(DAY, 1, @CTMFechaCreacion)) = @FechaItera)
			OR (DATEADD(MONTH, 3, DATEADD(DAY, -1, @CTMFechaCreacion)) = @FechaItera)
	BEGIN
		SET @Result = 1;
	END;

	ELSE IF (DATEADD(MONTH, 4, @CTMFechaCreacion) = @FechaItera)
			OR (DATEADD(MONTH, 4, DATEADD(DAY, 1, @CTMFechaCreacion)) = @FechaItera)
			OR (DATEADD(MONTH, 4, DATEADD(DAY, -1, @CTMFechaCreacion)) = @FechaItera)
	BEGIN
		SET @Result = 1;
	END;

	ELSE
	BEGIN
		SET @Result = 0;
	END;
	
	RETURN @Result;
END;
GO

