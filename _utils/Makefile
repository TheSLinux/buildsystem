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

run.sh.out: run.sh ./lib/*.sh
	@cp run.sh $(@)
	@grep -qE '^# libraries #' $(@)
	@for __ in ./lib/*.sh; do \
		echo >&2 ":: Adding '$${__}'..."; \
		sed -i -e "/^# libraries #/r $${__}" $(@) ; \
	done

uninstall:
	@rm -fv /usr/bin/s-run
	@rm -fv /usr/bin/s-makepkg
	@rm -fv /usr/bin/s-import-package
