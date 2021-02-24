#!/bin/bash
LUKS_DEVICE=/dev/XXX
LUKS_SLOT=YYY

read -r -p "Confirm? [type YES] " choice
[ "${choice}" = "YES" ] || exit 0

umask 177

if [ "${1}" = "-i" ]; then
  echo "Generating a new key"
  /usr/bin/tpm2_getrandom -f 32 -o masterKey.bin || exit 1
  /usr/bin/cryptsetup luksKillSlot "${LUKS_DEVICE}" "${LUKS_SLOT}" || exit 2
  /usr/bin/cryptsetup luksAddKey "${LUKS_DEVICE}" masterKey.bin || exit 3
  /usr/bin/openssl enc -e -aes-256-cbc -md sha512 --pbkdf2 --iter 100000 -in masterKey.bin -out wrappedKey.bin || exit 4
  shred -u masterKey.bin && echo "Done"
  exit 0
fi

[ -f ./wrappedKey.bin ] || exit 0

if grep -q 0x81000000 < <(/usr/bin/tpm2_getcap handles-persistent); then
  echo "Clearing the old key"
  /usr/bin/tpm2_evictcontrol -C o -c 0x81000000 || exit 1
fi

echo "Adding key to TPM"
/usr/bin/tpm2_createpolicy --policy-pcr -l sha256:0,2,4,7,14 -L policy.digest || exit 2
/usr/bin/tpm2_createprimary -C e -c primary.context || exit 3
/usr/bin/tpm2_create -u obj.pub -r obj.priv -C primary.context -L policy.digest -a "noda|adminwithpolicy|fixedparent|fixedtpm" -i wrappedKey.bin || exit 4
/usr/bin/tpm2_load -C primary.context -u obj.pub -r obj.priv -c load.context || exit 5
/usr/bin/tpm2_evictcontrol -C o -c load.context 0x81000000 || exit 6

shred -u wrappedKey.bin load.context obj.priv obj.pub policy.digest primary.context && echo "Done"
