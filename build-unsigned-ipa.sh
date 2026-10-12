#!/bin/bash
set -euo pipefail
PROJECT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
if ! command -v xcodebuild >/dev/null 2>&1; then
  printf '%s\n' 'Este script precisa de um Mac com Xcode instalado. Sideloadly assina e instala o IPA, mas não compila código-fonte.' >&2
  exit 1
fi
if ! xcrun --sdk iphoneos --show-sdk-path >/dev/null 2>&1; then
  printf '%s\n' 'O SDK iPhoneOS não está disponível. Instale o Xcode completo e selecione-o com xcode-select.' >&2
  exit 1
fi
BUILD_DIRECTORY="$PROJECT_DIRECTORY/build"
mkdir -p "$BUILD_DIRECTORY"
xcodebuild -project "$PROJECT_DIRECTORY/MesAMes.xcodeproj" -scheme MesAMes \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath "$BUILD_DIRECTORY/DerivedData" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' build
APP_PATH="$BUILD_DIRECTORY/DerivedData/Build/Products/Release-iphoneos/MesAMes.app"
if [ ! -f "$APP_PATH/MesAMes" ]; then
  printf '%s\n' 'O executável iOS não foi gerado. Nenhum IPA foi criado.' >&2
  exit 1
fi
PACKAGE_DIRECTORY="$BUILD_DIRECTORY/IPA"
mkdir -p "$PACKAGE_DIRECTORY/Payload"
ditto "$APP_PATH" "$PACKAGE_DIRECTORY/Payload/MesAMes.app"
find "$PACKAGE_DIRECTORY/Payload/MesAMes.app" -name _CodeSignature -type d -prune -exec rm -rf {} +
rm -f "$PACKAGE_DIRECTORY/Payload/MesAMes.app/embedded.mobileprovision"
OUTPUT_PATH="$BUILD_DIRECTORY/MesAMes-unsigned.ipa"
rm -f "$OUTPUT_PATH"
(cd "$PACKAGE_DIRECTORY" && /usr/bin/zip -qry "$OUTPUT_PATH" Payload)
printf 'IPA sem assinatura gerado: %s\n' "$OUTPUT_PATH"
printf '%s\n' 'Abra este arquivo no Sideloadly para assinar e instalar. Valide login, bancos e desempenho no iPhone antes de tratar o app como versão final.'
