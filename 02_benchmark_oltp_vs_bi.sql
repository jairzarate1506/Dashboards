/*
  02_benchmark_oltp_vs_bi.sql  |  Evidencias E-07 y E-09 (Cap. 6.2, 6.3)
  Mide la MISMA pregunta de negocio (ingreso por año, mes y categoría,
  ventas + alquileres) de dos formas sobre ModaEstilo_BI_Demo:
    A) OLTP : joins directos sobre las tablas dbo.*
    B) BI   : sobre las vistas dimensionales bi.*
*/
USE ModaEstilo_BI_Demo;
GO
SET NOCOUNT ON;
DECLARE @N INT = 10;              -- repeticiones por escenario y condición de caché
DECLARE @i INT, @t0 DATETIME2(7), @us BIGINT, @filas INT, @tot DECIMAL(18,2), @frio BIT, @esc VARCHAR(10);

CREATE TABLE #Res (Escenario VARCHAR(10), Cache VARCHAR(6), Corrida INT, Microsegundos BIGINT, Filas INT, Total DECIMAL(18,2));
CREATE TABLE #Out (Anio INT, Mes INT, Categoria NVARCHAR(100), Importe DECIMAL(18,2));

DECLARE @combos TABLE (Escenario VARCHAR(10), Frio BIT);
INSERT @combos VALUES ('OLTP',1),('BI',1),('OLTP',0),('BI',0);

DECLARE c CURSOR LOCAL FAST_FORWARD FOR SELECT Escenario, Frio FROM @combos;
OPEN c; FETCH NEXT FROM c INTO @esc, @frio;
WHILE @@FETCH_STATUS = 0
BEGIN
  -- caché caliente: la corrida 0 es de calentamiento y no se registra
  SET @i = CASE WHEN @frio = 1 THEN 1 ELSE 0 END;
  WHILE @i <= @N
  BEGIN
    TRUNCATE TABLE #Out;
    IF @frio = 1 BEGIN CHECKPOINT; DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS; END
    SET @t0 = SYSDATETIME();
    IF @esc = 'OLTP'
      INSERT #Out
      SELECT x.Anio, x.Mes, x.Categoria, SUM(x.Importe)
      FROM (
        SELECT YEAR(v.fechaVenta) Anio, MONTH(v.fechaVenta) Mes, ca.nombreCategoria Categoria, d.subtotal Importe
        FROM dbo.DetalleVenta d JOIN dbo.Venta v ON v.idVenta=d.idVenta
        JOIN dbo.Articulo a ON a.idArticulo=d.idArticulo JOIN dbo.Categoria ca ON ca.idCategoria=a.idCategoria
        UNION ALL
        SELECT YEAR(al.fechaAlquiler), MONTH(al.fechaAlquiler), ca.nombreCategoria, d.subtotal
        FROM dbo.DetalleAlquiler d JOIN dbo.Alquiler al ON al.idAlquiler=d.idAlquiler
        JOIN dbo.Articulo a ON a.idArticulo=d.idArticulo JOIN dbo.Categoria ca ON ca.idCategoria=a.idCategoria
      ) x GROUP BY x.Anio, x.Mes, x.Categoria;
    ELSE
      INSERT #Out
      SELECT cal.Anio, cal.MesNumero, art.Categoria, SUM(f.Importe)
      FROM (
        SELECT FechaVentaKey FechaKey, ArticuloKey, ImporteVenta Importe FROM bi.FactVenta
        UNION ALL
        SELECT FechaAlquilerKey, ArticuloKey, ImporteAlquiler FROM bi.FactAlquiler
      ) f JOIN bi.DimCalendario cal ON cal.FechaKey=f.FechaKey
          JOIN bi.DimArticulo art ON art.ArticuloKey=f.ArticuloKey
      GROUP BY cal.Anio, cal.MesNumero, art.Categoria;
    SET @us = DATEDIFF_BIG(MICROSECOND, @t0, SYSDATETIME());
    SELECT @filas = COUNT(*), @tot = SUM(Importe) FROM #Out;
    IF @i > 0 INSERT #Res VALUES (@esc, CASE WHEN @frio=1 THEN 'fria' ELSE 'caliente' END, @i, @us, @filas, @tot);
    SET @i += 1;
  END
  FETCH NEXT FROM c INTO @esc, @frio;
END
CLOSE c; DEALLOCATE c;

-- A) Todas las corridas (para el log / anexo)
SELECT * FROM #Res ORDER BY Cache, Escenario, Corrida;

-- B) Resumen: media, desviación estándar, CV
SELECT Escenario, Cache, COUNT(*) AS Corridas,
       CAST(AVG(Microsegundos)/1000.0 AS DECIMAL(10,2))   AS Media_ms,
       CAST(STDEV(Microsegundos)/1000.0 AS DECIMAL(10,2)) AS DesvEst_ms,
       CAST(MIN(Microsegundos)/1000.0 AS DECIMAL(10,2))   AS Min_ms,
       CAST(MAX(Microsegundos)/1000.0 AS DECIMAL(10,2))   AS Max_ms,
       CAST(100.0*STDEV(Microsegundos)/NULLIF(AVG(Microsegundos),0) AS DECIMAL(6,2)) AS CV_pct,
       MAX(Filas) AS Filas, MAX(Total) AS TotalReconciliado
FROM #Res GROUP BY Escenario, Cache ORDER BY Cache, Escenario;

-- C) Diferencia porcentual de latencia BI frente a OLTP (negativo = BI más rápido) y chequeo de igualdad de resultado
SELECT o.Cache,
       CAST(AVG(o.Microsegundos)/1000.0 AS DECIMAL(10,2)) AS OLTP_ms,
       CAST(AVG(b.Microsegundos)/1000.0 AS DECIMAL(10,2)) AS BI_ms,
       CAST(100.0*(AVG(b.Microsegundos*1.0)-AVG(o.Microsegundos*1.0))/AVG(o.Microsegundos*1.0) AS DECIMAL(8,2)) AS Delta_pct,
       CASE WHEN MAX(o.Total)=MAX(b.Total) AND MAX(o.Filas)=MAX(b.Filas) THEN 'COINCIDEN' ELSE 'DISCREPANCIA' END AS Reconciliacion
FROM #Res o JOIN #Res b ON b.Cache=o.Cache AND b.Corrida=o.Corrida AND b.Escenario='BI'
WHERE o.Escenario='OLTP' GROUP BY o.Cache;

DROP TABLE #Out; DROP TABLE #Res;