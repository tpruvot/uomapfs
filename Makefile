#
# Make file for compiling uomapfs
#
# (C) Copyright 2010
# Texas Instruments, <www.ti.com>
# Nishanth Menon <nm@ti.com>
#
# This program is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation version 2.
#
# This program is distributed .as is. WITHOUT ANY WARRANTY of any kind,
# whether express or implied; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston,
# MA 02111-1307 USA

# Handle verbose
ifeq ("$(origin V)", "command line")
  VERBOSE = $(V)
endif
ifndef VERBOSE
  VERBOSE = 0
endif
Q := $(if $(VERBOSE:1=),@)

# Our default directories
SCRIPT_DIR := scripts
CONFIG_DIR := configs
BUSYBOX := busybox
ETC_SCRIPTS :=$(CONFIG_DIR)/etc

# Our standard scripts
MAKECONFIG := $(SCRIPT_DIR)/make.config
CPSHLIBS := $(SCRIPT_DIR)/cpshlib
GETVAR := $(SCRIPT_DIR)/config.var
PWD := $(shell pwd)

-include .config

target_fs_dir ?= $(PWD)/target/rootfs
target_boot_files_dir ?= $(PWD)/target/boot
host_binaries ?= $(PWD)/bin
host_utils ?= omap-u-boot-utils

kexec_utils ?= kexec-tools

ifeq ("$(busybox_defconfig_file)", "")
  busybox_defconfig_file := $(PWD)/$(CONFIG_DIR)/busybox_generic.config
endif
# Phony rules
.PHONY: all distclean clean .config bootloader bootloader_defconf fs git kexec my_kexec

.EXPORT_ALL_VARIABLES:

all: git .config fs kernel utils kexec
	$(Q)$(MAKE) bootloader

distclean:
ifneq ("$(bootloader)", "")
	$(Q)$(MAKE) -C $(bootloader) distclean
endif
ifneq ("$(kernel)", "")
	$(Q)$(MAKE) -C $(kernel) distclean
endif
ifneq ("$(BUSYBOX)", "")
	$(Q)$(MAKE) -C $(BUSYBOX) distclean
endif
ifneq ("$(kexec_build)", "")
	$(Q)$(MAKE) -C $(kexec_utils) distclean
endif
	$(Q)$(MAKE) -C$(host_utils) distclean
	$(Q)rm -rf .config $(target_fs_dir) $(target_boot_files_dir) \
		$(host_binaries) target

git:
	$(Q)git submodule status|grep '^-' && git submodule init && \
		git submodule update || echo 'nothin to update'

bootloader: git .config $(bootloader)/$(bootloader_image_location)
	$(Q)install -d $(target_boot_files_dir)
	$(Q)install $(bootloader)/$(bootloader_image_location) \
		$(target_boot_files_dir)

$(bootloader)/$(bootloader_image_location): $(bootloader)/include/config.h
	$(Q)$(MAKE) -C $(bootloader) $(bootloader_image)

$(bootloader)/include/config.h: .config
	$(Q)$(MAKE) -C $(bootloader) $(bootloader_defconfig)

$(kexec_utils)/configure:
	$(Q)cd $(kexec_utils) && \
	$(Q)./bootstrap

$(kexec_utils)/Makefile: $(kexec_utils)/configure
	$(Q)cd $(kexec_utils) && \
	$(Q)./configure --build=arm --host=\$(kexec_mach) \
		       --prefix=$(target_fs_dir)

my_kexec: git .config fs $(kexec_utils)/Makefile
	$(Q)$(MAKE) -C $(kexec_utils)
	$(Q)$(MAKE) -C $(kexec_utils) install
	$(Q)$(CPSHLIBS) $(target_fs_dir) $(target_fs_dir)/lib kexec kdump

kexec: .config
	if [ "$(kexec_build)" = "yes" ]; then \
		$(Q)$(MAKE) my_kexec;\
	fi
	
fs: git .config $(BUSYBOX)/busybox busymkdir
	$(Q)fakeroot $(MAKE) -C$(BUSYBOX) CONFIG_PREFIX=$(target_fs_dir) install
	$(Q)$(CPSHLIBS) $(target_fs_dir) $(target_fs_dir)/lib busybox
	$(Q)cp -rf $(PWD)/$(ETC_SCRIPTS)/* $(target_fs_dir)/etc/

busymkdir: .config
	for d in lib etc dev dbg proc sys var/log; do \
		$(Q)install -d $(target_fs_dir)/$$d;\
	done

$(BUSYBOX)/busybox: .config $(BUSYBOX)/.config
	$(Q)$(MAKE) -C $(BUSYBOX)

$(BUSYBOX)/.config: .config git
	$(Q)cp $(CONFIG_DIR)/$(busybox_defconfig_file) $(BUSYBOX)/.config
	$(Q)$(MAKE) -C $(BUSYBOX) oldconfig

mykboot: $(kernel)/$(kernel_image_location) utils
	$(Q)$(MAKE) -C $(kernel) bzImage && \
	$(Q)install $(kernel)/`dirname $(kernel_image_location)`/zImage \
		$(target_boot_files_dir) && \
	$(Q)$(host_binaries)/tagger -c \
		$(CONFIG_DIR)/$(kernel_generatetag_conf_file) \
		-f  $(target_boot_files_dir)/zImage && \
	$(Q)$(host_binaries)/gpsign -c \
		$(CONFIG_DIR)/$(kernel_generatetag_conf_file) \
		-f  $(target_boot_files_dir)/zImage.tag 

kernel: git fs .config $(kernel)/$(kernel_image_location)
	$(Q)$(MAKE) -C$(kernel) INSTALL_MOD_STRIP=1 \
	INSTALL_MOD_PATH=$(target_fs_dir) modules_install
	$(Q)install -d $(target_boot_files_dir)
	$(Q)install $(kernel)/$(kernel_image_location) $(target_boot_files_dir)
	if [ "$(kernel_generatetag_boot)" = "yes" ]; then \
		$(Q)$(MAKE) mykboot; \
	fi

$(kernel)/$(kernel_image_location): .config $(kernel)/.config
	$(Q)$(MAKE) -C $(kernel) $(kernel_image)
	$(Q)$(MAKE) -C $(kernel) modules

$(kernel)/.config: .config git
	if [ -f "$(CONFIG_DIR)/$(kernel_defconfig)" ]; then \
		cp $(CONFIG_DIR)/$(kernel_defconfig) $(kernel)/.config && \
		$(Q)$(MAKE) -C $(kernel) oldconfig; \
	else \
	$(Q)$(MAKE) -C $(kernel) $(kernel_defconfig); \
	fi

%config: git
	$(Q)$(MAKECONFIG) $(if $(VERBOSE:0=),-v) -d $(CONFIG_DIR) -c $@

utils: git
	$(Q) install -d $(host_binaries)
	$(Q) $(MAKE) -C $(host_utils) all usb
	$(Q) install $(host_utils)/pusb  $(host_utils)/pserial \
		$(host_utils)/gpsign  $(host_utils)/ukermit  $(host_utils)/ucmd\
		$(host_utils)/tagger $(host_binaries) 
