### AnyKernel3 Ramdisk Mod Script
## Realme 6 Pro (RMX2061, atoll) - Nezuko BakaSU
## Based on osm0sis @ xda-developers

### AnyKernel setup
# global properties
properties() { '
kernel.string=Nezuko BakaSU | RMX2061
do.devicecheck=1
do.modules=0
do.systemless=0
do.cleanup=1
do.cleanuponabort=0

# Supported devices
device.name1=RMX2061
device.name2=RMX2170
device.name3=atoll
device.name4=reatoll
device.name5=realme6pro
device.name6=realme7pro
device.name7=rmx2061
device.name8=rmx2170

supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties


### AnyKernel install
# boot shell variables
# Realme 6 Pro (RMX2061, atoll): A-only device
BLOCK=/dev/block/bootdevice/by-name/boot;
IS_SLOT_DEVICE=0;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

# boot install
# Kernel-only flash: ramdisk TIDAK dibongkar/dipasang ulang
split_boot;
flash_boot;

ui_print " " "  >> Nezuko BakaSU flashed successfully!" " ";
## end boot install
