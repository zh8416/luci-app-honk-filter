# SPDX-License-Identifier: GPL-3.0-only
#
# luci-app-honk-filter — native ad-block & DNS routing management for Honk.
# Fork of kenzok8/openwrt-honk by zh8416.
#
# This package adds two Honk-style LuCI pages (AdBlock, DNS) that write rules
# directly into Honk's own config.dae. It intentionally does NOT install or
# depend on AdGuardHome / mosdns: filtering happens in the Honk core data plane.

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-honk-filter
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

PKG_LICENSE:=GPL-3.0-only
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=zh8416

PKG_BUILD_DEPENDS:=luci-base/host

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-honk-filter
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=LuCI native AdBlock & DNS routing for Honk
  DEPENDS:=+honk +luci-app-honk +rpcd +luci-base +jsonfilter +cgi-io +wget-ssl
  CONFLICTS:=luci-app-adguardhome
  PKGARCH:=all
  URL:=https://github.com/zh8416/luci-app-honk-filter
  MAINTAINER:=zh8416
endef

define Package/luci-app-honk-filter/description
  Honk-style LuCI pages that manage ad-block rule sources (offline package /
  online URL with auto-update) and DNS routing by writing Honk native config.
  No AdGuardHome, no mosdns, no extra DNS layer.
endef

define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
endef

define Build/Compile
endef

define Package/luci-app-honk-filter/install
	$(INSTALL_DIR) $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./root/usr/libexec/rpcd/honk-filter $(1)/usr/libexec/rpcd/honk-filter

	$(INSTALL_DIR) $(1)/usr/share/honk-filter
	$(INSTALL_BIN) ./root/usr/share/honk-filter/filter.sh $(1)/usr/share/honk-filter/filter.sh
	$(INSTALL_BIN) ./root/usr/share/honk-filter/update.sh $(1)/usr/share/honk-filter/update.sh
	$(INSTALL_BIN) ./root/usr/share/honk-filter/cron.sh $(1)/usr/share/honk-filter/cron.sh

	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) ./root/usr/share/luci/menu.d/luci-app-honk-filter.json $(1)/usr/share/luci/menu.d/luci-app-honk-filter.json

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-honk-filter.json $(1)/usr/share/rpcd/acl.d/luci-app-honk-filter.json

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./root/etc/config/honk-filter $(1)/etc/config/honk-filter

	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) ./root/etc/uci-defaults/90-honk-filter $(1)/etc/uci-defaults/90-honk-filter

	$(INSTALL_DIR) $(1)/www/luci-static/resources/view/honk-filter
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/honk-filter/*.js $(1)/www/luci-static/resources/view/honk-filter/
	$(INSTALL_DATA) ./htdocs/luci-static/resources/view/honk-filter/*.css $(1)/www/luci-static/resources/view/honk-filter/
endef

define Package/luci-app-honk-filter/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	[ -x /etc/uci-defaults/90-honk-filter ] && /etc/uci-defaults/90-honk-filter
	/etc/init.d/rpcd reload 2>/dev/null
	/etc/init.d/uhttpd restart 2>/dev/null
	exit 0
}
endef

define Package/luci-app-honk-filter/postrm
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || {
	rm -f /tmp/luci-indexcache.*
	rm -rf /tmp/luci-modulecache/
	exit 0
}
endef

$(eval $(call BuildPackage,luci-app-honk-filter))
