#!/bin/sh

# Rockchip's usbdevice helper prepares the Microsoft OS descriptor metadata,
# but only enables it for MTP. FunctionFS supplies ADB's WINUSB descriptors,
# so enable the configfs entry after adbd has opened ep0 and before binding
# the gadget to the UDC.
adb_post_prepare_hook()
{
	[ -e "$USB_GADGET_DIR/os_desc/use" ] || return 0
	usb_write "$USB_GADGET_DIR/os_desc/use" 1
}

adb_post_stop_hook()
{
	[ -e "$USB_GADGET_DIR/os_desc/use" ] || return 0
	usb_try_write "$USB_GADGET_DIR/os_desc/use" 0
}
