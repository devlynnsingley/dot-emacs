ADD_ELPA="(mapc (lambda (d) (when (file-directory-p d) (add-to-list 'load-path d))) (nthcdr 2 (directory-files \"~/.emacs.d/elpa\" t)))"
LOAD_TREEMACS="(progn (require 'treemacs) (require 'treemacs-evil))"

.PHONY: compile clean test

clean:
	rm -f *.elc

compile:
	emacs -Q --batch -L . --eval ${ADD_ELPA} --eval ${LOAD_TREEMACS} -f batch-byte-compile ./*.el

test: clean compile
	emacs -Q --batch -L . --eval ${ADD_ELPA} --eval ${LOAD_TREEMACS} -l treemacs-tests.el -f ert-run-tests-batch-and-exit
