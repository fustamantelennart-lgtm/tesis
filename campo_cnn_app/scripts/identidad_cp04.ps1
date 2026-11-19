param([string]$Proyecto = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path)

$ErrorActionPreference = 'Stop'
$archivos = @(
  'integration_test/concordancia_test.dart',
  'integration_test/cp04_tensores_test.dart',
  'lib/cp04_ejecucion.dart',
  'lib/comparacion_referencias.dart',
  'lib/preprocesamiento.dart',
  'lib/decodificador_jpeg.dart',
  'lib/diagnostico_motor.dart',
  'lib/domain.dart',
  'pubspec.yaml',
  'android/app/build.gradle.kts',
  'android/app/src/main/AndroidManifest.xml',
  'pubspec.lock'
)
$lineas = foreach ($relativo in $archivos) {
  $ruta = Join-Path $Proyecto $relativo
  if (-not (Test-Path -LiteralPath $ruta -PathType Leaf)) { throw "Falta $ruta" }
  "$relativo $((Get-FileHash -LiteralPath $ruta -Algorithm SHA256).Hash.ToLowerInvariant())"
}
$flutter = flutter --version --machine | ConvertFrom-Json
$lineas += "flutter $($flutter.frameworkRevision)"
$lineas += "engine $($flutter.engineRevision)"
$lineas += "dart $($flutter.dartSdkVersion)"
$datos = [Text.Encoding]::UTF8.GetBytes(($lineas -join "`n") + "`n")
$sha = [Security.Cryptography.SHA256]::Create()
try {
  $huella = -join ($sha.ComputeHash($datos) | ForEach-Object { $_.ToString('x2') })
} finally {
  $sha.Dispose()
}
Write-Output $huella
