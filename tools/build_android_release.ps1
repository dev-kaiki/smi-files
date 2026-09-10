# Gera o APK de release do SMI Files para instalacao na mao.
#
# Rode NESTA maquina Windows: e aqui que mora a debug.keystore que assinou os
# APKs que os tecnicos ja tem. Compilar em outra maquina gera uma chave nova,
# a assinatura deixa de bater e o Android recusa a atualizacao com "app nao
# instalado". Neste app o contorno e pior que no outro: desinstalar apaga a
# fila de uploads pendentes, que e justamente o trabalho ainda nao enviado.
#
# Uso, a partir da raiz do repositorio:
#   .\tools\build_android_release.ps1

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

# dart-define.json fica fora do repositorio, entao ele NAO vem no git pull.
# Sem ele o app compila normalmente e sobe sem as credenciais do Supabase,
# falhando no login ja na mao do tecnico. Por isso o build para aqui.
if (-not (Test-Path 'dart-define.json')) {
    Write-Host 'ERRO: dart-define.json nao encontrado.' -ForegroundColor Red
    Write-Host 'Preencha as credenciais do Supabase antes de gerar a build.'
    exit 1
}

# Conferir o nome das chaves, e nao so a existencia do arquivo. Este app le
# SUPABASE_ANON_KEY; o checklist-smi le SUPABASE_ANON. Trocar os dois nao da
# erro de build: gera um APK que so falha no login, na mao do tecnico.
$def = Get-Content 'dart-define.json' -Raw | ConvertFrom-Json
foreach ($chave in @('SUPABASE_URL', 'SUPABASE_ANON_KEY')) {
    if (-not $def.PSObject.Properties.Name.Contains($chave) -or
        [string]::IsNullOrWhiteSpace($def.$chave)) {
        Write-Host "ERRO: dart-define.json sem a chave $chave." -ForegroundColor Red
        Write-Host 'Este app espera SUPABASE_URL e SUPABASE_ANON_KEY.'
        exit 1
    }
}

flutter clean
flutter pub get
flutter build apk --release --dart-define-from-file=dart-define.json
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$apk = 'build\app\outputs\flutter-apk\app-release.apk'

Write-Host ''
Write-Host "APK gerado: $apk" -ForegroundColor Green
Write-Host ''
Write-Host 'ANTES de mandar para os seis tecnicos: peca para o primeiro deles'
Write-Host 'sincronizar tudo, e so entao instale por cima, sem desinstalar.'
Write-Host 'Se aparecer "app nao instalado", a assinatura nao bate -- pare ai,'
Write-Host 'porque desinstalar nesse app custa a fila de uploads pendentes.'
