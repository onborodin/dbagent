#
# $Id: Makefile.am 633 2017-04-15 13:51:07Z ziggi $
#
AUTOMAKE_OPTIONS = foreign no-dependencies no-installinfo

EXTRA_DIST = \
	LICENSE README.md

install-data-hook:
if FREEBSD_OS
	chmod a+x $(DESTDIR)/${etcdir}/rc.d/dbagent
endif
	$(INSTALL) -d -m 750 -o $(APP_USER) -g $(APP_GROUP) $(DESTDIR)$(APP_LOGDIR)
	$(INSTALL) -d -m 750 -o $(APP_USER) -g $(APP_GROUP) $(DESTDIR)$(APP_RUNDIR)
	for data in $(nobase_conf_DATA);do \
	  chmod 0644 $(DESTDIR)$(APP_CONFDIR)/$$data; \
	done

if FREEBSD_OS
etcdir = @prefix@/etc
nobase_etc_SCRIPTS = rc.d/dbagent
endif

if LINUX_OS
if SYSTEMD
systemddir = /lib/systemd/system
nobase_systemd_DATA = dbagent.service
endif
etcdir = @sysconfdir@
nobase_etc_SCRIPTS = init.d/dbagent
endif

sbin_SCRIPTS = dbagent

confdir = @app_confdir@
dist_conf_DATA = \
	dbagent.pw.example \
	dbagent.crt.example \
	dbagent.conf.example \
	dbagent.key.example

clean-local:
	rm -f dbagent

#EOF
