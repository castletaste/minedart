#!/bin/sh
# Раздаёт web-сборку спайка на http://127.0.0.1:8757/
cd "$(dirname "$0")/s5_web/build/web" || exit 1
exec python3 -m http.server 8757 --bind 127.0.0.1
