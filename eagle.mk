# This makefile expects the following variables to be set:
#
# DOWNLOAD_DIR: 	Used to store downloaded files
# TMP_DIR		Used to hold temporary files
# FIRMWARE_DEST_DIR 	Location to store downloaded firmware file
# ROOTFS_IMG		Location of rootfs image
# BOOT_IMG		Location of boot image
# IMAGE			Location of Linux kernel image
# INITRD		Location of initrd image
# DTB			Location of Device Tree Binary
#
# The skales repo is at: git://codeaurora.org/quic/kernel/skales
#
# Optional variables:
#
# EAGLE_KERNEL		Directory for the kernel source
# SKALES		Location of cloned skales repository
#
# if BUILD_DEFAULT_KERNEL=1 then the following must be provided:
#
# KERNEL_CONFIG		Location of kernel config file
#
# if FIRMWARE_UNPACK_DIR is defined then the target _firmware-unpack
# will unpack the firmware to FIRMWARE_UNPACK_DIR
#
# The target _firmware will download provide instructions to
# dowload the firmware
#


ifeq ($(DOWNLOAD_DIR),)
$(error DOWNLOAD_DIR Undefined)
endif

ifeq ($(TMP_DIR),)
$(error TMP_DIR Undefined)
endif

ifeq ($(FIRMWARE_DEST_DIR),)
$(error FIRMWARE_DEST_DIR Undefined)
endif

ifeq ($(ROOTFS_IMG),)
$(error ROOTFS_IMG Undefined)
endif

ifeq ($(BOOT_IMG),)
$(error BOOT_IMG Undefined)
endif

ifeq ($(DTB),)
$(error DTB Undefined)
endif

ifeq ($(IMAGE),)
$(error IMAGE Undefined)
endif

ifeq ($(shell which fdtget),)
$(error Missing fdtget, run: sudo apt-get install device-tree-compiler)
endif

ifneq ($(FIRMWARE_UNPACK_DIR),)
$(error FIRMWARE_UNPACK_DIR Undefined)
endif

INITRD:=$(DOWNLOAD_DIR)/initrd.img-4.0.0-linaro-lt-qcom
EAGLE_KERNEL?=eagle-linux
KERNEL_VERSION?=origin/release/qcomlt-4.0
SKALES?=skales

FIRMWARE_ZIP:=$(FIRMWARE_DEST_DIR)/Flight_BSP_3.0_apq8074-le-1-0_r00015.zip

$(FIRMWARE_UNPACK_DIR)/.unpacked: $(FIRMWARE_ZIP) $(DOWNLOAD_DIR)/.exists 
	mkdir -p $(FIRMWARE_UNPACK_DIR)
	[ -f $(DOWNLOAD_DIR)/Flight_BSP_3.0_apq8074-le-1-0_r00015.zip ] || (cd $(DOWNLOAD_DIR) && unzip $(FIRMWARE_ZIP))
	[ -f $(FIRMWARE_UNPACK_DIR)/.unpacked ] || unzip $(DOWNLOAD_DIR)/Flight_BSP_3.0_apq8074-le-1-0_r00015.zip -d $(FIRMWARE_UNPACK_DIR)
	touch @

$(DOWNLOAD_DIR):
	mkdir -p $(DOWNLOAD_DIR)

$(TMP_DIR):
	mkdir -p $(TMP_DIR)

$(DOWNLOAD_DIR)/.exists: $(DOWNLOAD_DIR)
	@[ -f $@ ] || touch $@

$(TMP_DIR)/.exists: $(TMP_DIR)
	@[ -f $@ ] || touch $@

$(SKALES):
	@[ -d $@ ] || git clone git://codeaurora.org/quic/kernel/skales $(SKALES)

ifeq ($(BUILD_DEFAULT_KERNEL),1)

ifeq ($(KERNEL_CONFIG),)
$(error KERNEL_CONFIG Undefined)
endif

$(EAGLE_KERNEL):
	@git clone -n git://git.linaro.org/landing-teams/working/qualcomm/kernel.git $@
	@(cd $@ && git checkout $(KERNEL_VERSION))

# Make the Eaglec kernel
$(IMAGE) $(DTS): $(EAGLE_KERNEL) $(KERNEL_CONFIG)
	@(cd $(EAGLE_KERNEL) && git checkout $(KERNEL_VERSION))
	@(cp $(KERNEL_CONFIG) $(EAGLE_KERNEL)/.config)
	@(cd $(EAGLE_KERNEL) && ARCH=arm64 make oldconfig)
	@(cd $(EAGLE_KERNEL) && CROSS_COMPILE=aarch64-linux-gnu- ARCH=arm make -j4 Image dtbs)
endif

# Required for dtbTool and mkbootimg
PATH:=$(SKALES):$(PATH)

# Firmware for EAGLE
$(FIRMWARE_ZIP): 
	@echo
	@echo "********************************************************************************************"
	@echo "* YOU NEED TO DOWNLOAD THE Snapdragon Flight BSP from Intrinsyc"
	@echo "*"
	@echo "* Paste the following link in your browser:"
	@echo "*"
	@echo "*    http://support.intrinsyc.com/attachments/download/428/Flight_BSP_3.0_apq8074-le-1-0_r00015.zip
	@echo "*"
	@echo "* and after accepting the EULA, save the file to:"
	@echo "*"
	@echo "*    $@"
	@echo "*"
	@echo "* Afterward, retry running make"
	@echo "*"
	@echo "********************************************************************************************"
	@echo
	@false

$(TMP_DIR)/dt.img: $(TMP_DIR) $(DTB) $(SKALES)
	cp $(DTB) $(TMP_DIR)
	@dtbTool -o $@ -s 2048 $(TMP_DIR)

$(BOOT_IMG): $(IMAGE) $(INITRD) $(TMP_DIR)/dt.img $(SKALES)
	@mkbootimg --kernel $(IMAGE) \
          --ramdisk $(INITRD) \
          --output $(BOOT_IMG) \
          --dt $(TMP_DIR)/dt.img \
          --pagesize 2048 \
          --base 0x80000000 \
          --cmdline "root=/dev/disk/by-partlabel/rootfs rw rootwait console=tty0 console=ttyMSM0,115200n8"
	@echo "Built boot image: $@"

flash-bootimg: $(BOOT_IMG)
	sudo fastboot flash boot $<

flash-rootimg: $(ROOTFS_IMG)
	sudo fastboot flash rootfs $<

