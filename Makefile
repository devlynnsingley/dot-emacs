## -*- mode: makefile-gmake -*-

EMACS	    = emacs
EMACS_BATCH = $(EMACS) -Q -batch

TARGET = $(patsubst %.el,%.elc,init.el)

DIRS    = lisp
SUBDIRS = $(shell find $(DIRS) -maxdepth 2	\
		       ! -name .git		\
		       ! -name doc		\
		       ! -name test		\
		       ! -name tests		\
		       ! -name obsolete		\
		       -type d -print)

MY_LOADPATH = -L . $(patsubst %,-L %, $(SUBDIRS))
BATCH_LOAD  = $(EMACS_BATCH) $(MY_LOADPATH)

.PHONY: test build clean

# Main rule
all: init.elc

# Generate lisp and compile it
init.el: init.org
	@$(BATCH_LOAD) -L $(HOME)/.emacs.d/lisp/org-mode/lisp \
		--eval "(require 'org)" \
		--eval "(org-babel-load-file \"init.org\")"
	@chmod ugo-w $@

compile:
	@BATCH_LOAD="$(BATCH_LOAD)" ./compile-all $(DIRS)
	@echo All Emacs Lisp files have been compiled.

init.elc: init.el

%.elc: %.el
	@echo Compiling file $<
	@$(BATCH_LOAD) -f batch-byte-compile $<
	@chmod ugo-w $@

speed:
	time emacs -L . -l init --batch --eval "(message \"Hello, world\!\")"

slow:
	time emacs -L . -l init --debug-init --batch --eval "(message \"Hello, world\!\")"

clean:
	rm -f init.el *.elc *~ settings.el

### Makefile ends here
