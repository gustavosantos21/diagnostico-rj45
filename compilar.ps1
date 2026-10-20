$ErrorActionPreference = 'Stop'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:winexe /platform:anycpu /optimize+ /win32manifest:"$PSScriptRoot\app.manifest" /out:"$PSScriptRoot\DiagnosticoRJ45.exe" /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Management.dll "$PSScriptRoot\NetworkProbe.cs" "$PSScriptRoot\NativeNetwork.cs"
if ($LASTEXITCODE -ne 0) { throw 'Falha ao compilar o aplicativo.' }
