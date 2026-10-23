USE ModaEstilo_BI_Demo;
GO
SET NOCOUNT ON;

-- 1) Hechos: filas y monto de la vista frente a su origen
SELECT Vista, Filas_Vista, Filas_Origen, Monto_Vista, Monto_Origen,
       CASE WHEN Filas_Vista = Filas_Origen AND Monto_Vista = Monto_Origen
            THEN 'COINCIDE' ELSE 'DISCREPANCIA' END AS Resultado
FROM (
    SELECT 1 AS Orden, 'bi.FactVenta' AS Vista,
           (SELECT COUNT(*) FROM bi.FactVenta)              AS Filas_Vista,
           (SELECT COUNT(*) FROM dbo.DetalleVenta)          AS Filas_Origen,
           (SELECT SUM(ImporteVenta) FROM bi.FactVenta)     AS Monto_Vista,
           (SELECT SUM(total) FROM dbo.Venta)               AS Monto_Origen
    UNION ALL
    SELECT 2, 'bi.FactAlquiler',
           (SELECT COUNT(*) FROM bi.FactAlquiler),
           (SELECT COUNT(*) FROM dbo.DetalleAlquiler),
           (SELECT SUM(ImporteAlquiler) FROM bi.FactAlquiler),
           (SELECT SUM(total) FROM dbo.Alquiler)
    UNION ALL
    SELECT 3, 'bi.FactPenalidad',
           (SELECT COUNT(*) FROM bi.FactPenalidad),
           (SELECT COUNT(*) FROM dbo.Penalidad),
           (SELECT SUM(MontoPenalidad) FROM bi.FactPenalidad),
           (SELECT SUM(monto) FROM dbo.Penalidad)
    UNION ALL
    SELECT 4, 'bi.FactGasto',
           (SELECT COUNT(*) FROM bi.FactGasto),
           (SELECT COUNT(*) FROM dbo.Gasto),
           (SELECT SUM(MontoGasto) FROM bi.FactGasto),
           (SELECT SUM(monto) FROM dbo.Gasto)
    UNION ALL
    SELECT 5, 'bi.FactPago',
           (SELECT COUNT(*) FROM bi.FactPago),
           (SELECT COUNT(*) FROM dbo.Pago),
           (SELECT SUM(MontoPago) FROM bi.FactPago),
           (SELECT SUM(monto) FROM dbo.Pago)
    UNION ALL
    SELECT 6, 'bi.FactCobranza (facturado)',
           (SELECT COUNT(*) FROM bi.FactCobranza),
           (SELECT COUNT(*) FROM dbo.Venta) + (SELECT COUNT(*) FROM dbo.Alquiler) + (SELECT COUNT(*) FROM dbo.Penalidad),
           (SELECT SUM(ImporteFacturado) FROM bi.FactCobranza),
           (SELECT SUM(total) FROM dbo.Venta) + (SELECT SUM(total) FROM dbo.Alquiler) + (SELECT SUM(monto) FROM dbo.Penalidad)
) x
ORDER BY Orden;

-- 2) Cobranza: cobrado y saldo pendiente
SELECT SUM(ImporteFacturado) AS Facturado,
       SUM(ImporteCobrado)   AS Cobrado,
       SUM(SaldoPendiente)   AS SaldoPendiente
FROM bi.FactCobranza;

-- 3) Dimensiones: filas de la vista frente a su origen
SELECT 'bi.DimCliente' AS Vista,    (SELECT COUNT(*) FROM bi.DimCliente)    AS Filas_Vista, (SELECT COUNT(*) FROM dbo.Cliente)    AS Filas_Origen
UNION ALL SELECT 'bi.DimTrabajador', (SELECT COUNT(*) FROM bi.DimTrabajador), (SELECT COUNT(*) FROM dbo.Trabajador)
UNION ALL SELECT 'bi.DimArticulo',   (SELECT COUNT(*) FROM bi.DimArticulo),   (SELECT COUNT(*) FROM dbo.Articulo)
UNION ALL SELECT 'bi.DimCategoria',  (SELECT COUNT(*) FROM bi.DimCategoria),  (SELECT COUNT(*) FROM dbo.Categoria)
UNION ALL SELECT 'bi.DimCalendario', (SELECT COUNT(*) FROM bi.DimCalendario), (SELECT COUNT(*) FROM dbo.DimFecha);