#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'DMG packaging requires macOS (hdiutil). Use the macOS GitHub Actions job.' >&2
  exit 1
fi
scripts/build_macos.sh
staging="$(mktemp -d)"
trap 'rm -rf "$staging"' EXIT
# ditto preserves executable permissions and bundle metadata.
ditto -x -k build/Botball-Lab-macOS.zip "$staging"
test -d "$staging/Botball Lab.app"
ln -s /Applications "$staging/Applications"
cat > "$staging/Установка.txt" <<'TEXT'
Перенеси Botball Lab.app в «Программы».
Для обновления сначала закрой Botball Lab, затем замени старую версию.
Сохранённые проекты не удаляются. Кнопка «Обновления» проверяет новые релизы.
TEXT
rm -f build/Botball-Lab-macOS.dmg
hdiutil create -volname "Botball Lab" -srcfolder "$staging" -ov -format UDZO build/Botball-Lab-macOS.dmg
hdiutil verify build/Botball-Lab-macOS.dmg
(cd build && shasum -a 256 Botball-Lab-macOS.dmg Botball-Lab-macOS.zip > SHA256SUMS.txt)
