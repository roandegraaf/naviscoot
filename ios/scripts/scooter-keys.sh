#!/bin/zsh
# Fills the NAVISCOOT_SCOOTER_* values in Config/Local.xcconfig from the Mac login Keychain.
set -euo pipefail

config="${0:A:h}/../Config/Local.xcconfig"
password_service="Naviscoot scooter BLE password"
ident_service="Naviscoot scooter BLE ident"

serial="${1:-$(security find-generic-password -s "$password_service" 2>/dev/null | sed -n 's/.*"acct"<blob>="\(.*\)"/\1/p')}"
if [[ -z $serial ]]; then
  print -u2 "No serial found. Pass it as the first argument, or store the password under service \"$password_service\"."
  exit 1
fi

password=$(security find-generic-password -a "$serial" -s "$password_service" -w 2>/dev/null) || {
  print -u2 "No Keychain item \"$password_service\" for $serial."
  exit 1
}
ident=$(security find-generic-password -a "$serial" -s "$ident_service" -w 2>/dev/null || true)

for name value in password "$password" ident "$ident"; do
  if [[ -n $value && ! $value =~ '^[0-9a-fA-F]{32}$' ]]; then
    print -u2 "The $name in the Keychain is not 32 hex characters."
    exit 1
  fi
done

touch "$config"

set_value() {
  local key=$1 value=$2 tmp
  tmp=$(mktemp)
  grep -v -E "^[[:space:]]*${key}[[:space:]]*=" "$config" > "$tmp" || true
  print -r -- "$key = $value" >> "$tmp"
  mv "$tmp" "$config"
}

set_value NAVISCOOT_SCOOTER_SERIAL "$serial"
set_value NAVISCOOT_SCOOTER_PASSWORD "$password"
print "Wrote serial $serial and password to Config/Local.xcconfig."
if [[ -n $ident ]]; then
  set_value NAVISCOOT_SCOOTER_IDENT "$ident"
  print "Wrote the seat/power ident too."
else
  print "No \"$ident_service\" item, so the seat/power ident is left as it was."
fi
