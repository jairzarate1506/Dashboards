/*
  01_validacion_calidad.sql  |  Evidencia E-06 (Cap. 6.1)
*/
USE ModaEstilo_BI_Demo;   -- o ModaEstilo_Final
GO
SET NOCOUNT ON;
CREATE TABLE #R (Orden INT IDENTITY, Control VARCHAR(80), Valor DECIMAL(18,2));

-- 1) Registros por tabla (y total)
INSERT #R(Control,Valor) SELECT 'Registros ' + t.name, SUM(p.rows)
FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE t.schema_id=SCHEMA_ID('dbo') GROUP BY t.name;
INSERT #R(Control,Valor) SELECT 'Registros TOTAL', SUM(p.rows)
FROM sys.tables t JOIN sys.partitions p ON p.object_id=t.object_id AND p.index_id IN (0,1)
WHERE t.schema_id=SCHEMA_ID('dbo');

-- 2) Completitud: nulos en campos obligatorios de las tablas transaccionales
INSERT #R(Control,Valor) SELECT 'Nulos obligatorios (venta/alquiler/detalles/pago)',
  (SELECT COUNT(*) FROM dbo.Venta WHERE idCliente IS NULL OR idTrabajador IS NULL OR fechaVenta IS NULL OR total IS NULL)
 +(SELECT COUNT(*) FROM dbo.Alquiler WHERE idCliente IS NULL OR idTrabajador IS NULL OR fechaAlquiler IS NULL OR fechaDevolucionProgramada IS NULL OR total IS NULL)
 +(SELECT COUNT(*) FROM dbo.DetalleVenta WHERE idArticulo IS NULL OR cantidad IS NULL OR precioUnitario IS NULL OR subtotal IS NULL)
 +(SELECT COUNT(*) FROM dbo.DetalleAlquiler WHERE idArticulo IS NULL OR cantidad IS NULL OR precioUnitario IS NULL OR subtotal IS NULL)
 +(SELECT COUNT(*) FROM dbo.Pago WHERE fechaPago IS NULL OR monto IS NULL OR metodoPago IS NULL);

-- 3) Duplicados
INSERT #R(Control,Valor) SELECT 'Duplicados Cliente.dni',  COUNT(*) FROM (SELECT dni FROM dbo.Cliente GROUP BY dni HAVING COUNT(*)>1) x;
INSERT #R(Control,Valor) SELECT 'Duplicados Articulo.codigo', COUNT(*) FROM (SELECT codigo FROM dbo.Articulo GROUP BY codigo HAVING COUNT(*)>1) x;
INSERT #R(Control,Valor) SELECT 'Duplicados DetalleVenta (venta,articulo)', COUNT(*) FROM (SELECT 1 a FROM dbo.DetalleVenta GROUP BY idVenta,idArticulo HAVING COUNT(*)>1) x;
INSERT #R(Control,Valor) SELECT 'Duplicados DetalleAlquiler (alquiler,articulo)', COUNT(*) FROM (SELECT 1 a FROM dbo.DetalleAlquiler GROUP BY idAlquiler,idArticulo HAVING COUNT(*)>1) x;

-- 4) Integridad referencial (huérfanos)
INSERT #R(Control,Valor) SELECT 'Huérfanos FK (venta/alquiler/detalles/devolución/pago)',
  (SELECT COUNT(*) FROM dbo.Venta v LEFT JOIN dbo.Cliente c ON c.idCliente=v.idCliente WHERE c.idCliente IS NULL)
 +(SELECT COUNT(*) FROM dbo.Alquiler a LEFT JOIN dbo.Cliente c ON c.idCliente=a.idCliente WHERE c.idCliente IS NULL)
 +(SELECT COUNT(*) FROM dbo.DetalleVenta d LEFT JOIN dbo.Venta v ON v.idVenta=d.idVenta WHERE v.idVenta IS NULL)
 +(SELECT COUNT(*) FROM dbo.DetalleVenta d LEFT JOIN dbo.Articulo a ON a.idArticulo=d.idArticulo WHERE a.idArticulo IS NULL)
 +(SELECT COUNT(*) FROM dbo.DetalleAlquiler d LEFT JOIN dbo.Alquiler a ON a.idAlquiler=d.idAlquiler WHERE a.idAlquiler IS NULL)
 +(SELECT COUNT(*) FROM dbo.Devolucion d LEFT JOIN dbo.Alquiler a ON a.idAlquiler=d.idAlquiler WHERE a.idAlquiler IS NULL)
 +(SELECT COUNT(*) FROM dbo.Pago p WHERE p.idVenta IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Venta v WHERE v.idVenta=p.idVenta))
 +(SELECT COUNT(*) FROM dbo.Pago p WHERE p.idAlquiler IS NOT NULL AND NOT EXISTS (SELECT 1 FROM dbo.Alquiler a WHERE a.idAlquiler=p.idAlquiler));

-- 5) Consistencia financiera y de fechas
INSERT #R(Control,Valor) SELECT 'Venta.total <> suma de detalles', COUNT(*)
FROM dbo.Venta v OUTER APPLY (SELECT SUM(d.subtotal) t FROM dbo.DetalleVenta d WHERE d.idVenta=v.idVenta) x WHERE ABS(v.total-ISNULL(x.t,0))>0.001;
INSERT #R(Control,Valor) SELECT 'Alquiler.total <> suma de detalles', COUNT(*)
FROM dbo.Alquiler a OUTER APPLY (SELECT SUM(d.subtotal) t FROM dbo.DetalleAlquiler d WHERE d.idAlquiler=a.idAlquiler) x WHERE ABS(a.total-ISNULL(x.t,0))>0.001;
INSERT #R(Control,Valor) SELECT 'Alquileres con fechas ilógicas', COUNT(*) FROM dbo.Alquiler
WHERE fechaDevolucionProgramada<fechaAlquiler OR fechaEntrega<fechaAlquiler OR fechaDevolucionProgramada<fechaEntrega OR fechaDevolucionReal<fechaEntrega;
INSERT #R(Control,Valor) SELECT 'Cantidades <= 0 o montos <= 0',
  (SELECT COUNT(*) FROM dbo.DetalleVenta WHERE cantidad<=0)+(SELECT COUNT(*) FROM dbo.DetalleAlquiler WHERE cantidad<=0)
 +(SELECT COUNT(*) FROM dbo.Pago WHERE monto<=0)+(SELECT COUNT(*) FROM dbo.Penalidad WHERE monto<=0)+(SELECT COUNT(*) FROM dbo.Gasto WHERE monto<=0);

-- 6) Totales de referencia para reconciliar con el Data Mart / Power BI
INSERT #R(Control,Valor) SELECT 'SUM Venta.total', SUM(total) FROM dbo.Venta;
INSERT #R(Control,Valor) SELECT 'SUM Alquiler.total', SUM(total) FROM dbo.Alquiler;
INSERT #R(Control,Valor) SELECT 'SUM Penalidad.monto', SUM(monto) FROM dbo.Penalidad;
INSERT #R(Control,Valor) SELECT 'SUM Gasto.monto', SUM(monto) FROM dbo.Gasto;
INSERT #R(Control,Valor) SELECT 'Alquileres sin devolución real', COUNT(*) FROM dbo.Alquiler WHERE fechaDevolucionReal IS NULL;
INSERT #R(Control,Valor) SELECT 'Artículos con stock <= stock mínimo', COUNT(*) FROM dbo.Articulo WHERE stock<=stockMinimo;

-- 7) Reconciliación Data Mart (solo existe en ModaEstilo_BI_Demo)
IF SCHEMA_ID('bi') IS NOT NULL
BEGIN
  INSERT #R(Control,Valor) SELECT 'bi.FactVenta SUM(ImporteVenta)', SUM(ImporteVenta) FROM bi.FactVenta;
  INSERT #R(Control,Valor) SELECT 'bi.FactAlquiler SUM(ImporteAlquiler)', SUM(ImporteAlquiler) FROM bi.FactAlquiler;
  INSERT #R(Control,Valor) SELECT 'bi.FactPenalidad SUM(MontoPenalidad)', SUM(MontoPenalidad) FROM bi.FactPenalidad;
  INSERT #R(Control,Valor) SELECT 'bi.FactGasto SUM(MontoGasto)', SUM(MontoGasto) FROM bi.FactGasto;
  INSERT #R(Control,Valor) SELECT 'Filas bi.FactVenta', COUNT(*) FROM bi.FactVenta;
  INSERT #R(Control,Valor) SELECT 'Filas bi.FactAlquiler', COUNT(*) FROM bi.FactAlquiler;
  INSERT #R(Control,Valor) SELECT 'Filas bi.FactCobranza', COUNT(*) FROM bi.FactCobranza;
END

SELECT Control, Valor FROM #R ORDER BY Orden;
DROP TABLE #R;