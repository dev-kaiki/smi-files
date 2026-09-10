#!/usr/bin/env bash
set -euo pipefail

# Gera o .ipa assinado para envio ao App Store Connect.
# Rode a partir da raiz do repositorio: ./tools/build_ios_release.sh

cd "$(dirname "$0")/.."

# dart-define.json fica fora do repositorio (ver .gitignore). Sem ele o app
# compila normalmente, mas sobe sem as credenciais do Supabase e falha no
# login ja na mao do tecnico -- por isso a build para aqui.
if [ ! -f dart-define.json ]; then
  echo "ERRO: dart-define.json nao encontrado."
  echo "Preencha as credenciais do Supabase antes de gerar a build."
  exit 1
fi

flutter clean
flutter pub get
flutter build ipa \
  --release \
  --dart-define-from-file=dart-define.json \
  --export-options-plist=ios/ExportOptions.plist

echo
echo "IPA gerado em build/ios/ipa/"
echo "Envie com:  xcrun altool --upload-app -f build/ios/ipa/*.ipa -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>"
echo "Ou abra o Xcode > Organizer e use Distribute App."
