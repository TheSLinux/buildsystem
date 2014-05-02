# Purpose: Install/Uninstall `_utils` to/from system path
# Author : Anh K. Huynh
# License: GPL v2
# Note   : This is a work-around while waiting for a dedicated package

default:
	@echo >&2 "Available sections:"
	@echo >&2 "  install   : To install script 'run.sh' to your system path '/usr/bin/'"
	@echo >&2 "  uninstall : Remove this scripts from your system"

install: run.sh.out
	@install -v -m755 run.sh.out /usr/bin/s-run
	@ln -sv /usr/bin/s-run /usr/bin/s-makepkg
	@ln -sv /usr/bin/s-run /usr/bin/s-import-package
	@ln -sv /usr/bin/s-run /usr/bin/start
	@ln -sv /usr/bin/s-run /usr/bin/stop
	@ln -sv /usr/bin/s-run /usr/bin/status

run.sh.out: run2.sh ./lib/*.sh
	@echo >&2 ":: Generating $(@)..."
	@cat run2.sh > $(@)
	@for f in ./lib/*.sh; do \
		echo >&2 "- processing $$f ..." ; \
		echo "" >> $(@) ; \
		echo "# Source file = $$f" >> $(@) ; \
		echo "" >> $(@) ; \
		cat $$f >> $(@) ; \
	done

uninstall:
	@rm -fv /usr/bin/s-run
	@rm -fv /usr/bin/s-makepkg
	@rm -fv /usr/bin/s-import-package
	@rm -fv /usr/bin/stop
	@rm -fv /usr/bin/start
	@rm -fv /usr/bin/status

clean:
	@rm -f run.sh.out
