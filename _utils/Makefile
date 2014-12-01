# Purpose: Install/Uninstall `_utils` to/from system path
# Author : Anh K. Huynh
# License: GPL v2
# Note   : This is a work-around while waiting for a dedicated package

SYMBOLS = $(shell grep '^:export ' lib/*.sh -h | awk '{print $$2}')
PREFIX ?= /usr/

default:
	@echo >&2 "Available sections:"
	@echo >&2 "  install   : To install script 'run.sh' to your system path '$(PREFIX)/bin/'"
	@echo >&2 "  uninstall : Remove this scripts from your system"

install: run.sh.out
	@install -v -m755 run.sh.out $(PREFIX)/bin/s-run
	@cd $(PREFIX)/bin \
	&& for P in $(SYMBOLS); do \
		ln -sv s-run $$P ; \
	done

run.sh.out: ./bin/compile.sh ./lib/*.sh ./lib/*.txt
	@echo >&2 ":: Generating $(@)..."
	@./bin/compile.sh > $(@)
	@bash -n $(@)

uninstall:
	@find $(PREFIX)/bin/ -type l -ilname "*s-run" \
		-exec rm -fv {} \;
	@rm -fv $(PREFIX)/bin/s-run

clean:
	@rm -f run.sh.out
