#!/bin/zsh
# scripts/p5-strict.sh — passe stricte hors gate. Ne touche jamais .build.
set -u
cd "$(git rev-parse --show-toplevel)"
SRC=("${(@f)$(find StarHubTH -name '*.swift' | sort)}")
OUT=${1:-/tmp/p5-measure}
mkdir -p "$OUT/module-cache"
t0=$SECONDS
xcrun swiftc "${SRC[@]}" -target "$(uname -m)-apple-macosx14.0" \
  -o "$OUT/probe" -parse-as-library \
  -module-cache-path "$OUT/module-cache" \
  -strict-concurrency=complete > "$OUT/strict.log" 2>&1 < /dev/null
code=$?

# Complétude avant compte (leçon L4, 2026-09-14). Une passe tuée — l'édition de
# liens perdue, la machine à court de mémoire — **sous-compte en silence** : le
# journal garde ses diagnostics partiels et son pied de page d'URL, qui ne
# prouve rien. Le binaire, lui, n'existe que si le compilateur est allé au bout.
# Sans lui, refuser de rendre un chiffre vaut mieux qu'en rendre un faux : c'est
# ainsi qu'un « −25 » est passé pour mesuré alors qu'il valait −22.
if [[ ! -x "$OUT/probe" ]]; then
  echo "PASSE INCOMPLÈTE — le binaire $OUT/probe n'existe pas (exit=$code)."
  echo "Les comptes de $OUT/strict.log sont partiels : ne rien en publier."
  exit 2
fi

w=$(grep -cE '^[^ ].*:[0-9]+:[0-9]+: warning:' "$OUT/strict.log")
e=$(grep -cE '^[^ ].*:[0-9]+:[0-9]+: error:' "$OUT/strict.log")
s6=$(grep -E '^[^ ].*:[0-9]+:[0-9]+: warning:' "$OUT/strict.log" \
     | grep -c 'error in the Swift 6 language mode')
echo "exit=$code  avertissements=$w  bloquants_swift6=$s6  erreurs=$e  duree=$((SECONDS-t0))s"
