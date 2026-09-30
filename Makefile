TARGET := iphone:clang:16.5:16.0
ARCHS := arm64 arm64e
THEOS_PACKAGE_SCHEME ?= rootless
INSTALL_TARGET_PROCESSES := WeChat

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
export TARGET := iphone:clang:16.5:16.0
endif

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := WcSy
WcSy_FILES := tweak/Core/ReplyTypes.m tweak/Core/ContextEngine.m \
  tweak/Core/PrivacyGate.m tweak/Core/RulesProvider.m \
  tweak/Core/RulesDecisionEngine.m tweak/Core/JevDecisionProvider.m \
  tweak/Core/CandidateValidator.m tweak/Core/RemoteGenerationProvider.m \
  tweak/Core/SessionCoordinator.m tweak/Core/MessageCursor.m tweak/Core/DecisionSchema.m \
  tweak/Core/ConversationPolicy.m \
  tweak/WeChatAdapter/WeChatAdapter.m tweak/WeChatAdapter/ChatHooks.xm \
  tweak/Overlay/ReplyOverlay.m tweak/Overlay/SettingsViewController.m
WcSy_CFLAGS := -fobjc-arc -Wall -Wextra -Werror
WcSy_FRAMEWORKS := Foundation UIKit Security
WcSy_LIBRARIES :=
WcSy_LDFLAGS += -Wl,-weak_framework,CydiaSubstrate

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
WcSy_LDFLAGS += -Wl,-rpath,@loader_path/.jbroot/Library/Frameworks \
                -Wl,-rpath,@loader_path/.jbroot/usr/lib
endif

include $(THEOS_MAKE_PATH)/tweak.mk

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
before-package::
	@sed -i '' 's/^Package: .*/Package: com.wcsy.reply.roothide/' $(THEOS_STAGING_DIR)/DEBIAN/control
endif
