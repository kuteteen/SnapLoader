TARGET = iphone:11.2:8.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Injectbook
Injectbook_FILES = Tweak.xm

include $(THEOS_MAKE_PATH)/tweak.mk
