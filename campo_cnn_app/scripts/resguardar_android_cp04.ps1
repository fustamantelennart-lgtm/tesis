param(
  [Parameter(Mandatory=$true)][string]$Dispositivo,
  [string]$Destino
)

$ErrorActionPreference = 'Stop'
if (-not $Destino) {
  # Respaldos binarios de datos privados: fuera del repositorio (_local/ esta ignorado).
  $Destino = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path '_local/resguardos_android'
}
if ($Dispositivo -notmatch '^[A-Za-z0-9._:-]+$') {
  throw 'ID Android invalido.'
}
New-Item -ItemType Directory -Path $Destino -Force | Out-Null
$marca = Get-Date -Format 'yyyyMMdd_HHmmss_fffffff'
$archivo = Join-Path $Destino "privado_${Dispositivo}_$marca.tgz"
$inicio = New-Object System.Diagnostics.ProcessStartInfo
$inicio.FileName = 'adb'
$inicio.Arguments = "-s $Dispositivo exec-out run-as com.example.campo_cnn tar -czf - ."
$inicio.UseShellExecute = $false
$inicio.RedirectStandardOutput = $true
$inicio.RedirectStandardError = $true
$inicio.CreateNoWindow = $true
$proceso = [System.Diagnostics.Process]::Start($inicio)
try {
  $errorPendiente = $proceso.StandardError.ReadToEndAsync()
  $salida = [IO.File]::Open($archivo, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
  try {
    $proceso.StandardOutput.BaseStream.CopyTo($salida)
  } finally {
    $salida.Dispose()
  }
  $proceso.WaitForExit()
  $errorTexto = $errorPendiente.Result
  if ($proceso.ExitCode -ne 0 -or (Get-Item -LiteralPath $archivo).Length -eq 0) {
    throw "Respaldo no confirmado. Archivo parcial: $archivo. adb: $errorTexto"
  }
  Write-Output $archivo
} finally {
  $proceso.Dispose()
}
