# Purpose: Install/Uninstall `_utils` to/from system path
# Author : Anh K. Huynh
# License: GPL v2
# Note   : This is a work-around while waiting for a dedicated package

exports = $(shell grep '^:export ' lib/*.sh -h | awk '{print $$2}')

default:
	@echo $(exports)
	@echo >&2 "Available sections:"
	@echo >&2 "  install   : To install script 'run.sh' to your system path '/usr/bin/'"
	@echo >&2 "  uninstall : Remove this scripts from your system"

install: run.sh.out
	@install -v -m755 run.sh.out /usr/bin/s-run
	@for P in $(exports); do \
		ln -sv /usr/bin/s-run /usr/bin/$$P ; \
	done

run.sh.out: run2.sh ./bin/compile.sh ./lib/*.sh
	@echo >&2 ":: Generating $(@)..."
	@./bin/compile.sh > $(@)

uninstall:
	@for P in $(exports); do \
		rm -fv /usr/bin/$$P ; \
	done

clean:
	@rm -f run.sh.out
