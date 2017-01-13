#!/bin/bash

TOOLS_DIR="$PWD/bin"
IFDTOOL="$TOOLS_DIR/ich_descriptors_tool"
ME_CLEANER="$TOOLS_DIR/me_cleaner.py"
ROM_HEADERS="$TOOLS_DIR/romheaders"
UEFI_EXTRACT="$TOOLS_DIR/uefiextract"
ROM_FILE=""
DISABLE_ME=0

set -e

function is_new_x86_layout() {
  local src="$1"
  local ret=""

  $IFDTOOL -f "$src" && echo $? > result
  ret=$(cat result)
  if [ "$ret" == "1" ] ; then
    rm "result"
    return 0
  else
    rm "result"
    return 1
  fi
}

function get_real_mac() {
  local src="$1"

  $IFDTOOL -f "$src" | awk -F: -v key=\"The MAC address might be at offset 0x1000\" \
  '\$1==key {printf(\"%s:%s:%s:%s:%s:%s\", \$2, \$3, \$4, \$5, \$6, \$7)}' | tr -d '[:space:]' > macaddress
}

function disable_me() {
  local src="$1"

  if [ -f "$src" ] ; then
    $ME_CLEANER "$src"
  fi
}

function get_vgabios_name() {
  local src="$1"

  echo -n "VGABIOS_NAME=pci" > vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Vendor ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && \
  echo -n "," >> vgabios_pci.name && "$ROM_HEADERS" "$src" | grep 'Device ID:' | cut -d ':' -f 2 | tr -d '[:space:]' | sed -e "s/^0x//" >> vgabios_pci.name && echo ".rom" >> vgabios_pci.name
}

function extract_x86_blobs() {
  local src="$1"

  $IFDTOOL -d -f "$src"
}

function extract_vgabios() {
  local src="$1"
  local pattern="$2"

  $UEFI_EXTRACT "$src" dump
  grep -rl "$pattern" "$(basename "$src.dump")" > vgabios.list

  while IFS='\n' read -r p < vgabios.list
  do
    cp "$p" vgabios.bin
    get_vgabios_name vgabios.bin
    source vgabios_pci.name
    rm vgabios_pci.name
    mv vgabios.bin "$VGABIOS_NAME"
  done

  rm vgabios.list
}

if ( ! getopts "r:dh" opt); then
	echo "Usage: $(basename "$0") options (-d disable Management Engine) (-r rom.bin) -h for help";
	exit $E_OPTERROR
fi

while getopts "r:dh" opt; do
     case $opt in
         d) export DISABLE_ME=1 ;;
         r) export ROM_FILE="$OPTARG" ;;
     esac
done

if is_new_x86_layout "$ROM_FILE" ; then
  get_real_mac "$ROM_FILE"
  extract_x86_blobs "$ROM_FILE"
  if [ "$DISABLE_ME" == "1" ] ; then
    disable_me "$ROM_FILE.ME.bin"
  fi
  extract_vgabios "$ROM_FILE.BIOS.bin" "VGA Compatible"
fi
