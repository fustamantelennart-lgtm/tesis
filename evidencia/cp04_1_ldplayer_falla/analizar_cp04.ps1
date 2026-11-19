param([string]$Carpeta = $PSScriptRoot)

$ErrorActionPreference = 'Stop'
$salidas = Join-Path $Carpeta 'salidas_despues'
$archivo = Get-ChildItem -LiteralPath $salidas -Filter 'comparacion_*.json' |
  Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $archivo) { throw 'Falta informe CP04 JSON' }
$informe = Get-Content -LiteralPath $archivo.FullName -Raw | ConvertFrom-Json
$csv = Get-ChildItem -LiteralPath $salidas -Filter 'comparacion_*.csv' |
  Sort-Object LastWriteTime | Select-Object -Last 1
if (-not $csv) { throw 'Falta informe CP04 CSV' }
$filasCsv = @(Import-Csv -LiteralPath $csv.FullName)
if ($informe.resultados.Count -ne 629 -or $filasCsv.Count -ne 629 -or
    $informe.entradas_verificadas -ne 629 -or $informe.comparadas -ne 629) {
  throw 'Informe o CSV incompleto'
}

$afectadas = @($informe.resultados | Where-Object {
  $_.error -or $_.score_cumple -eq $false -or $_.categoria_coincide -eq $false
} | ForEach-Object {
  [pscustomobject]@{
    cultivo = $_.cultivo
    ruta_relativa = $_.ruta_relativa
    sha256_original = $_.sha256_original
    error = $_.error
    score_referencia = $_.score_referencia
    score_android = $_.score_actual
    score_error_abs = $_.score_error_abs
    score_limite = $_.score_limite
    score_cumple = $_.score_cumple
    categoria_referencia = $_.categoria_referencia
    categoria_android = $_.categoria_actual
    categoria_coincide = $_.categoria_coincide
    tensor_max_abs = $_.tensor.max_abs
    tensor_media_abs = $_.tensor.media_abs
    tensor_rmse = $_.tensor.rmse
  }
})
$afectadas | Export-Csv -LiteralPath (Join-Path $Carpeta 'fotografias_afectadas.csv') -NoTypeInformation -Encoding UTF8

@($informe.resultados | ForEach-Object {
  [pscustomobject]@{
    cultivo = $_.cultivo
    ruta_relativa = $_.ruta_relativa
    sha256_original = $_.sha256_original
    sha256_tensor_referencia = $_.sha256_tensor_referencia
    sha256_tensor_android = $_.sha256_tensor_android
    tensor_max_abs = $_.tensor.max_abs
    tensor_indice_max_abs = $_.tensor.indice_max_abs
    tensor_media_abs = $_.tensor.media_abs
    tensor_rmse = $_.tensor.rmse
    tensor_valores_distintos = $_.tensor.valores_distintos
  }
}) | Export-Csv -LiteralPath (Join-Path $Carpeta 'tensores_diferentes.csv') -NoTypeInformation -Encoding UTF8

$grupos = @($informe.resultados | Group-Object cultivo | Sort-Object Name | ForEach-Object {
  $filas = @($_.Group)
  $tensores = @($filas | Where-Object { $_.tensor -ne $null })
  $maximos = @($tensores | ForEach-Object { $_.tensor.max_abs })
  $mayor = $tensores | Sort-Object { $_.tensor.max_abs } -Descending | Select-Object -First 1
  $medicion = $maximos | Measure-Object -Minimum -Maximum -Average
  [pscustomobject]@{
    cultivo = $_.Name
    fotografias = $filas.Count
    errores_ejecucion = @($filas | Where-Object { $_.error }).Count
    score_fuera_tolerancia = @($filas | Where-Object { $_.score_cumple -eq $false }).Count
    categoria_diferente = @($filas | Where-Object { $_.categoria_coincide -eq $false }).Count
    discrepancias_score_o_categoria = @($filas | Where-Object {
      $_.score_cumple -eq $false -or $_.categoria_coincide -eq $false
    }).Count
    tensor_con_valores_distintos = @($tensores | Where-Object {
      $_.tensor.valores_distintos -gt 0
    }).Count
    tensor_max_abs_min = $medicion.Minimum
    tensor_max_abs_promedio = $medicion.Average
    tensor_max_abs_max = $medicion.Maximum
    tensor_max_abs_fotografia = $mayor.ruta_relativa
  }
})
$grupos | Export-Csv -LiteralPath (Join-Path $Carpeta 'resumen_por_cultivo.csv') -NoTypeInformation -Encoding UTF8
$resumen = [pscustomobject]@{
  entorno = 'LDPlayer, instancia emulator-5554; Android declara SONY SOV44 y fisico=true, metadatos emulados'
  id_ejecucion = $informe.id_ejecucion
  estado = $informe.estado
  total_esperado = $informe.total_esperado
  entradas_verificadas = $informe.entradas_verificadas
  comparadas = $informe.comparadas
  reutilizadas = $informe.reutilizadas
  filas_csv = $filasCsv.Count
  fotografias_afectadas = $afectadas.Count
  manifiesto_sha256 = $informe.identidad.manifest_sha256
  codigo_sha256 = $informe.identidad.codigo_sha256
  informe_json_sha256 = (Get-FileHash -LiteralPath $archivo.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  informe_csv_sha256 = (Get-FileHash -LiteralPath $csv.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
  por_cultivo = $grupos
}
$resumen | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $Carpeta 'resumen_cp04_ldplayer.json') -Encoding UTF8
$resumen | ConvertTo-Json -Depth 7
