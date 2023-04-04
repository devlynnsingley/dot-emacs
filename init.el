;;; -*- lexical-binding: t; -*-

(ignore-errors
  (message "1: gnus-kill-files-directory: %s" gnus-kill-files-directory))

(defvar dot-emacs-use-eglot nil)
(eval-when-compile
  (defvar gnus-home-directory)
  (defvar gnus-kill-files-directory))

(defconst emacs-start-time (current-time))

(defvar file-name-handler-alist-old file-name-handler-alist)

(setq package-enable-at-startup nil
      file-name-handler-alist nil
      message-log-max 16384
      gc-cons-threshold 402653184
      gc-cons-percentage 0.6
      auto-window-vscroll nil
      gnus-home-directory "~/Messages/Gnus/")

(add-to-list 'load-path "~/.emacs.d/lisp/org-mode/lisp")

(add-hook 'after-init-hook
          #'(lambda ()
              (setq file-name-handler-alist file-name-handler-alist-old
                    gc-cons-threshold 800000
                    gc-cons-percentage 0.1)
              (garbage-collect)) t)

(eval-and-compile
  (defun emacs-path (path)
    (expand-file-name path user-emacs-directory))

  (defun lookup-password (host user port)
    (require 'auth-source)
    (require 'auth-source-pass)
    (let ((auth (auth-source-search :host host :user user :port port)))
      (if auth
          (let ((secretf (plist-get (car auth) :secret)))
            (if secretf
                (funcall secretf)
              (error "Auth entry for %s@%s:%s has no secret!"
                     user host port)))
        (error "No auth entry found for %s@%s:%s" user host port))))

  (defvar saved-window-configuration nil)

  (defun push-window-configuration ()
    (interactive)
    (push (current-window-configuration) saved-window-configuration))

  (defun pop-window-configuration ()
    (interactive)
    (let ((config (pop saved-window-configuration)))
      (if config
          (set-window-configuration config)
        (if (> (length (window-list)) 1)
            (delete-window)
          (bury-buffer)))))

  (defmacro atomic-modify-buffer (&rest body)
    `(let ((buf (current-buffer)))
       (save-window-excursion
         (with-temp-buffer
           (insert-buffer buf)
           ,@body
           (let ((temp-buf (current-buffer))
                 (inhibit-redisplay t))
             (with-current-buffer buf
               (let ((here (point)))
                 (save-excursion
                   (delete-region (point-min) (point-max))
                   (insert-buffer temp-buf))
                 (goto-char here)))))))))

(eval-and-compile
  (defconst emacs-environment (getenv "NIX_MYENV_NAME"))

  (setq load-path
        (append '("~/.emacs.d")
                (delete-dups load-path)
                '("~/.emacs.d/lisp")))

  (defun filter (f args)
    (let (result)
      (dolist (arg args)
        (when (funcall f arg)
          (setq result (cons arg result))))
      (nreverse result)))

  (defun nix-read-environment (name)
    (ignore-errors
      (with-temp-buffer
        (insert-file-contents-literally
         (with-temp-buffer
           (insert-file-contents-literally
            (executable-find (concat "load-env-" name)))
           (and (re-search-forward "^source \\(.+\\)$" nil t)
                (match-string 1))))
        (and (or (re-search-forward "^  nativeBuildInputs=\"\\(.+?\\)\"" nil t)
                 (re-search-forward "^  buildInputs=\"\\(.+?\\)\"" nil t))
             (split-string (match-string 1))))))

  (add-to-list 'load-path "~/.emacs.d/lisp/use-package")
  (require 'use-package)

  (defconst load-path-reject-re "/\\.emacs\\.d/\\(lib\\|site-lisp\\)/"
    "Regexp matching `:load-path' values to be rejected.")

  (defun load-path-handler-override (orig-func name keyword args rest state)
    (if (cl-some (apply-partially #'string-match load-path-reject-re) args)
        (use-package-process-keywords name rest state)
      (let ((body (use-package-process-keywords name rest state)))
        (use-package-concat
         (mapcar #'(lambda (path)
                     `(eval-and-compile (add-to-list 'load-path ,path t)))
                 args)
         body))))

  (advice-add 'use-package-handler/:load-path
              :around #'load-path-handler-override)

  (if init-file-debug
      (setq use-package-verbose t
            use-package-expand-minimally nil
            use-package-compute-statistics t
            debug-on-error t)
    (setq use-package-verbose nil
          use-package-expand-minimally t)))

(eval-and-compile
  (defconst emacs-data-suffix
    (cond ((string= "emacsERC" emacs-environment) "alt")
          ((string-match "emacs2[67]\\(.+\\)$" emacs-environment)
           (match-string 1 emacs-environment))))

  (defconst alternate-emacs (string= emacs-data-suffix "alt"))

  (defconst user-data-directory
    (emacs-path (if emacs-data-suffix
                    (format "data-%s" emacs-data-suffix)
                  "data")))

  (ignore-errors
    (message "2: gnus-kill-files-directory: %s" gnus-kill-files-directory))
  (load (emacs-path "settings"))
  (ignore-errors
    (message "3: gnus-kill-files-directory: %s" gnus-kill-files-directory))

  ;; Note that deferred loading may override some of these changed values.
  ;; This can happen with `savehist', for example.
  (when emacs-data-suffix
    (let ((settings (with-temp-buffer
                      (insert-file-contents (emacs-path "settings.el"))
                      (read (current-buffer)))))
      (pcase-dolist (`(quote (,var ,value . ,_)) (cdr settings))
        (when (and (stringp value)
                   (string-match "/\\.emacs\\.d/data" value))
          (set var (replace-regexp-in-string
                    "/\\.emacs\\.d/data"
                    (format "/.emacs.d/data-%s" emacs-data-suffix)
                    value)))))))

(defvar Info-directory-list
  (mapcar 'expand-file-name
          (append
           (mapcar (apply-partially #'expand-file-name "share/info")
                   (nix-read-environment emacs-environment))
           '("~/.local/share/info"
             "~/.nix-profile/share/info"))))

(setq disabled-command-function nil) ;; enable all commands

(eval-when-compile
  ;; Disable all warnings about obsolete functions here.
  (dolist (sym '(flet lisp-complete-symbol))
    (setplist sym (use-package-plist-delete (symbol-plist sym)
                                            'byte-obsolete-info))))

(use-package alert         :defer t  :load-path "lisp/alert")
(use-package anaphora      :defer t)
(use-package apiwrap       :defer t)
(use-package asoc          :defer t)
(use-package async         :defer t  :load-path "lisp/async")
(use-package button-lock   :defer t)
(use-package ctable        :defer t)
(use-package dash          :defer t)
(use-package deferred      :defer t)
(use-package diminish      :demand t)
(use-package el-mock       :defer t)
(use-package elisp-refs    :defer t)
(use-package epc           :defer t)
(use-package epl           :defer t)
(use-package esxml         :defer t)
(use-package f             :defer t)
(use-package fn            :defer t)
(use-package fringe-helper :defer t)
(use-package fuzzy         :defer t)
(use-package ghub+         :disabled t :defer t)
(use-package ht            :defer t)
(use-package kv            :defer t)
(use-package list-utils    :defer t)
(use-package logito        :defer t)
(use-package loop          :defer t)
(use-package m-buffer      :defer t)
(use-package makey         :defer t)
(use-package marshal       :defer t)
(use-package names         :defer t)
(use-package noflet        :defer t)
(use-package oauth2        :defer t)
(use-package ov            :defer t)
(use-package packed        :defer t)
(use-package parent-mode   :defer t)
(use-package parsebib      :defer t)
(use-package parsec        :defer t)
(use-package peval         :defer t)
(use-package pfuture       :defer t)
(use-package pkg-info      :defer t)
(use-package popup         :defer t)
(use-package popup-pos-tip :defer t)
(use-package popwin        :defer t)
(use-package pos-tip       :defer t)
(use-package request       :defer t)
(use-package rich-minority :defer t)
(use-package s             :defer t)
(use-package simple-httpd  :defer t)
(use-package spinner       :defer t)
(use-package tablist       :defer t)
(use-package uuidgen       :defer t)
(use-package web           :defer t)
(use-package web-server    :defer t)
(use-package websocket     :defer t)
(use-package with-editor   :defer t)
(use-package xml-rpc       :defer t)
(use-package zoutline      :defer t)

(use-package ghub
  :defer t
  :config
  (require 'auth-source-pass)
  (defvar my-ghub-token-cache nil)
  (advice-add
   'ghub--token :around
   #'(lambda (orig-func host username package &optional nocreate forge)
       (or my-ghub-token-cache
           (setq my-ghub-token-cache
                 (funcall orig-func host username package nocreate forge))))))

(define-key input-decode-map [?\C-m] [C-m])

(eval-and-compile
  (mapc #'(lambda (entry)
            (define-prefix-command (cdr entry))
            (bind-key (car entry) (cdr entry)))
        '(("C-,"   . my-ctrl-comma-map)
          ("<C-m>" . my-ctrl-m-map)

          ("C-h e" . my-ctrl-h-e-map)
          ("C-h x" . my-ctrl-h-x-map)

          ("C-c b" . my-ctrl-c-b-map)
          ("C-c e" . my-ctrl-c-e-map)
          ("C-c m" . my-ctrl-c-m-map)
          ("C-c n" . my-ctrl-c-m-map)
          ("C-c w" . my-ctrl-c-w-map)
          ("C-c y" . my-ctrl-c-y-map)
          ("C-c H" . my-ctrl-c-H-map)
          ("C-c N" . my-ctrl-c-N-map)
          ("C-c (" . my-ctrl-c-open-paren-map)
          ("C-c -" . my-ctrl-c-minus-map)
          ("C-c =" . my-ctrl-c-equals-map)
          ("C-c ." . my-ctrl-c-r-map)
          )))

(use-package abbrev
  :defer 5
  :diminish
  :hook
  ((text-mode prog-mode erc-mode LaTeX-mode) . abbrev-mode)
  (expand-load
   . (lambda ()
       (add-hook 'expand-expand-hook #'indent-according-to-mode)
       (add-hook 'expand-jump-hook #'indent-according-to-mode)))
  :config
  (if (file-exists-p abbrev-file-name)
      (quietly-read-abbrev-file)))

(use-package ace-isearch
  :disabled t
  :config
  (global-ace-isearch-mode +1)
  (define-key isearch-mode-map (kbd "C-'") 'ace-isearch-jump-during-isearch)
  :custom
  (ace-isearch-input-length 7)
  (ace-isearch-jump-delay 0.25)
  (ace-isearch-function 'avy-goto-char)
  (ace-isearch-use-jump 'printing-char))

(use-package ace-jump-mode
  :defer t)

(use-package ace-link
  :disabled t
  :defer 10
  :bind ("C-c M-o" . ace-link-addr)
  :config
  (ace-link-setup-default)

  (add-hook 'org-mode-hook
            #'(lambda () (bind-key "C-c C-o" #'ace-link-org org-mode-map)))
  (add-hook 'gnus-summary-mode-hook
            #'(lambda () (bind-key "M-o" #'ace-link-gnus gnus-summary-mode-map)))
  (add-hook 'gnus-article-mode-hook
            #'(lambda () (bind-key "M-o" #'ace-link-gnus gnus-article-mode-map)))
  (add-hook 'ert-results-mode-hook
            #'(lambda () (bind-key "o" #'ace-link-help ert-results-mode-map)))
  (add-hook 'eww-mode-hook
            #'(lambda () (bind-key "f" #'ace-link-eww eww-mode-map))))

(use-package ace-mc
  :bind (("<C-m> h"   . ace-mc-add-multiple-cursors)
         ("<C-m> M-h" . ace-mc-add-single-cursor)))

(use-package ace-window
  :bind* ("<C-return>" . ace-window))

(use-package adoc-mode
  :mode "\\.adoc\\'"
  :config
  (add-hook 'adoc-mode-hook
            #'(lambda ()
                (auto-fill-mode 1)
                ;; (visual-line-mode 1)
                ;; (visual-fill-column-mode 1)
                )))

(use-package agda-input
  :demand t
  :config
  (setq-default default-input-method "Agda")
  ;; (dolist (hook '(minibuffer-setup-hook
  ;;                 fundamental-mode-hook
  ;;                 text-mode-hook
  ;;                 prog-mode-hook))
  ;;   (add-hook hook #'(lambda () (set-input-method "Agda"))))
  )

(use-package agda2-mode
  ;; This declaration depends on the load-path established by agda-input.
  :mode ("\\.agda\\'" "\\.lagda.md\\'")
  :bind (:map agda2-mode-map
              ("C-c C-i" . agda2-insert-helper-function))
  :preface
  (defun agda2-insert-helper-function (&optional prefix)
    (interactive "P")
    (let ((func-def (with-current-buffer "*Agda information*"
                      (buffer-string))))
      (save-excursion
        (forward-paragraph)
        (let ((name (car (split-string func-def " "))))
          (insert "  where\n    " func-def "    " name " x = ?\n")))))
  :init
  (advice-add 'agda2-mode
              :before #'direnv-update-directory-environment))

(use-package aggressive-indent
  :diminish
  :hook (emacs-lisp-mode . aggressive-indent-mode))

(use-package align
  :bind (("M-["   . align-code)
         ("C-c [" . align-regexp))
  :commands align
  :preface
  (defun align-code (beg end &optional arg)
    (interactive "rP")
    (if (null arg)
        (align beg end)
      (let ((end-mark (copy-marker end)))
        (indent-region beg end-mark nil)
        (align beg end-mark)))))

(use-package anki-editor
  :commands anki-editor-submit)

(use-package aria2
  :commands aria2-downloads-list)

(use-package ascii
  :bind ("C-c e A" . ascii-toggle)
  :commands (ascii-on ascii-off)
  :preface
  (defun ascii-toggle ()
    (interactive)
    (if ascii-display
        (ascii-off)
      (ascii-on))))

(use-package auctex
  :demand t
  :no-require t
  :mode ("\\.tex\\'" . TeX-latex-mode)
  :config
  (defun latex-help-get-cmd-alist ()    ;corrected version:
    "Scoop up the commands in the index of the latex info manual.
   The values are saved in `latex-help-cmd-alist' for speed."
    ;; mm, does it contain any cached entries
    (if (not (assoc "\\begin" latex-help-cmd-alist))
        (save-window-excursion
          (setq latex-help-cmd-alist nil)
          (Info-goto-node (concat latex-help-file "Command Index"))
          (goto-char (point-max))
          (while (re-search-backward "^\\* \\(.+\\): *\\(.+\\)\\." nil t)
            (let ((key (buffer-substring (match-beginning 1) (match-end 1)))
                  (value (buffer-substring (match-beginning 2)
                                           (match-end 2))))
              (add-to-list 'latex-help-cmd-alist (cons key value))))))
    latex-help-cmd-alist)

  (add-hook 'TeX-after-compilation-finished-functions
            #'TeX-revert-document-buffer))

(use-package auth-source-pass
  :config
  (auth-source-pass-enable)

  (defvar auth-source-pass--cache (make-hash-table :test #'equal))

  (defun auth-source-pass--reset-cache ()
    (setq auth-source-pass--cache (make-hash-table :test #'equal)))

  (defun auth-source-pass--read-entry (entry)
    "Return a string with the file content of ENTRY."
    (run-at-time 45 nil #'auth-source-pass--reset-cache)
    (let ((cached (gethash entry auth-source-pass--cache)))
      (or cached
          (puthash
           entry
           (with-temp-buffer
             (insert-file-contents (expand-file-name
                                    (format "%s.gpg" entry)
                                    (getenv "PASSWORD_STORE_DIR")))
             (buffer-substring-no-properties (point-min) (point-max)))
           auth-source-pass--cache))))

  (defun auth-source-pass-entries ()
    "Return a list of all password store entries."
    (let ((store-dir (getenv "PASSWORD_STORE_DIR")))
      (mapcar
       (lambda (file) (file-name-sans-extension (file-relative-name file store-dir)))
       (directory-files-recursively store-dir "\.gpg$")))))

(use-package auto-yasnippet
  :after yasnippet
  :bind (("C-c y a" . aya-create)
         ("C-c y e" . aya-expand)
         ("C-c y o" . aya-open-line)))

(use-package avy
  :bind* ("C-." . avy-goto-char-timer)
  :config
  (avy-setup-default))

(use-package avy-zap
  :bind (("M-z" . avy-zap-to-char-dwim)
         ("M-Z" . avy-zap-up-to-char-dwim)))

(use-package backup-each-save
  :commands backup-each-save
  :preface
  (defun my-make-backup-file-name (file)
    (make-backup-file-name-1 (expand-file-name (file-truename file))))

  (defun backup-each-save-filter (filename)
    (not (string-match
          (concat "\\(^/tmp\\|\\.emacs\\.d/data\\(-alt\\)?/"
                  "\\|\\.newsrc\\(\\.eld\\)?\\|"
                  "\\(archive/sent/\\|recentf\\`\\)\\)")
          filename)))

  (defun my-dont-backup-files-p (filename)
    (unless (string-match filename "\\(archive/sent/\\|recentf\\`\\)")
      (normal-backup-enable-predicate filename)))

  :hook after-save
  :config
  (setq backup-each-save-filter-function 'backup-each-save-filter
        backup-enable-predicate 'my-dont-backup-files-p))

(use-package backup-walker
  :commands backup-walker-start)

(use-package beacon
  :diminish
  :commands beacon-mode)

(use-package biblio
  :commands biblio-lookup)

(use-package bm
  :unless alternate-emacs
  :bind (("C-c b b" . bm-toggle)
         ("C-c b n" . bm-next)
         ("C-c b p" . bm-previous))
  :commands (bm-repository-load
             bm-buffer-save
             bm-buffer-save-all
             bm-buffer-restore)
  :init
  (add-hook 'after-init-hook #'bm-repository-load)
  (add-hook 'find-file-hooks #'bm-buffer-restore)
  (add-hook 'after-revert-hook #'bm-buffer-restore)
  (add-hook 'kill-buffer-hook #'bm-buffer-save)
  (add-hook 'after-save-hook #'bm-buffer-save)
  (add-hook 'vc-before-checkin-hook #'bm-buffer-save)
  (add-hook 'kill-emacs-hook #'(lambda nil
                                 (bm-buffer-save-all)
                                 (bm-repository-save))))

(use-package bookmark+
  :after bookmark
  :bind ("M-B" . bookmark-bmenu-list)
  :commands bmkp-jump-dired)

(use-package boogie-friends)

(use-package browse-at-remote
  :bind ("C-c B" . browse-at-remote))

(use-package browse-kill-ring
  :defer 5
  :commands browse-kill-ring)

(use-package browse-kill-ring+
  :after browse-kill-ring
  :config (browse-kill-ring-default-keybindings))

(use-package bytecomp-simplify
  :defer 15)

(use-package c-includes
  :disabled t
  :commands c-includes
  :after cc-mode
  :bind (:map c-mode-base-map
              ("C-c C-i"  . c-includes-current-file)))

(use-package calc
  :defer t
  :custom
  (math-additional-units
   '((GiB "1024 * MiB" "Giga Byte")
     (MiB "1024 * KiB" "Mega Byte")
     (KiB "1024 * B" "Kilo Byte")
     (B nil "Byte")
     (Gib "1024 * Mib" "Giga Bit")
     (Mib "1024 * Kib" "Mega Bit")
     (Kib "1024 * b" "Kilo Bit")
     (b "B / 8" "Bit")))
  :config
  (setq math-units-table nil))

(use-package cargo
  :commands cargo-minor-mode
  :bind (:map cargo-mode-map
              ("C-c C-c C-y" . cargo-process-clippy))
  :config
  (defadvice cargo-process-clippy
      (around my-cargo-process-clippy activate)
    (let ((cargo-process--command-flags
           (concat cargo-process--command-flags
                   "--all-targets "
                   "--all-features "
                   "-- "
                   "-D warnings "
                   "-D clippy::all "
                   "-D clippy::mem_forget "
                   "-C debug-assertions=off")))
      ad-do-it))

  (defun cargo-fix ()
    (interactive)
    (async-shell-command
     (concat "cargo fix"
             " --clippy --tests --benches --allow-dirty --allow-staged"))))

(use-package cc-mode
  :mode (("\\.h\\(h?\\|xx\\|pp\\)\\'" . c++-mode)
         ("\\.m\\'" . c-mode)
         ("\\.mm\\'" . c++-mode))
  :bind (:map c++-mode-map
              ("<" . self-insert-command)
              (">" . self-insert-command))
  :bind (:map c-mode-base-map
              ("#" . self-insert-command)
              ("{" . self-insert-command)
              ("}" . self-insert-command)
              ("/" . self-insert-command)
              ("*" . self-insert-command)
              (";" . self-insert-command)
              ("," . self-insert-command)
              (":" . self-insert-command)
              ("(" . self-insert-command)
              (")" . self-insert-command)
              ("<return>" . newline-and-indent)
              ("M-q" . c-fill-paragraph)
              ("M-j"))
  :preface
  (defun my-c-mode-common-hook ()
    (require 'flycheck)
    ;; (flycheck-define-checker
    ;;  c++-ledger
    ;;  "A C++ syntax checker for the Ledger project specifically."
    ;;  :command ("ninja"
    ;;            "-C"
    ;;            (eval (expand-file-name "~/Products/ledger"))
    ;;            (eval (concat "src/CMakeFiles/libledger.dir/"
    ;;                          (file-name-nondirectory (buffer-file-name))
    ;;                          ".o")))
    ;;  :error-patterns
    ;;  ((error line-start
    ;;          (message "In file included from") " " (or "<stdin>" (file-name))
    ;;          ":" line ":" line-end)
    ;;   (info line-start (or "<stdin>" (file-name)) ":" line ":" column
    ;;         ": note: " (optional (message)) line-end)
    ;;   (warning line-start (or "<stdin>" (file-name)) ":" line ":" column
    ;;            ": warning: " (optional (message)) line-end)
    ;;   (error line-start (or "<stdin>" (file-name)) ":" line ":" column
    ;;          ": " (or "fatal error" "error") ": " (optional (message)) line-end))
    ;;  :error-filter
    ;;  (lambda (errors)
    ;;    (let ((errors (flycheck-sanitize-errors errors)))
    ;;      (dolist (err errors)
    ;;        ;; Clang will output empty messages for #error/#warning pragmas
    ;;        ;; without messages. We fill these empty errors with a dummy message
    ;;        ;; to get them past our error filtering
    ;;        (setf (flycheck-error-message err)
    ;;              (or (flycheck-error-message err) "no message")))
    ;;      (flycheck-fold-include-levels errors "In file included from")))
    ;;  :modes c++-mode
    ;;  :next-checkers ((warning . c/c++-cppcheck)))

    (flycheck-mode 1)
    ;; (flycheck-select-checker 'c++-ledger)
    (setq-local flycheck-check-syntax-automatically nil)
    (setq-local flycheck-highlighting-mode nil)

    (set (make-local-variable 'parens-require-spaces) nil)

    (let ((bufname (buffer-file-name)))
      (when bufname
        (cond
         ((string-match "/ledger/" bufname)
          (c-set-style "ledger"))
         ((string-match "/edg/" bufname)
          (c-set-style "edg"))
         (t
          (c-set-style "clang")))))

    (font-lock-add-keywords
     'c++-mode '(("\\<\\(assert\\|DEBUG\\)(" 1 font-lock-warning-face t))))

  :hook (c-mode-common . my-c-mode-common-hook)
  :config
  (add-to-list
   'c-style-alist
   '("edg"
     (indent-tabs-mode . nil)
     (c-basic-offset . 2)
     (c-comment-only-line-offset . (0 . 0))
     (c-hanging-braces-alist
      . ((substatement-open before after)
         (arglist-cont-nonempty)))
     (c-offsets-alist
      . ((statement-block-intro . +)
         (knr-argdecl-intro . 5)
         (substatement-open . 0)
         (substatement-label . 0)
         (label . 0)
         (case-label . +)
         (statement-case-open . 0)
         (statement-cont . +)
         (arglist-intro . +)
         (arglist-close . +)
         (inline-open . 0)
         (brace-list-open . 0)
         (topmost-intro-cont
          . (first c-lineup-topmost-intro-cont
                   c-lineup-gnu-DEFUN-intro-cont))))
     (c-special-indent-hook . c-gnu-impose-minimum)
     (c-block-comment-prefix . "")))

  (add-to-list
   'c-style-alist
   '("ledger"
     (indent-tabs-mode . nil)
     (c-basic-offset . 2)
     (c-comment-only-line-offset . (0 . 0))
     (c-hanging-braces-alist
      . ((substatement-open before after)
         (arglist-cont-nonempty)))
     (c-offsets-alist
      . ((statement-block-intro . +)
         (knr-argdecl-intro . 5)
         (substatement-open . 0)
         (substatement-label . 0)
         (label . 0)
         (case-label . 0)
         (statement-case-open . 0)
         (statement-cont . +)
         (arglist-intro . +)
         (arglist-close . +)
         (inline-open . 0)
         (brace-list-open . 0)
         (topmost-intro-cont
          . (first c-lineup-topmost-intro-cont
                   c-lineup-gnu-DEFUN-intro-cont))))
     (c-special-indent-hook . c-gnu-impose-minimum)
     (c-block-comment-prefix . "")))

  (add-to-list
   'c-style-alist
   '("clang"
     (indent-tabs-mode . nil)
     (c-basic-offset . 2)
     (c-comment-only-line-offset . (0 . 0))
     (c-hanging-braces-alist
      . ((substatement-open before after)
         (arglist-cont-nonempty)))
     (c-offsets-alist
      . ((statement-block-intro . +)
         (knr-argdecl-intro . 5)
         (substatement-open . 0)
         (substatement-label . 0)
         (label . 0)
         (case-label . 0)
         (statement-case-open . 0)
         (statement-cont . +)
         (arglist-intro . +)
         (arglist-close . +)
         (inline-open . 0)
         (brace-list-open . 0)
         (topmost-intro-cont
          . (first c-lineup-topmost-intro-cont
                   c-lineup-gnu-DEFUN-intro-cont))))
     (c-special-indent-hook . c-gnu-impose-minimum)
     (c-block-comment-prefix . ""))))

(use-package centered-cursor-mode
  :commands centered-cursor-mode)

(use-package change-inner
  :bind (("M-i"     . change-inner)
         ("M-o M-o" . change-outer)))

(use-package chess
  :load-path "lisp/chess"
  :commands chess)

(use-package chess-ics
  :after chess
  :commands chess-ics
  :config
  (defun chess ()
    (interactive)
    (chess-ics "freechess.org" 5000 "jwiegley"
               (lookup-password "freechess.org" "jwiegley" 80))))

(use-package circe
  :if alternate-emacs
  :defer t)

(use-package cl-info
  ;; jww (2017-12-10): Need to configure.
  :disabled t)

(use-package cmake-font-lock
  :hook (cmake-mode . cmake-font-lock-activate))

(use-package cmake-mode
  :mode ("CMakeLists.txt" "\\.cmake\\'"))

(use-package col-highlight
  :commands col-highlight-mode)

(use-package color-moccur
  :commands (isearch-moccur isearch-all isearch-moccur-all)
  :bind (("M-s O" . moccur)
         :map isearch-mode-map
         ("M-o" . isearch-moccur)
         ("M-O" . isearch-moccur-all)))

(use-package command-log-mode
  :bind (("C-c e M" . command-log-mode)
         ("C-c e L" . clm/open-command-log-buffer)))

(use-package company
  :defer 5
  :diminish
  :commands (company-mode company-indent-or-complete-common)
  :init
  (dolist (hook '(emacs-lisp-mode-hook
                  c-mode-common-hook))
    (add-hook hook
              #'(lambda ()
                  (local-set-key (kbd "<tab>")
                                 #'company-indent-or-complete-common))))
  :config
  ;; From https://github.com/company-mode/company-mode/issues/87
  ;; See also https://github.com/company-mode/company-mode/issues/123
  (defadvice company-pseudo-tooltip-unless-just-one-frontend
      (around only-show-tooltip-when-invoked activate)
    (when (company-explicit-action-p)
      ad-do-it))

  ;; See http://oremacs.com/2017/12/27/company-numbers/
  (defun ora-company-number ()
    "Forward to `company-complete-number'.

  Unless the number is potentially part of the candidate.
  In that case, insert the number."
    (interactive)
    (let* ((k (this-command-keys))
           (re (concat "^" company-prefix k)))
      (if (cl-find-if (lambda (s) (string-match re s))
                      company-candidates)
          (self-insert-command 1)
        (company-complete-number (string-to-number k)))))

  (let ((map company-active-map))
    (mapc
     (lambda (x)
       (define-key map (format "%d" x) 'ora-company-number))
     (number-sequence 0 9))
    (define-key map " " (lambda ()
                          (interactive)
                          (company-abort)
                          (self-insert-command 1))))

  (defun check-expansion ()
    (save-excursion
      (if (outline-on-heading-p t)
          nil
        (if (looking-at "\\_>") t
          (backward-char 1)
          (if (looking-at "\\.") t
            (backward-char 1)
            (if (looking-at "->") t nil))))))

  (define-key company-mode-map [tab]
    '(menu-item "maybe-company-expand" nil
                :filter (lambda (&optional _)
                          (when (check-expansion)
                            #'company-complete-common))))

  (eval-after-load "coq"
    '(progn
       (defun company-mode/backend-with-yas (backend)
         (if (and (listp backend) (member 'company-yasnippet backend))
             backend
           (append (if (consp backend) backend (list backend))
                   '(:with company-yasnippet))))
       (setq company-backends
             (mapcar #'company-mode/backend-with-yas company-backends))))

  (global-company-mode 1))

(use-package company-auctex
  :after (company latex))

(use-package company-cabal
  :after (company haskell-cabal))

(use-package company-coq
  :after coq
  :commands company-coq-mode
  :bind (:map company-coq-map
              ("M-<return>"))
  :bind (:map coq-mode-map
              ("C-M-h" . company-coq-toggle-definition-overlay)))

(use-package company-elisp
  :after company
  :config
  (push 'company-elisp company-backends))

(setq-local company-backend '(company-elisp))

(use-package company-math
  :defer t)

(use-package company-quickhelp
  :after company
  :bind (:map company-active-map
              ("C-c ?" . company-quickhelp-manual-begin)))

(use-package company-restclient
  :after (company restclient))

(use-package company-rtags
  :disabled t
  :load-path "~/.nix-profile/share/emacs/site-lisp/rtags"
  :after (company rtags)
  :config
  (push 'company-rtags company-backends))

(use-package company-terraform
  :after (company terraform-mode))

(use-package compile
  :no-require
  :bind (("C-c c" . compile)
         ("M-O"   . show-compilation))
  :bind (:map compilation-mode-map
              ("z" . delete-window))
  :preface
  (defun show-compilation ()
    (interactive)
    (let ((it
           (catch 'found
             (dolist (buf (buffer-list))
               (when (string-match "\\*compilation\\*" (buffer-name buf))
                 (throw 'found buf))))))
      (if it
          (display-buffer it)
        (call-interactively 'compile))))

  (defun compilation-ansi-color-process-output ()
    (ansi-color-process-output nil)
    (set (make-local-variable 'comint-last-output-start)
         (point-marker)))

  :hook (compilation-filter . compilation-ansi-color-process-output))

(use-package copy-as-format
  :bind (("C-c w m" . copy-as-format-markdown)
         ("C-c w g" . copy-as-format-slack)
         ("C-c w o" . copy-as-format-org-mode)
         ("C-c w r" . copy-as-format-rst)
         ("C-c w s" . copy-as-format-github)
         ("C-c w w" . copy-as-format))
  :init
  (setq copy-as-format-default "github"))

(use-package coq-lookup
  :bind ("C-h q" . coq-lookup))

(use-package counsel
  :after ivy
  :demand t
  :diminish
  :custom (counsel-find-file-ignore-regexp
           (concat "\\(\\`\\.[^.]\\|"
                   (regexp-opt completion-ignored-extensions)
                   "\\'\\)"))
  :bind (("C-*"     . counsel-org-agenda-headlines)
         ("C-x C-f" . counsel-find-file)
         ("C-c e l" . counsel-find-library)
         ("C-c e q" . counsel-set-variable)
         ("C-h e l" . counsel-find-library)
         ("C-h e u" . counsel-unicode-char)
         ("C-h f"   . counsel-describe-function)
         ("C-x r b" . counsel-bookmark)
         ("M-x"     . counsel-M-x)
         ;; ("M-y"     . counsel-yank-pop)

         ("M-s f" . counsel-file-jump)
         ;; ("M-s g" . counsel-rg)
         ("M-s j" . counsel-dired-jump))
  :commands counsel-minibuffer-history
  :init
  (bind-key "M-r" #'counsel-minibuffer-history minibuffer-local-map)
  :config
  (add-to-list 'ivy-sort-matches-functions-alist
               '(counsel-find-file . ivy--sort-files-by-date))

  (defun counsel-recoll-function (string)
    "Run recoll for STRING."
    (if (< (length string) 3)
        (counsel-more-chars 3)
      (counsel--async-command
       (format "recollq -t -b %s"
               (shell-quote-argument string)))
      nil))

  (defun counsel-recoll (&optional initial-input)
    "Search for a string in the recoll database.
  You'll be given a list of files that match.
  Selecting a file will launch `swiper' for that file.
  INITIAL-INPUT can be given as the initial minibuffer input."
    (interactive)
    (counsel-require-program "recollq")
    (ivy-read "recoll: " 'counsel-recoll-function
              :initial-input initial-input
              :dynamic-collection t
              :history 'counsel-git-grep-history
              :action (lambda (x)
                        (when (string-match "file://\\(.*\\)\\'" x)
                          (let ((file-name (match-string 1 x)))
                            (find-file file-name)
                            (unless (string-match "pdf$" x)
                              (swiper ivy-text)))))
              :unwind #'counsel-delete-process
              :caller 'counsel-recoll)))

(use-package counsel-gtags
  ;; jww (2017-12-10): Need to configure.
  :disabled t
  :after counsel)

(use-package counsel-jq
  :commands counsel-jq)

(use-package counsel-osx-app
  :bind* ("S-M-SPC" . counsel-osx-app)
  :commands counsel-osx-app
  :config
  (setq counsel-osx-app-location
        (list "/Applications"
              "/Applications/Misc"
              "/Applications/Utilities"
              (expand-file-name "~/Applications")
              (expand-file-name "~/.nix-profile/Applications")
              "/Applications/Xcode.app/Contents/Applications")))

(use-package counsel-projectile
  :after (counsel projectile)
  :config
  (counsel-projectile-mode 1))

(use-package counsel-tramp
  :commands counsel-tramp)

(use-package crosshairs
  :bind ("M-o c" . crosshairs-mode))

(use-package crux
  :bind ("C-c e i" . crux-find-user-init-file))

(use-package css-mode
  :mode "\\.css\\'")

(use-package csv-mode
  :mode "\\.csv\\'"
  :config
  (defun csv-remove-commas ()
    (interactive)
    (goto-char (point-min))
    (while (re-search-forward "\"\\([^\"]+\\)\"" nil t)
      (replace-match (replace-regexp-in-string "," "" (match-string 1)))))

  (defun maybe-add (x y)
    (if (equal x "")
        (if (equal y "")
            ""
          y)
      (if (equal y "")
          x
        (format "%0.2f" (+ (string-to-number x) (string-to-number y))))))

  (defun parse-desc (desc)
    (cond
     ((string-match "\\(BOT \\+\\|SOLD -\\)\\([0-9]+\\) \\(.+\\) @\\([0-9.]+\\)\\( .+\\)?" desc)
      (list (match-string 1 desc)
            (match-string 2 desc)
            (match-string 3 desc)
            (match-string 4 desc)
            (match-string 5 desc)))))

  (defun maybe-add-descs (x y)
    (let ((x-info (parse-desc x))
          (y-info (parse-desc y)))
      (and (string= (nth 0 x-info) (nth 0 y-info))
           (string= (nth 2 x-info) (nth 2 y-info))
           (string= (nth 3 x-info) (nth 3 y-info))
           (format "%s%d %s @%s%s"
                   (nth 0 y-info)
                   (+ (string-to-number (nth 1 x-info))
                      (string-to-number (nth 1 y-info)))
                   (nth 2 y-info)
                   (nth 3 y-info)
                   (or (nth 4 y-info) "")))))

  (defun csv-merge-lines ()
    (interactive)
    (goto-char (line-beginning-position))
    (let ((start (point-marker))
          (fields-a (csv--collect-fields (line-end-position))))
      (forward-line 1)
      (let ((fields-b (csv--collect-fields (line-end-position))))
        (when (string= (nth 3 fields-a) (nth 3 fields-b))
          (let ((desc (maybe-add-descs (nth 4 fields-a) (nth 4 fields-b))))
            (when desc
              (delete-region start (line-end-position))
              (setcar (nthcdr 4 fields-b) desc)
              (setcar (nthcdr 5 fields-b)
                      (maybe-add (nth 5 fields-a) (nth 5 fields-b)))
              (setcar (nthcdr 6 fields-b)
                      (maybe-add (nth 6 fields-a) (nth 6 fields-b)))
              (setcar (nthcdr 7 fields-b)
                      (maybe-add (nth 7 fields-a) (nth 7 fields-b)))
              (insert (mapconcat #'identity fields-b ","))
              (forward-char 1)
              (forward-line -1))))))))

(use-package cursor-chg
  :commands change-cursor-mode
  :config
  (change-cursor-mode 1)
  (toggle-cursor-type-when-idle 1))

(use-package cus-edit
  :bind (("C-c o" . customize-option)
         ("C-c O" . customize-group)
         ("C-c F" . customize-face)))

(use-package dafny-mode
  :bind (:map dafny-mode-map
              ("M-n" . flycheck-next-error)
              ("M-p" . flycheck-previous-error)))

(use-package debbugs-gnu
  :disabled t
  :commands (debbugs-gnu debbugs-gnu-search)
  :bind ("C-c #" . gnus-read-ephemeral-emacs-bug-group))

(use-package deadgrep
  :bind ("M-s g" . deadgrep))

(use-package dedicated
  :bind ("C-c W" . dedicated-mode))

(use-package diff-hl
  :commands (diff-hl-mode diff-hl-dired-mode)
  :hook (magit-post-refresh . diff-hl-magit-post-refresh))

(use-package diff-hl-flydiff
  :commands diff-hl-flydiff-mode)

(use-package diff-mode
  :commands diff-mode)

(use-package diffview
  :commands (diffview-current diffview-region diffview-message))

(use-package dired
  :bind ("C-c j" . dired-two-pane)
  :bind (:map dired-mode-map
              ("j"     . dired)
              ("z"     . pop-window-configuration)
              ("e"     . ora-ediff-files)
              ("l"     . dired-up-directory)
              ("q"     . pop-window-configuration)
              ("Y"     . ora-dired-rsync)
              ("M-!"   . shell-command)
              ("<tab>" . dired-next-window)
              ("M-G")
              ("M-s f"))
  :diminish dired-omit-mode
  :hook (dired-mode . dired-hide-details-mode)
  ;; :hook (dired-mode . dired-omit-mode)
  :preface
  (defun dired-two-pane ()
    (interactive)
    (push-window-configuration)
    (let ((here default-directory))
      (delete-other-windows)
      (dired "~/dl")
      (split-window-horizontally)
      (dired here)))

  (defun dired-next-window ()
    (interactive)
    (let ((next (car (cl-remove-if-not #'(lambda (wind)
                                           (with-current-buffer (window-buffer wind)
                                             (eq major-mode 'dired-mode)))
                                       (cdr (window-list))))))
      (when next
        (select-window next))))

  (defvar mark-files-cache (make-hash-table :test #'equal))

  (defun mark-similar-versions (name)
    (let ((pat name))
      (if (string-match "^\\(.+?\\)-[0-9._-]+$" pat)
          (setq pat (match-string 1 pat)))
      (or (gethash pat mark-files-cache)
          (ignore (puthash pat t mark-files-cache)))))

  (defun dired-mark-similar-version ()
    (interactive)
    (setq mark-files-cache (make-hash-table :test #'equal))
    (dired-mark-sexp '(mark-similar-versions name)))

  (defun ora-dired-rsync (dest)
    (interactive
     (list
      (expand-file-name
       (read-file-name "Rsync to: " (dired-dwim-target-directory)))))
    (let ((files (dired-get-marked-files
                  nil current-prefix-arg))
          (tmtxt/rsync-command "rsync -aP "))
      (dolist (file files)
        (setq tmtxt/rsync-command
              (concat tmtxt/rsync-command
                      (shell-quote-argument file)
                      " ")))
      (setq tmtxt/rsync-command
            (concat tmtxt/rsync-command
                    (shell-quote-argument dest)))
      (async-shell-command tmtxt/rsync-command "*rsync*")
      (other-window 1)))

  (defun ora-ediff-files ()
    (interactive)
    (let ((files (dired-get-marked-files))
          (wnd (current-window-configuration)))
      (if (<= (length files) 2)
          (let ((file1 (car files))
                (file2 (if (cdr files)
                           (cadr files)
                         (read-file-name
                          "file: "
                          (dired-dwim-target-directory)))))
            (if (file-newer-than-file-p file1 file2)
                (ediff-files file2 file1)
              (ediff-files file1 file2))
            (add-hook 'ediff-after-quit-hook-internal
                      `(lambda ()
                         (setq ediff-after-quit-hook-internal nil)
                         (set-window-configuration ,wnd))))
        (error "no more than 2 files should be marked"))))

  :config
  (add-hook 'dired-mode-hook
            #'(lambda () (bind-key "M-G" #'switch-to-gnus dired-mode-map))))

(use-package dired-toggle
  :bind ("C-c ~" . dired-toggle)
  :preface
  (defun my-dired-toggle-mode-hook ()
    (interactive)
    (visual-line-mode 1)
    (setq-local visual-line-fringe-indicators '(nil right-curly-arrow))
    (setq-local word-wrap nil))
  :hook (dired-toggle-mode . my-dired-toggle-mode-hook))

(use-package dired-x
  :after dired
  :config
  ;; (defvar dired-omit-regexp-orig (symbol-function 'dired-omit-regexp))

  ;; ;; Omit files that Git would ignore
  ;; (defun dired-omit-regexp ()
  ;;   (let ((file (expand-file-name ".git"))
  ;;         parent-dir)
  ;;     (while (and (not (file-exists-p file))
  ;;                 (progn
  ;;                   (setq parent-dir
  ;;                         (file-name-directory
  ;;                          (directory-file-name
  ;;                           (file-name-directory file))))
  ;;                   ;; Give up if we are already at the root dir.
  ;;                   (not (string= (file-name-directory file)
  ;;                                 parent-dir))))
  ;;       ;; Move up to the parent dir and try again.
  ;;       (setq file (expand-file-name ".git" parent-dir)))
  ;;     ;; If we found a change log in a parent, use that.
  ;;     (if (file-exists-p file)
  ;;         (let ((regexp (funcall dired-omit-regexp-orig))
  ;;               (omitted-files
  ;;                (shell-command-to-string "git clean -d -x -n")))
  ;;           (if (= 0 (length omitted-files))
  ;;               regexp
  ;;             (concat
  ;;              regexp
  ;;              (if (> (length regexp) 0)
  ;;                  "\\|" "")
  ;;              "\\("
  ;;              (mapconcat
  ;;               #'(lambda (str)
  ;;                   (concat
  ;;                    "^"
  ;;                    (regexp-quote
  ;;                     (substring str 13
  ;;                                (if (= ?/ (aref str (1- (length str))))
  ;;                                    (1- (length str))
  ;;                                  nil)))
  ;;                    "$"))
  ;;               (split-string omitted-files "\n" t)
  ;;               "\\|")
  ;;              "\\)")))
  ;;       (funcall dired-omit-regexp-orig))))
  )

(use-package dired+
  :after dired-x
  :config
  (defun dired-do-delete (&optional arg)  ; Bound to `D'
    "Delete all marked (or next ARG) files.
NOTE: This deletes the marked (`*'), not the flagged (`D'), files.

User option `dired-recursive-deletes' controls whether deletion of
non-empty directories is allowed.

ARG is the prefix argument.

As an exception, if ARG is zero then delete the marked files, but with
the behavior specified by option `delete-by-moving-to-trash' flipped."
    (interactive "P")
    (let* ((flip                       (zerop (prefix-numeric-value arg)))
           (delete-by-moving-to-trash  (and (boundp 'delete-by-moving-to-trash)  (if flip
                                                                                     (not delete-by-moving-to-trash)
                                                                                   delete-by-moving-to-trash)))
           (markers                    ()))
      (when flip (setq arg  nil))
      (diredp-internal-do-deletions
       (nreverse
        ;; This can move point if ARG is an integer.
        (dired-map-over-marks (cons (dired-get-filename) (let ((mk  (point-marker)))
                                                           (push mk markers)
                                                           mk))
                              arg))
       arg
       t)          ; Gets ANDed anyway with `delete-by-moving-to-trash'.
      (dolist (mk  markers) (set-marker mk nil))))

  (defun dired-do-flagged-delete (&optional no-msg) ; Bound to `x'
    "In Dired, delete the files flagged for deletion.
NOTE: This deletes flagged, not marked, files.
If arg NO-MSG is non-nil, no message is displayed.

User option `dired-recursive-deletes' controls whether deletion of
non-empty directories is allowed."
    (interactive)
    (let* ((dired-marker-char  dired-del-marker)
           (regexp             (dired-marker-regexp))
           (case-fold-search   nil)
           (markers            ()))
      (if (save-excursion (goto-char (point-min)) (re-search-forward regexp nil t))
          (diredp-internal-do-deletions
           (nreverse
            ;; This cannot move point since last arg is nil.
            (dired-map-over-marks (cons (dired-get-filename) (let ((mk  (point-marker)))
                                                               (push mk markers)
                                                               mk))
                                  nil))
           nil
           'USE-TRASH-CAN)             ; This arg is for Emacs 24+ only.
        (dolist (mk  markers) (set-marker mk nil))
        (unless no-msg (message "(No deletions requested.)"))))))

(use-package dired-rsync
  :after dired+
  :config
  (bind-key "C-c C-r" 'dired-rsync dired-mode-map))

(use-package direnv
  :demand t
  :preface
  (defun patch-direnv-environment (&rest _args)
    (setenv "PATH" (concat emacs-binary-path ":" (getenv "PATH")))
    (setq exec-path (cons (file-name-as-directory emacs-binary-path)
                          exec-path)))
  :init
  (defconst emacs-binary-path (directory-file-name
                               (file-name-directory
                                (executable-find "emacsclient"))))
  :config
  (defvar flycheck-executable-for-buffer (make-hash-table :test #'equal))
  (defun locate-flycheck-executable (cmd)
    ;; (add-hook 'post-command-hook #'direnv--maybe-update-environment)
    (let ((exe (gethash (cons cmd (buffer-name))
                        flycheck-executable-for-buffer)))
      (if exe
          exe
        (direnv-update-environment default-directory)
        (let ((exe (executable-find cmd)))
          (puthash (cons cmd (buffer-name)) exe
                   flycheck-executable-for-buffer)))))
  (eval-after-load 'flycheck
    '(setq flycheck-executable-find #'locate-flycheck-executable))
  (add-hook 'coq-mode-hook
            #'(lambda ()
                ;; (add-hook 'post-command-hook #'direnv--maybe-update-environment)
                (direnv-update-environment default-directory)))
  (advice-add 'direnv-update-directory-environment
              :after #'patch-direnv-environment)
  (add-hook 'git-commit-mode-hook #'patch-direnv-environment)
  (add-hook 'magit-status-mode-hook #'patch-direnv-environment)
  (defvar my-direnv-last-buffer nil)
  (defun update-on-buffer-change ()
    (unless (eq (current-buffer) my-direnv-last-buffer)
      (setq my-direnv-last-buffer (current-buffer))
      (direnv-update-environment default-directory)))
  (add-hook 'post-command-hook #'update-on-buffer-change))

(use-package discover-my-major
  :bind (("C-h <C-m>" . discover-my-major)
         ("C-h M-m"   . discover-my-mode)))

(use-package docker
  :bind ("C-c d" . docker)
  :diminish
  :init
  (use-package docker-image     :commands docker-images)
  (use-package docker-container :commands docker-containers)
  (use-package docker-volume    :commands docker-volumes)
  (use-package docker-network   :commands docker-containers)
  (use-package docker-machine   :disabled t :commands docker-machines)
  (use-package docker-compose   :commands docker-compose))

(use-package docker-compose-mode
  :mode "docker-compose.*\.yml\\'")

(use-package docker-tramp
  :after tramp
  :defer 5)

(use-package dockerfile-mode
  :mode "Dockerfile[a-zA-Z.-]*\\'")

(use-package dot-gnus
  :no-require t
  :bind (("M-G"   . switch-to-gnus)
         ("C-x m" . compose-mail))
  :init
  (setq gnus-home-directory "~/Messages/Gnus/")

  (defun fetchmail-password ()
    (lookup-password "imap.fastmail.com" "johnw" 993)))

(use-package dot-org
  :no-require t
  :commands my-org-startup
  :bind* (("M-C"   . jump-to-org-agenda)
          ("M-m"   . org-smart-capture)
          ("M-M"   . org-inline-note)
          ("C-c a" . org-agenda)
          ("C-c S" . org-store-link)
          ("C-c l" . org-insert-link))
  :config
  (unless alternate-emacs
    (run-with-idle-timer 300 t 'jump-to-org-agenda)
    (my-org-startup)))

(use-package doxymacs
  :disabled t
  :commands (doxymacs-mode doxymacs-font-lock)
  :config
  (doxymacs-mode 1)
  (doxymacs-font-lock))

(use-package dumb-jump
  :hook ((coq-mode haskell-mode) . dumb-jump-mode))

(use-package ebdb-com
  :commands ebdb)

(use-package edbi
  :commands edbi:sql-mode)

(use-package ediff
  :bind (("C-c = b" . ediff-buffers)
         ("C-c = B" . ediff-buffers3)
         ("C-c = c" . compare-windows)
         ("C-c = =" . ediff-files)
         ("C-c = f" . ediff-files)
         ("C-c = F" . ediff-files3)
         ("C-c = m" . count-matches)
         ("C-c = r" . ediff-revision)
         ("C-c = p" . ediff-patch-file)
         ("C-c = P" . ediff-patch-buffer)
         ("C-c = l" . ediff-regions-linewise)
         ("C-c = w" . ediff-regions-wordwise))
  :init
  (defun test-compare ()
    (interactive)
    (delete-other-windows)
    (let ((here (point)))
      (search-forward "got:")
      (split-window-below)
      (goto-char here))
    (search-forward "expected:")
    (call-interactively #'compare-windows))

  (defun test-ediff ()
    (interactive)
    (goto-char (point-min))
    (search-forward "expected:")
    (forward-line 1)
    (goto-char (line-beginning-position))
    (let ((begin (point)))
      (search-forward "(")
      (goto-char (match-beginning 0))
      (forward-sexp)
      (let ((text (buffer-substring begin (point)))
            (expected (get-buffer-create "*expected*")))
        (with-current-buffer expected
          (erase-buffer)
          (insert text))
        (let ((here (point)))
          (search-forward "got:")
          (forward-line 1)
          (goto-char (line-beginning-position))
          (setq begin (point))
          (search-forward "(")
          (goto-char (match-beginning 0))
          (forward-sexp)
          (setq text (buffer-substring begin (point)))
          (let ((got (get-buffer-create "*got*")))
            (with-current-buffer got
              (erase-buffer)
              (insert text))
            (ediff-buffers expected got)))))))

(use-package ediff-keep
  :after ediff)

(use-package edit-env
  :commands edit-env)

(use-package edit-indirect
  :bind (("C-c '" . edit-indirect-region)))

(use-package edit-rectangle
  :bind ("C-x r e" . edit-rectangle))

(use-package edit-server
  :if (and window-system
           (not alternate-emacs))
  :defer 5
  :config
  (edit-server-start))

(use-package edit-var
  :bind ("C-c e v" . edit-variable))

(use-package eglot
  :if dot-emacs-use-eglot
  :commands eglot
  :config
  ;; (add-to-list 'eglot-server-programs '(rust-mode "rust-analyzer"))
  (defvar flymake-list-only-diagnostics nil)
  (defun project-root (project)
    (car (project-roots project)))
  )

(use-package eldoc
  :diminish
  :hook ((c-mode-common emacs-lisp-mode) . eldoc-mode))

(use-package elint
  :commands (elint-initialize elint-current-buffer)
  :bind ("C-c e E" . my-elint-current-buffer)
  :preface
  (defun my-elint-current-buffer ()
    (interactive)
    (elint-initialize)
    (elint-current-buffer))
  :config
  (add-to-list 'elint-standard-variables 'current-prefix-arg)
  (add-to-list 'elint-standard-variables 'command-line-args-left)
  (add-to-list 'elint-standard-variables 'buffer-file-coding-system)
  (add-to-list 'elint-standard-variables 'emacs-major-version)
  (add-to-list 'elint-standard-variables 'window-system))

(use-package elisp-depend
  :commands elisp-depend-print-dependencies)

(use-package elisp-docstring-mode
  :commands elisp-docstring-mode)

(use-package elisp-slime-nav
  :diminish
  :commands (elisp-slime-nav-mode
             elisp-slime-nav-find-elisp-thing-at-point))

(use-package elmacro
  :bind (("C-c m e" . elmacro-mode)
         ("C-x C-)" . elmacro-show-last-macro)))

(use-package emamux
  :commands emamux:send-command)

(use-package emojify
  :after erc
  :defer 15
  :config
  (global-emojify-mode)
  ;; (global-emojify-mode-line-mode -1)
  )

(use-package engine-mode
  :defer 5
  :config
  (defengine google "https://www.google.com/search?q=%s"
             :keybinding "/")
  (engine-mode 1))

(use-package epa
  :config
  (epa-file-enable))

(use-package erc
  :commands (erc erc-tls)
  :bind (:map erc-mode-map
              ("C-c r" . reset-erc-track-mode))
  :preface
  (defun irc (&optional arg)
    (interactive "P")
    (if arg
        (pcase-dolist (`(,server . ,nick)
                       '(("irc.libera.chat"  . "johnw")
                         ("irc.gitter.im"    . "jwiegley")))
          (erc-tls :server server :port 6697 :nick (concat nick "_")
                   :password (lookup-password server nick 6697)))
      (let ((pass (lookup-password "irc.libera.chat" "johnw" 6697)))
        (when (> (length pass) 32)
          (error "Failed to read ZNC password"))
        (erc :server "127.0.0.1" :port 6697 :nick "johnw"
             :password (concat "johnw/gitter:" pass))
        (sleep-for 5)
        (erc :server "127.0.0.1" :port 6697 :nick "johnw"
             :password (concat "johnw/libera:" pass)))))

  (defun reset-erc-track-mode ()
    (interactive)
    (setq erc-modified-channels-alist nil)
    (erc-modified-channels-update)
    (erc-modified-channels-display)
    (force-mode-line-update))

  (defun setup-irc-environment ()
    (set (make-local-variable 'scroll-conservatively) 100)
    (setq erc-timestamp-only-if-changed-flag nil
          erc-timestamp-format "%H:%M "
          erc-fill-prefix "          "
          erc-fill-column 78
          erc-insert-timestamp-function 'erc-insert-timestamp-left
          ivy-use-virtual-buffers nil
          line-spacing 4))

  (defun accept-certificate ()
    (interactive)
    (when (re-search-backward "/znc[\n ]+AddTrustedServerFingerprint[\n ]+\\(.+\\)" nil t)
      (goto-char (point-max))
      (erc-send-input (concat "/znc AddTrustedServerFingerprint " (match-string 1)))))

  (defcustom erc-foolish-content '()
    "Regular expressions to identify foolish content.
    Usually what happens is that you add the bots to
    `erc-ignore-list' and the bot commands to this list."
    :group 'erc
    :type '(repeat regexp))

  (defun erc-foolish-content (msg)
    "Check whether MSG is foolish."
    (erc-list-match erc-foolish-content msg))

  :init
  (add-hook 'erc-mode-hook #'setup-irc-environment)
  (when alternate-emacs
    (add-hook 'emacs-startup-hook #'irc))

  (eval-after-load 'erc-identd
    '(defun erc-identd-start (&optional port)
       "Start an identd server listening to port 8113.
  Port 113 (auth) will need to be redirected to port 8113 on your
  machine -- using iptables, or a program like redir which can be
  run from inetd. The idea is to provide a simple identd server
  when you need one, without having to install one globally on
  your system."
       (interactive (list (read-string "Serve identd requests on port: " "8113")))
       (unless port (setq port erc-identd-port))
       (when (stringp port)
         (setq port (string-to-number port)))
       (when erc-identd-process
         (delete-process erc-identd-process))
       (setq erc-identd-process
	     (make-network-process :name "identd"
			           :buffer nil
			           :host 'local :service port
			           :server t :noquery t
			           :filter 'erc-identd-filter))
       (set-process-query-on-exit-flag erc-identd-process nil)))

  :config
  (erc-track-minor-mode 1)
  (erc-track-mode 1)

  (add-hook 'erc-insert-pre-hook
            #'(lambda (s)
                (when (erc-foolish-content s)
                  (setq erc-insert-this nil))))

  (bind-key "<f5>" #'accept-certificate))

(use-package erc-alert
  :disabled t
  :after erc)

(use-package erc-highlight-nicknames
  :after erc)

(use-package erc-macros
  :after erc)

(use-package erc-patch
  :disabled t
  :after erc)

(use-package erc-question
  :disabled t
  :after erc)

(use-package erc-yank
  :load-path "lisp/erc-yank"
  :after erc
  :bind (:map erc-mode-map
              ("C-y" . erc-yank )))

(use-package erefactor
  :disabled t
  :bind (:map emacs-lisp-mode-map
              ("C-c C-v" . erefactor-map)))

(use-package ert
  :bind ("C-c e t" . ert-run-tests-interactively))

(use-package esh-toggle
  :bind ("C-x C-z" . eshell-toggle))

(use-package eshell
  :commands (eshell eshell-command)
  :preface
  (defvar eshell-isearch-map
    (let ((map (copy-keymap isearch-mode-map)))
      (define-key map [(control ?m)] 'eshell-isearch-return)
      (define-key map [return]       'eshell-isearch-return)
      (define-key map [(control ?r)] 'eshell-isearch-repeat-backward)
      (define-key map [(control ?s)] 'eshell-isearch-repeat-forward)
      (define-key map [(control ?g)] 'eshell-isearch-abort)
      (define-key map [backspace]    'eshell-isearch-delete-char)
      (define-key map [delete]       'eshell-isearch-delete-char)
      map)
    "Keymap used in isearch in Eshell.")

  (defun eshell-initialize ()
    (defun eshell-spawn-external-command (beg end)
      "Parse and expand any history references in current input."
      (save-excursion
        (goto-char end)
        (when (looking-back "&!" beg)
          (delete-region (match-beginning 0) (match-end 0))
          (goto-char beg)
          (insert "spawn "))))

    (add-hook 'eshell-expand-input-functions #'eshell-spawn-external-command)

    (use-package em-unix
      :defer t
      :config
      (unintern 'eshell/su nil)
      (unintern 'eshell/sudo nil)))

  :init
  (add-hook 'eshell-first-time-mode-hook #'eshell-initialize))

(use-package eshell-bookmark
  :hook (eshell-mode . eshell-bookmark-setup))

(use-package eshell-up
  :commands eshell-up)

(use-package eshell-z
  :after eshell)

(use-package etags
  :bind ("M-T" . tags-search))

(use-package eval-expr
  :disabled t
  :bind ("M-:" . eval-expr)
  :config
  (defun eval-expr-minibuffer-setup ()
    (local-set-key (kbd "<tab>") #'lisp-complete-symbol)
    (set-syntax-table emacs-lisp-mode-syntax-table)
    (paredit-mode)))

(use-package eval-in-repl
  ;; jww (2017-12-10): Need to configure.
  :disabled t)

(use-package evil
  :commands evil-mode)

(use-package expand-region
  :bind ("C-=" . er/expand-region))

(use-package eyebrowse
  :bind-keymap ("C-\\" . eyebrowse-mode-map)
  :bind (:map eyebrowse-mode-map
              ("C-\\ C-\\" . eyebrowse-last-window-config)
              ("A-1" . eyebrowse-switch-to-window-config-1)
              ("A-2" . eyebrowse-switch-to-window-config-2)
              ("A-3" . eyebrowse-switch-to-window-config-3)
              ("A-4" . eyebrowse-switch-to-window-config-4))
  :config
  (eyebrowse-mode t))

(use-package fancy-narrow
  :bind (("C-c N N" . fancy-narrow-to-region)
         ("C-c N W" . fancy-widen))
  :commands (fancy-narrow-to-region fancy-widen))

(use-package feebleline
  :bind (("M-o m" . feebleline-mode))
  :config
  (window-divider-mode t))

(use-package fence-edit
  :commands fence-edit-code-at-point)

(use-package fetchmail-mode
  :commands fetchmail-mode)

(use-package ffap
  :bind ("C-c v" . ffap))

(use-package flycheck
  :commands (flycheck-mode
             flycheck-next-error
             flycheck-previous-error)
  :init
  (dolist (where '((emacs-lisp-mode-hook . emacs-lisp-mode-map)
                   ;; (haskell-mode-hook    . haskell-mode-map)
                   (js2-mode-hook        . js2-mode-map)
                   (c-mode-common-hook   . c-mode-base-map)
                   ;; (rust-mode-hook       . rust-mode-map)
                   (rustic-mode-hook     . rustic-mode-map)))
    (add-hook (car where)
              `(lambda ()
                 (bind-key "M-n" #'flycheck-next-error ,(cdr where))
                 (bind-key "M-p" #'flycheck-previous-error ,(cdr where)))))
  :config
  (defalias 'show-error-at-point-soon
    'flycheck-show-error-at-point)

  (defun magnars/adjust-flycheck-automatic-syntax-eagerness ()
    "Adjust how often we check for errors based on if there are any.
  This lets us fix any errors as quickly as possible, but in a
  clean buffer we're an order of magnitude laxer about checking."
    (setq flycheck-idle-change-delay
          (if flycheck-current-errors 0.3 3.0)))

  ;; Each buffer gets its own idle-change-delay because of the
  ;; buffer-sensitive adjustment above.
  (make-variable-buffer-local 'flycheck-idle-change-delay)

  (add-hook 'flycheck-after-syntax-check-hook
            #'magnars/adjust-flycheck-automatic-syntax-eagerness)

  ;; Remove newline checks, since they would trigger an immediate check
  ;; when we want the idle-change-delay to be in effect while editing.
  (setq-default flycheck-check-syntax-automatically '(save
                                                      idle-change
                                                      mode-enabled))

  (defun flycheck-handle-idle-change ()
    "Handle an expired idle time since the last change.
  This is an overwritten version of the original
  flycheck-handle-idle-change, which removes the forced deferred.
  Timers should only trigger inbetween commands in a single
  threaded system and the forced deferred makes errors never show
  up before you execute another command."
    (flycheck-clear-idle-change-timer)
    (flycheck-buffer-automatically 'idle-change)))

(use-package flycheck-haskell
  :disabled t
  :commands flycheck-haskell-setup)

(use-package flycheck-package
  :after flycheck)

(use-package flyspell
  :bind (("C-c i b" . flyspell-buffer)
         ("C-c i f" . flyspell-mode))
  :config
  (defun my-flyspell-maybe-correct-transposition (beg end candidates)
    (unless (let (case-fold-search)
              (string-match "\\`[A-Z0-9]+\\'"
                            (buffer-substring-no-properties beg end)))
      (flyspell-maybe-correct-transposition beg end candidates))))

(use-package focus
  :commands focus-mode)

(use-package font-lock-studio
  :commands (font-lock-studio
             font-lock-studio-region))

(use-package forge
  :after magit
  :preface
  (defun my-quick-create-pull-request (title branch)
    (interactive "sTitle: \nsBranch: ")
    (setq branch (concat "johnw/" branch))
    ;; Split this commit to another branch.
    (magit-branch-spinoff branch)
    ;; Push that branch to the remote.
    (call-interactively #'magit-push-current-to-pushremote)
    (sleep-for 3)
    ;; Create a pullreq using the same title.
    (forge-create-pullreq (concat "origin/" branch) "origin/master"))
  :config
  (transient-insert-suffix 'forge-dispatch "c i"
    '("p" "quick-pr" my-quick-create-pull-request))
  (remove-hook 'magit-status-sections-hook 'forge-insert-issues))

(use-package format-all
  :commands (format-all-buffer
             format-all-mode)
  :config
  (defun format-all--resolve-system (choices)
    "Get first choice matching `format-all--system-type' from CHOICES."
    (cl-dolist (choice choices)
      (cond ((atom choice)
             (cl-return choice))
            ((eql format-all--system-type (car choice))
             (cl-return (cadr choice)))))))

(use-package free-keys
  :commands free-keys)

(use-package fullframe
  :defer t
  :init
  (autoload #'fullframe "fullframe"))

(use-package ggtags
  ;; jww (2017-12-10): Need to configure.
  :disabled t
  :commands ggtags-mode
  :diminish)

(use-package gist
  :no-require t
  :bind ("C-c G" . my-gist-region-or-buffer)
  :preface
  (defun my-gist-region-or-buffer (start end)
    (interactive "r")
    (copy-region-as-kill start end)
    (deactivate-mark)
    (let ((file-name buffer-file-name))
      (with-temp-buffer
        (if file-name
            (call-process "gist" nil t nil "-f" file-name "-P")
          (call-process "gist" nil t nil "-P"))
        (kill-ring-save (point-min) (1- (point-max)))
        (message (buffer-substring (point-min) (1- (point-max))))))))

(use-package git-annex
  :load-path "lisp/git-annex"
  :after dired
  :defer t)

(use-package git-link
  :bind ("C-c Y" . git-link)
  :commands (git-link git-link-commit git-link-homepage))

(use-package git-timemachine
  :commands git-timemachine)

(use-package git-undo
  :load-path "lisp/git-undo"
  :commands git-undo)

(use-package gitattributes-mode
  :disabled t
  :defer 5)

(use-package gitconfig-mode
  :disabled t
  :defer 5)

(use-package gitignore-mode
  :disabled t
  :defer 5)

(use-package github-review
  :after forge
  :commands github-review-start
  :config
  (transient-insert-suffix 'forge-dispatch "c p"
    '("c r" "github-review" github-review-forge-pr-at-point)))

(use-package gitpatch
  :commands gitpatch-mail)

(use-package google-this
  :bind-keymap ("C-c /" . google-this-mode-submap)
  :bind* ("M-SPC" . google-this-search)
  :bind (:map google-this-mode-map
              ("/" . google-this-search)))

(use-package goto-last-change
  :bind ("C-x C-/" . goto-last-change))

(use-package goto-line-preview
  :config
  (global-set-key [remap goto-line] 'goto-line-preview))

(use-package graphviz-dot-mode
  :mode "\\.dot\\'")

(use-package grep
  :bind (("M-s n" . find-name-dired)
         ("M-s F" . find-grep)
         ("M-s G" . grep)
         ("M-s d" . find-grep-dired)))

(use-package gud
  :commands gud-gdb
  :bind (("<f9>"    . gud-cont)
         ("<f10>"   . gud-next)
         ("<f11>"   . gud-step)
         ("S-<f11>" . gud-finish))
  :init
  (defun show-debugger ()
    (interactive)
    (let ((gud-buf
           (catch 'found
             (dolist (buf (buffer-list))
               (if (string-match "\\*gud-" (buffer-name buf))
                   (throw 'found buf))))))
      (if gud-buf
          (switch-to-buffer-other-window gud-buf)
        (call-interactively 'gud-gdb)))))

(use-package haskell-edit
  :load-path "lisp/haskell-config"
  :after haskell-mode
  :bind (:map haskell-mode-map
              ("C-c M-q" . haskell-edit-reformat)))

(use-package haskell-mode
  :mode (("\\.hs\\(c\\|-boot\\)?\\'" . haskell-mode)
         ("\\.lhs\\'" . literate-haskell-mode)
         ("\\.cabal\\'" . haskell-cabal-mode))
  :bind (:map haskell-mode-map
              ("C-c C-h" . my-haskell-hoogle)
              ("C-c C-," . haskell-navigate-imports)
              ("C-c C-." . haskell-mode-format-imports)
              ("C-c C-u" . my-haskell-insert-undefined)
              ("M-s")
              ("M-t"))
  :preface
  (defun my-haskell-insert-undefined ()
    (interactive) (insert "undefined"))

  (defun snippet (name)
    (interactive "sName: ")
    (find-file (expand-file-name (concat name ".hs") "~/src/notes"))
    (haskell-mode)
    (goto-char (point-min))
    (when (eobp)
      (insert "hdr")
      (yas-expand)))

  (defvar hoogle-server-process nil)
  (defun my-haskell-hoogle (query &optional arg)
    "Do a Hoogle search for QUERY."
    (interactive
     (let ((def (haskell-ident-at-point)))
       (if (and def (symbolp def)) (setq def (symbol-name def)))
       (list (read-string (if def
                              (format "Hoogle query (default %s): " def)
                            "Hoogle query: ")
                          nil nil def)
             current-prefix-arg)))
    (let ((pe process-environment)
          (ep exec-path)
          (default-hoo (expand-file-name
                        "default.hoo"
                        (locate-dominating-file "." "default.hoo"))))
      (unless (and hoogle-server-process
                   (process-live-p hoogle-server-process))
        (message "Starting local Hoogle server on port 8687...")
        (with-current-buffer (get-buffer-create " *hoogle-web*")
          (cd temporary-file-directory)
          (let ((process-environment pe)
                (exec-path ep))
            (setq hoogle-server-process
                  (start-process "hoogle-web" (current-buffer)
                                 (executable-find "hoogle")
                                 "server"
                                 ;; (concat "--database=" default-hoo)
                                 "--local" "--port=8687"))))
        (message "Starting local Hoogle server on port 8687...done")))
    (browse-url
     (format "http://127.0.0.1:8687/?hoogle=%s"
             (replace-regexp-in-string
              " " "+" (replace-regexp-in-string "\\+" "%2B" query)))))

  (defvar haskell-prettify-symbols-alist
    '(("::"     . ?∷)
      ("forall" . ?∀)
      ("exists" . ?∃)
      ("->"     . ?→)
      ("<-"     . ?←)
      ("=>"     . ?⇒)
      ("~>"     . ?⇝)
      ("<~"     . ?⇜)
      ("<>"     . ?⨂)
      ("msum"   . ?⨁)
      ("\\"     . ?λ)
      ("not"    . ?¬)
      ("&&"     . ?∧)
      ("||"     . ?∨)
      ("/="     . ?≠)
      ("<="     . ?≤)
      (">="     . ?≥)
      ("<<<"    . ?⋘)
      (">>>"    . ?⋙)

      ("`elem`"             . ?∈)
      ("`notElem`"          . ?∉)
      ("`member`"           . ?∈)
      ("`notMember`"        . ?∉)
      ("`union`"            . ?∪)
      ("`intersection`"     . ?∩)
      ("`isSubsetOf`"       . ?⊆)
      ("`isNotSubsetOf`"    . ?⊄)
      ("`isSubsequenceOf`"  . ?⊆)
      ("`isProperSubsetOf`" . ?⊂)
      ("undefined"          . ?⊥)))

  :config
  (require 'haskell)
  (require 'haskell-doc)
  (require 'haskell-commands)

  (defun my-update-cabal-repl (&rest _args)
    (aif (getenv "CABAL_REPL")
        (let ((args (nthcdr 2 (split-string it))))
          (setq-local haskell-process-args-cabal-repl
                      (delete-dups
                       (append haskell-process-args-cabal-repl args))))))

  (defun my-haskell-mode-hook ()
    (haskell-indentation-mode)
    (interactive-haskell-mode)
    (diminish 'interactive-haskell-mode)
    (when (and (boundp 'brittany-enabled)
               brittany-enabled)
      (let ((brittany (find-brittany)))
        (when brittany
          (setq-local haskell-stylish-on-save t)
          (setq-local haskell-mode-stylish-haskell-path brittany)
          (setq-local haskell-mode-stylish-haskell-args '("-")))))
    (advice-add 'direnv-update-directory-environment
                :after #'my-update-cabal-repl)
    (whitespace-mode 1)
    ;; (flycheck-mode 1)
    ;; (flycheck-haskell-setup)
    ;; (add-hook 'hack-local-variables-hook
    ;;           #'(lambda ()
    ;;               (when nil
    ;;                 (setq-local flycheck-ghc-search-path nil)
    ;;                 (setq-local flycheck-ghc-args nil)))
    ;;           t)
    (bind-key "M-n" #'haskell-goto-next-error haskell-mode-map)
    (bind-key "M-p" #'haskell-goto-prev-error haskell-mode-map)
    (setq-local prettify-symbols-alist haskell-prettify-symbols-alist)
    (prettify-symbols-mode 1)
    (bug-reference-prog-mode 1)
    (when (executable-find "ormolu")
      (require 'format-all)
      (define-format-all-formatter ormolu
        (:executable "ormolu")
        (:install "stack install ormolu")
        (:languages "Haskell" "Literate Haskell")
        (:features)
        (:format
         (format-all--buffer-easy
          executable
          (when (buffer-file-name)
            (list "--stdin-input-file" (buffer-file-name))))))
      (format-all--set-chain "Haskell" '(ormolu))
      ;; (format-all-mode 1)
      ))

  (add-hook 'haskell-mode-hook #'my-haskell-mode-hook)

  (eval-after-load 'align
    '(nconc
      align-rules-list
      (mapcar #'(lambda (x)
                  `(,(car x)
                    (regexp . ,(cdr x))
                    (modes quote (haskell-mode literate-haskell-mode))))
              '((haskell-types       . "\\(\\s-+\\)\\(::\\|∷\\)\\s-+")
                (haskell-assignment  . "\\(\\s-+\\)=\\s-+")
                (haskell-arrows      . "\\(\\s-+\\)\\(->\\|→\\)\\s-+")
                (haskell-left-arrows . "\\(\\s-+\\)\\(<-\\|←\\)\\s-+")))))

  (defun haskell-process-load-complete
      (session process buffer reload module-buffer &optional cont)
    "Handle the complete loading response. BUFFER is the string of
  text being sent over the process pipe. MODULE-BUFFER is the
  actual Emacs buffer of the module being loaded."
    (when (get-buffer (format "*%s:splices*" (haskell-session-name session)))
      (with-current-buffer (haskell-interactive-mode-splices-buffer session)
        (erase-buffer)))
    (let* ((ok (cond
                ((haskell-process-consume
                  process
                  "Ok, \\(?:\\([0-9]+\\|one\\)\\) modules? loaded\\.$")
                 t)
                ((haskell-process-consume
                  process
                  "Failed, \\(?:[0-9]+\\) modules? loaded\\.$")
                 nil)
                ((haskell-process-consume
                  process
                  "Ok, modules loaded: \\(.+\\)\\.$")
                 t)
                ((haskell-process-consume
                  process
                  "Failed, modules loaded: \\(.+\\)\\.$")
                 nil)
                (t
                 (error (message "Unexpected response from haskell process.")))))
           (modules (haskell-process-extract-modules buffer))
           (cursor (haskell-process-response-cursor process))
           (warning-count 0))
      (haskell-process-set-response-cursor process 0)
      (haskell-check-remove-overlays module-buffer)
      (while
          (haskell-process-errors-warnings module-buffer session process buffer)
        (setq warning-count (1+ warning-count)))
      (haskell-process-set-response-cursor process cursor)
      (if (and (not reload)
               haskell-process-reload-with-fbytecode)
          (haskell-process-reload-with-fbytecode process module-buffer)
        (haskell-process-import-modules process (car modules)))
      (if ok
          (haskell-mode-message-line (if reload "Reloaded OK." "OK."))
        (haskell-interactive-mode-compile-error session "Compilation failed."))
      (when cont
        (condition-case-unless-debug e
            (funcall cont ok)
          (error (message "%S" e))
          (quit nil))))))

(use-package hcl-mode
  :mode "\.nomad\\'")

(use-package helm
  :defer t
  :bind (:map helm-map
              ("<tab>" . helm-execute-persistent-action)
              ("C-i"   . helm-execute-persistent-action)
              ("C-z"   . helm-select-action)
              ("A-v"   . helm-previous-page))
  :config
  (helm-autoresize-mode 1))

(use-package helm-descbinds
  :bind ("C-h b" . helm-descbinds)
  :init
  (fset 'describe-bindings 'helm-descbinds))

(use-package helm-describe-modes
  :after helm
  :bind ("C-h m" . helm-describe-modes))

(use-package helm-firefox
  :disabled t
  :bind ("A-M-b" . helm-firefox-bookmarks))

(use-package helm-font
  :commands (helm-select-xfont helm-ucs))

(use-package helm-google
  :commands helm-google)

(use-package helm-navi
  :after (helm navi)
  :commands helm-navi)

(use-package helm-sys
  :commands helm-top)

(use-package helpful
  :bind (("C-h e F" . helpful-function)
         ("C-h e C" . helpful-command)
         ("C-h e M" . helpful-macro)
         ("C-h e L" . helpful-callable)
         ("C-h e S" . helpful-at-point)
         ("C-h e V" . helpful-variable)))

(use-package hi-lock
  :bind (("M-o l" . highlight-lines-matching-regexp)
         ("M-o r" . highlight-regexp)
         ("M-o w" . highlight-phrase)))

(use-package hideif
  :diminish hide-ifdef-mode
  :hook (c-mode-common . hide-ifdef-mode))

(use-package hideshow
  :diminish hs-minor-mode
  :hook (prog-mode . hs-minor-mode)
  :bind (:map prog-mode-map
              ("C-c h" . hs-toggle-hiding)))

(use-package highlight
  :bind (("C-c H H" . hlt-highlight-region)
         ("C-c H U" . hlt-unhighlight-region)))

(use-package highlight-cl
  :hook (emacs-lisp-mode . highlight-cl-add-font-lock-keywords))

(use-package highlight-defined
  :commands highlight-defined-mode)

(use-package highlight-numbers
  :hook (prog-mode . highlight-numbers-mode))

(use-package hilit-chg
  :bind ("M-o C" . highlight-changes-mode))

(use-package hippie-exp
  :bind (("M-/"   . hippie-expand)
         ("C-M-/" . dabbrev-completion)))

(use-package hl-line
  :commands hl-line-mode
  :bind ("M-o h" . hl-line-mode))

(use-package hl-line+
  :after hl-line)

(use-package hydra
  :defer t
  :config
  (defhydra hydra-zoom (global-map "<f2>")
    "zoom"
    ("g" text-scale-increase "in")
    ("l" text-scale-decrease "out")))

(use-package ibuffer
  :bind ("C-x C-b" . ibuffer)
  :init
  (add-hook 'ibuffer-mode-hook
            #'(lambda ()
                (ibuffer-switch-to-saved-filter-groups "default"))))

(use-package iedit
  :defer t)

(use-package ielm
  :commands ielm
  :bind (:map ielm-map ("<return>" . my-ielm-return))
  :config
  (defun my-ielm-return ()
    (interactive)
    (let ((end-of-sexp (save-excursion
                         (goto-char (point-max))
                         (skip-chars-backward " \t\n\r")
                         (point))))
      (if (>= (point) end-of-sexp)
          (progn
            (goto-char (point-max))
            (skip-chars-backward " \t\n\r")
            (delete-region (point) (point-max))
            (call-interactively #'ielm-return))
        (call-interactively #'paredit-newline)))))

(use-package iflipb
  :disabled t
  :bind* ("<S-return>" . my-iflipb-next-buffer)
  :commands (iflipb-next-buffer iflipb-previous-buffer)
  :preface
  (defvar my-iflipb-auto-off-timeout-sec 1)
  (defvar my-iflipb-auto-off-timer nil)
  (defvar my-iflipb-auto-off-timer-canceler-internal nil)
  (defvar my-iflipb-ing-internal nil)

  (defun my-iflipb-auto-off ()
    (setq my-iflipb-auto-off-timer-canceler-internal nil
          my-iflipb-ing-internal nil)
    (when my-iflipb-auto-off-timer
      (message nil)
      (cancel-timer my-iflipb-auto-off-timer)
      (setq my-iflipb-auto-off-timer nil)))

  (defun my-iflipb-next-buffer (arg)
    (interactive "P")
    (iflipb-next-buffer arg)
    (if my-iflipb-auto-off-timer-canceler-internal
        (cancel-timer my-iflipb-auto-off-timer-canceler-internal))
    (setq my-iflipb-auto-off-timer
          (run-with-idle-timer my-iflipb-auto-off-timeout-sec 0
                               'my-iflipb-auto-off)
          my-iflipb-ing-internal t))

  (defun my-iflipb-previous-buffer ()
    (interactive)
    (iflipb-previous-buffer)
    (if my-iflipb-auto-off-timer-canceler-internal
        (cancel-timer my-iflipb-auto-off-timer-canceler-internal))
    (setq my-iflipb-auto-off-timer
          (run-with-idle-timer my-iflipb-auto-off-timeout-sec 0
                               'my-iflipb-auto-off)
          my-iflipb-ing-internal t))

  :config
  (setq iflipb-always-ignore-buffers
        "\\`\\( \\|diary\\|ipa\\|\\.newsrc-dribble\\'\\)"
        iflipb-wrap-around t)

  (defun iflipb-first-iflipb-buffer-switch-command ()
    (not (and (or (eq last-command 'my-iflipb-next-buffer)
                  (eq last-command 'my-iflipb-previous-buffer))
              my-iflipb-ing-internal))))

(use-package image-file
  :defer 5
  :config
  (auto-image-file-mode 1)
  (add-hook 'image-mode-hook #'image-transform-reset))

(use-package imenu-list
  :commands imenu-list-minor-mode)

(use-package indent
  :commands indent-according-to-mode)

(use-package indent-shift
  :bind (("C-c <" . indent-shift-left)
         ("C-c >" . indent-shift-right)))

(use-package info
  :bind ("C-h C-i" . info-lookup-symbol)
  :config
  (add-hook 'Info-mode-hook
            #'(lambda ()
                (setq buffer-face-mode-face '(:family "Bookerly"))
                (buffer-face-mode)
                (text-scale-adjust 1))))

(use-package info-look
  :defer t
  :init
  (autoload 'info-lookup-add-help "info-look"))

(use-package info-lookmore
  :after info-look
  :config
  (info-lookmore-elisp-cl)
  (info-lookmore-elisp-userlast)
  (info-lookmore-elisp-gnus)
  (info-lookmore-apropos-elisp))

(use-package initsplit
  :disabled t
  :demand t
  :load-path "lisp/initsplit")

(use-package ialign
  :bind ("C-c {" . ialign-interactive-align))

(use-package inventory
  :commands (inventory sort-package-declarations))

(use-package ipcalc
  :commands ipcalc)

(use-package isearch
  :no-require t
  :bind (("C-M-r" . isearch-backward-other-window)
         ("C-M-s" . isearch-forward-other-window))
  :bind (:map isearch-mode-map
              ("C-c" . isearch-toggle-case-fold)
              ("C-t" . isearch-toggle-regexp)
              ("C-^" . isearch-edit-string)
              ("C-i" . isearch-complete))
  :preface
  (defun isearch-backward-other-window ()
    (interactive)
    (split-window-vertically)
    (other-window 1)
    (call-interactively 'isearch-backward))

  (defun isearch-forward-other-window ()
    (interactive)
    (split-window-vertically)
    (other-window 1)
    (call-interactively 'isearch-forward)))

(use-package ispell
  :no-require t
  :bind (("C-c i c" . ispell-comments-and-strings)
         ("C-c i d" . ispell-change-dictionary)
         ("C-c i k" . ispell-kill-ispell)
         ("C-c i m" . ispell-message)
         ("C-c i r" . ispell-region)))

(use-package ivy
  :diminish
  :demand t

  :bind (("C-x b" . ivy-switch-buffer)
         ("C-x B" . ivy-switch-buffer-other-window)
         ("M-H"   . ivy-resume))

  :bind (:map ivy-minibuffer-map
              ("<tab>" . ivy-alt-done)
              ("SPC"   . ivy-alt-done-or-space)
              ("C-d"   . ivy-done-or-delete-char)
              ("C-i"   . ivy-partial-or-done)
              ("C-r"   . ivy-previous-line-or-history)
              ("M-r"   . ivy-reverse-i-search))

  :bind (:map ivy-switch-buffer-map
              ("C-k" . ivy-switch-buffer-kill))

  :custom
  (ivy-dynamic-exhibit-delay-ms 200)
  (ivy-height 10)
  (ivy-initial-inputs-alist nil t)
  (ivy-magic-tilde nil)
  (ivy-re-builders-alist '((t . ivy--regex-ignore-order)))
  (ivy-use-virtual-buffers t)
  (ivy-wrap t)

  :preface
  (defun ivy-done-or-delete-char ()
    (interactive)
    (call-interactively
     (if (eolp)
         #'ivy-immediate-done
       #'ivy-delete-char)))

  (defun ivy-alt-done-or-space ()
    (interactive)
    (call-interactively
     (if (= ivy--length 1)
         #'ivy-alt-done
       #'self-insert-command)))

  (defun ivy-switch-buffer-kill ()
    (interactive)
    (debug)
    (let ((bn (ivy-state-current ivy-last)))
      (when (get-buffer bn)
        (kill-buffer bn))
      (unless (buffer-live-p (ivy-state-buffer ivy-last))
        (setf (ivy-state-buffer ivy-last)
              (with-ivy-window (current-buffer))))
      (setq ivy--all-candidates (delete bn ivy--all-candidates))
      (ivy--exhibit)))

  ;; This is the value of `magit-completing-read-function', so that we see
  ;; Magit's own sorting choices.
  (defun my-ivy-completing-read (&rest args)
    (let ((ivy-sort-functions-alist '((t . nil))))
      (apply 'ivy-completing-read args)))

  :config
  (ivy-mode 1)
  (ivy-set-occur 'ivy-switch-buffer 'ivy-switch-buffer-occur)

  (defun ivy--switch-buffer-matcher (regexp candidates)
    "Return REGEXP matching CANDIDATES.
Skip buffers that match `ivy-ignore-buffers'."
    (let ((res (ivy--re-filter regexp candidates)))
      (if (or (null ivy-use-ignore)
              (null ivy-ignore-buffers))
          res
        (or (cl-remove-if
             (lambda (buf)
               (cl-find-if
                (lambda (f-or-r)
                  (if (functionp f-or-r)
                      (funcall f-or-r buf)
                    (string-match-p f-or-r buf)))
                ivy-ignore-buffers))
             res)
            (and (eq ivy-use-ignore t)
                 res))))))

(use-package ivy-bibtex
  :disabled t
  :commands ivy-bibtex)

(use-package ivy-hydra
  :after (ivy hydra)
  :defer t)

(use-package ivy-pass
  :commands ivy-pass)

(use-package ivy-rich
  :after ivy
  :demand t
  :config
  (ivy-rich-mode 1)
  (setq ivy-virtual-abbreviate 'full
        ivy-rich-switch-buffer-align-virtual-buffer t
        ivy-rich-path-style 'abbrev))

(use-package ivy-rtags
  :disabled t
  :load-path "~/.nix-profile/share/emacs/site-lisp/rtags"
  :after (ivy rtags))

(use-package jobhours
  :disabled t
  :demand t
  :bind ("M-o j" . jobhours-update-string)
  :config
  (defun my-org-insert-jobhours-string ()
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (goto-char (line-end-position))
      (let* ((width (- (window-width) (current-column)))
             (jobhours (jobhours-get-string t))
             (spacer (- width (length jobhours)))
             (inhibit-read-only t))
        (when (> spacer 0)
          (insert (make-string spacer ? ) jobhours)))))

  (defun my-org-delayed-update ()
    (run-with-idle-timer
     1 nil
     `(lambda ()
        (with-current-buffer ,(current-buffer)
          (org-save-all-org-buffers)
          (my-org-insert-jobhours-string)))))

  (add-hook 'org-agenda-finalize-hook #'my-org-delayed-update t))

(use-package jq-mode
  :mode "\\.jq\\'")

(use-package js2-mode
  :mode "\\.js\\'"
  :config
  (add-to-list 'flycheck-disabled-checkers #'javascript-jshint)
  (flycheck-add-mode 'javascript-eslint 'js2-mode)
  (flycheck-mode 1))

(use-package js3-mode
  ;; jww (2017-12-10): Need to configure.
  :disabled t)

(use-package json-mode
  :mode "\\.json\\'")

(use-package json-reformat
  :after json-mode)

(use-package json-snatcher
  :after json-mode)

(use-package key-chord
  :commands key-chord-mode)

(use-package keypression
  :commands key-chord-mode)

(use-package know-your-http-well
  :commands (http-header
             http-method
             http-relation
             http-status-code
             media-type))

(use-package kotl-mode
  :disabled t
  :mode "\\.kotl\\'")

(use-package latex
  :config
  (require 'preview)
  ;; (load (emacs-path "site-lisp/auctex/style/minted"))

  (info-lookup-add-help :mode 'LaTeX-mode
                        :regexp ".*"
                        :parse-rule "\\\\?[a-zA-Z]+\\|\\\\[^a-zA-Z]"
                        :doc-spec '(("(latex2e)Concept Index")
                                    ("(latex2e)Command Index")))

  (defvar latex-prettify-symbols-alist
    '(("\N{THIN SPACE}" . ?\⟷)))

  (bind-key "C-x SPC"
            #'(lambda ()
                (interactive)
                (insert "\N{THIN SPACE}"))
            LaTeX-mode-map)
  (bind-key "C-x A"
            #'(lambda ()
                (interactive)
                (insert "ٰ"))
            LaTeX-mode-map)
  (bind-key "A-َ"
            #'(lambda ()
                (interactive)
                (insert "ٰ"))
            LaTeX-mode-map)
  (bind-key "A-ه"
            #'(lambda ()
                (interactive)
                (insert "ۀ"))
            LaTeX-mode-map)
  (bind-key "A-د"
            #'(lambda ()
                (interactive)
                (insert "ذ"))
            LaTeX-mode-map)
  (bind-key "A-ت"
            #'(lambda ()
                (interactive)
                (insert "ة"))
            LaTeX-mode-map)

  (add-hook 'LaTeX-mode-hook
            #'(lambda
                ()
                (setq-local prettify-symbols-alist latex-prettify-symbols-alist)
                (prettify-symbols-mode 1))))

(use-package ledger-mode
  :mode "\\.ledger\\'"
  :load-path "~/src/ledger/lisp"
  :commands ledger-mode
  :bind ("C-c L" . my-ledger-start-entry)
  :preface
  (defun my-ledger-start-entry (&optional arg)
    (interactive "p")
    (find-file-other-window "/Volumes/Files/Accounts/ledger.dat")
    (goto-char (point-max))
    (skip-syntax-backward " ")
    (if (looking-at "\n\n")
        (goto-char (point-max))
      (delete-region (point) (point-max))
      (insert ?\n)
      (insert ?\n))
    (insert (format-time-string "%Y/%m/%d ")))

  (defun ledger-matchup ()
    (interactive)
    (while (re-search-forward "\\(\\S-+Unknown\\)\\s-+\\$\\([-,0-9.]+\\)"
                              nil t)
      (let ((account-beg (match-beginning 1))
            (account-end (match-end 1))
            (amount (match-string 2))
            account answer)
        (goto-char account-beg)
        (set-window-point (get-buffer-window) (point))
        (recenter)
        (redraw-display)
        (with-current-buffer (get-buffer "nrl-mastercard-old.dat")
          (goto-char (point-min))
          (when (re-search-forward (concat "\\(\\S-+\\)\\s-+\\$" amount)
                                   nil t)
            (setq account (match-string 1))
            (goto-char (match-beginning 1))
            (set-window-point (get-buffer-window) (point))
            (recenter)
            (redraw-display)
            (setq answer
                  (read-char (format "Is this a match for %s (y/n)? "
                                     account)))))
        (when (eq answer ?y)
          (goto-char account-beg)
          (delete-region account-beg account-end)
          (insert account))
        (forward-line))))

  (defun my-ledger-add-symbols ()
    (interactive)
    (while (re-search-forward " \\(BOT\\|SOLD\\) [+-][0-9,]+ \\(\\S-+\\) " nil t)
      (forward-line 2)
      (goto-char (line-beginning-position))
      (insert "    ; Symbol: " (match-string 2) ?\n)))
  :config
  (add-hook 'ledger-mode-hook
            #'(lambda ()
                (auto-fill-mode -1))))

(use-package link-hint
  :defer 10
  :bind ("C-c C-o" . link-hint-open-link)
  :config
  (add-hook 'eww-mode-hook
            #'(lambda () (bind-key "f" #'link-hint-open-link eww-mode-map)))
  (add-hook 'w3m-mode-hook
            #'(lambda () (bind-key "f" #'link-hint-open-link w3m-mode-map))))

(use-package lively
  :bind ("C-x C-E" . lively))

(use-package lisp-mode
  :defer t
  :hook ((emacs-lisp-mode lisp-mode)
         . (lambda () (add-hook 'after-save-hook #'check-parens nil t)))
  :init
  (dolist (mode '(ielm-mode
                  inferior-emacs-lisp-mode
                  inferior-lisp-mode
                  lisp-interaction-mode
                  lisp-mode
                  emacs-lisp-mode))
    (font-lock-add-keywords
     mode
     '(("(\\(lambda\\)\\>"
        (0 (ignore
            (compose-region (match-beginning 1)
                            (match-end 1) ?λ))))
       ("(\\(ert-deftest\\)\\>[         '(]*\\(setf[    ]+\\sw+\\|\\sw+\\)?"
        (1 font-lock-keyword-face)
        (2 font-lock-function-name-face
           nil t))))))

(use-package lispy
  :commands lispy-mode
  :bind (:map lispy-mode-map
              ("M-j"))
  :bind (:map emacs-lisp-mode-map
              ("C-1"     . lispy-describe-inline)
              ("C-2"     . lispy-arglist-inline)
              ("C-c C-j" . lispy-goto)))

(use-package llvm-mode
  :disabled t
  :mode "\\.ll\\'")

(use-package lsp-haskell
  :after lsp-mode
  :config
  (setq lsp-haskell-server-path "haskell-language-server-wrapper"))

(use-package lsp-mode
  :commands lsp
  :custom
  (lsp-completion-enable t)
  (lsp-completion-provider :capf)
  (lsp-eldoc-enable-hover nil)
  (lsp-eldoc-render-all t)
  (lsp-enable-eldoc nil)
  (lsp-haskell-process-args-hie '("-l" "/tmp/hie.log"))
  (lsp-headerline-breadcrumb-enable nil)
  (lsp-highlight-symbol-at-point nil)
  (lsp-idle-delay 0.6)
  (lsp-inhibit-message t)
  (lsp-prefer-capf t)
  (lsp-prefer-flymake nil)
  ;; what to use when checking on-save. "check" is default, I prefer clippy
  (lsp-rust-analyzer-cargo-watch-command "clippy")
  (lsp-rust-analyzer-server-display-inlay-hints t)
  (lsp-rust-clippy-preference "on")
  :config
  (use-package lsp-lens)
  (use-package lsp-headerline)
  (setq read-process-output-max 16384
        gc-cons-threshold 1600000))

(use-package lsp-ui
  :after lsp-mode
  :hook (lsp-mode . lsp-ui-mode)
  :custom
  (lsp-ui-doc-enable nil)
  (lsp-ui-doc-max-height 60)
  (lsp-ui-doc-text-scale-level 4)
  (lsp-ui-peek-always-show t)
  (lsp-ui-sideline-enable nil)
  (lsp-ui-sideline-show-diagnostics nil)
  (lsp-ui-sideline-show-hover t)
  :config
  (define-key lsp-ui-mode-map [remap xref-find-definitions]
    #'lsp-ui-peek-find-definitions)
  (define-key lsp-ui-mode-map [remap xref-find-references]
    #'lsp-ui-peek-find-references))

(use-package lua-mode
  :mode "\\.lua\\'"
  :interpreter "lua")

(use-package macrostep
  :bind ("C-c e m" . macrostep-expand))

(use-package magit
  :bind (("C-x g" . magit-status)
         ("C-x G" . magit-status-with-prefix))
  :bind (:map magit-mode-map
              ("U" . magit-unstage-all)
              ("M-h") ("M-s") ("M-m") ("M-w"))
  :bind (:map magit-file-section-map ("<C-return>"))
  :bind (:map magit-hunk-section-map ("<C-return>"))
  :preface
  ;; History can be viewed with:
  ;; git log refs/snapshots/$(git symbolic-ref HEAD)
  (defun magit-monitor (&optional no-display)
    "Start git-monitor in the current directory."
    (interactive)
    (let* ((path (file-truename
                  (directory-file-name
                   (expand-file-name default-directory))))
           (name (format "*git-monitor: %s*"
                         (file-name-nondirectory path))))
      (unless (and (get-buffer name)
                   (with-current-buffer (get-buffer name)
                     (string= path (directory-file-name default-directory))))
        (with-current-buffer (get-buffer-create name)
          (cd path)
          (if (file-regular-p ".git")
              (let ((branch (string-chop-newline
                             (shell-command-to-string
                              "git branch --show-current")))
                    (repo
                     (with-temp-buffer
                       (insert-file-contents-literally ".git")
                       (goto-char (point-min))
                       (and (looking-at "^gitdir: \\(.+?/\\.git/\\)")
                            (match-string 1)))))
                (when repo
                  (ignore-errors
                    (start-process "*git-monitor*" (current-buffer)
                                   "git-monitor"
                                   "--git-dir" repo
                                   "--work-dir" path
                                   "-r" (concat "refs/heads/" branch)))))
            (ignore-errors
              (start-process "*git-monitor*" (current-buffer)
                             "git-monitor" "--work-dir" path)))))))

  (defun magit-status-with-prefix ()
    (interactive)
    (let ((current-prefix-arg '(4)))
      (call-interactively 'magit-status)))

  (defun endless/visit-pull-request-url ()
    "Visit the current branch's PR on Github."
    (interactive)
    (browse-url
     (format "https://github.com/%s/pull/new/%s"
             (replace-regexp-in-string
              "\\`.+github\\.com:\\(.+?\\)\\(\\.git\\)?\\'" "\\1"
              (magit-get "remote" (magit-get-remote) "url"))
             (magit-get-current-branch))))

  :hook (magit-mode . hl-line-mode)
  :config
  (use-package magit-commit
    :config
    (use-package git-commit))

  (use-package magit-files
    :config
    ;;(global-magit-file-mode)
    )

  (add-hook 'magit-status-mode-hook #'(lambda () (magit-monitor t)))

  (define-key magit-mode-map "G" #'endless/visit-pull-request-url)

  (eval-after-load 'magit-pull
    '(transient-insert-suffix 'magit-pull "p"
       '("F" "default" magit-fetch-from-upstream)))

  (eval-after-load 'magit-push
    '(transient-insert-suffix 'magit-push "p"
       '("P" "default" magit-push-current-to-upstream)))

  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-status-headers)
  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-tags-header)
  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-unpushed-to-pushremote)
  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-unpushed-to-upstream-or-recent)
  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-unpulled-from-pushremote)
  ;; (remove-hook 'magit-status-sections-hook 'magit-insert-unpulled-from-upstream)
  )

(use-package magit-popup
  :defer t)

(use-package magit-imerge
  ;; jww (2017-12-10): Need to configure.
  :disabled t
  :after magit)

(use-package malyon
  :commands malyon
  :config
  (defun replace-invisiclues ()
    (interactive)
    (query-replace-regexp
     "^\\( +\\)\\(\\([A-Z]\\)\\. \\)?\\(.+\\)"
     (quote (replace-eval-replacement
             concat "\\1\\2" (replace-quote (rot13 (match-string 4)))))
     nil (if (use-region-p) (region-beginning))
     (if (use-region-p) (region-end)) nil nil)))

(use-package markdown-mode
  :mode (("\\`README\\.md\\'" . gfm-mode)
         ("\\.md\\'"          . markdown-mode)
         ("\\.markdown\\'"    . markdown-mode))
  :init (setq markdown-command "multimarkdown"))

(use-package markdown-preview-mode
  :after markdown-mode
  :config
  (setq markdown-preview-stylesheets
        (list (concat "https://github.com/dmarcotte/github-markdown-preview/"
                      "blob/master/data/css/github.css"))))

(use-package math-symbol-lists
  :defer t)

(use-package mediawiki
  :commands mediawiki-open)

(use-package memory-usage
  :commands memory-usage)

(use-package mhtml-mode
  :bind (:map html-mode-map
              ("<return>" . newline-and-indent)))

(use-package mic-paren
  :defer 5
  :config
  (paren-activate))

(use-package midnight
  :bind ("C-c z" . clean-buffer-list))

(use-package minibuffer
  :config
  (defun my-minibuffer-setup-hook ()
    (setq gc-cons-threshold most-positive-fixnum))

  (defun my-minibuffer-exit-hook ()
    (setq gc-cons-threshold 800000))

  (add-hook 'minibuffer-setup-hook #'my-minibuffer-setup-hook)
  (add-hook 'minibuffer-exit-hook #'my-minibuffer-exit-hook))

(use-package minimap
  :commands minimap-mode)

(use-package mmm-mode
  :defer t)

(use-package moccur-edit
  :after color-moccur)

(use-package monitor
  :defer t
  :init
  (autoload #'define-monitor "monitor"))

(use-package motoko-mode
  :disabled t
  :mode (("\\.mo\\'" . motoko-mode)))

(use-package mule
  :no-require t
  :config
  (prefer-coding-system 'utf-8)
  (set-terminal-coding-system 'utf-8)
  (setq x-select-request-type '(UTF8_STRING COMPOUND_TEXT TEXT STRING)))

(use-package multi-term
  :bind (("C-c t" . multi-term-next)
         ("C-c T" . multi-term))
  :init
  (defun screen ()
    (interactive)
    (let (term-buffer)
      ;; Set buffer.
      (setq term-buffer
            (let ((multi-term-program (executable-find "screen"))
                  (multi-term-program-switches "-DR"))
              (multi-term-get-buffer)))
      (set-buffer term-buffer)
      (multi-term-internal)
      (switch-to-buffer term-buffer)))

  :config
  (require 'term)

  (defalias 'my-term-send-raw-at-prompt 'term-send-raw)

  (defun my-term-end-of-buffer ()
    (interactive)
    (call-interactively #'end-of-buffer)
    (if (and (eobp) (bolp))
        (delete-char -1)))

  (defadvice term-process-pager (after term-process-rebind-keys activate)
    (define-key term-pager-break-map  "\177" 'term-pager-back-page)))

(use-package multifiles
  :bind ("C-c m f" . mf/mirror-region-in-multifile))

(use-package multiple-cursors
  :after phi-search
  :defer 5

  ;; - Sometimes you end up with cursors outside of your view. You can scroll
  ;;   the screen to center on each cursor with `C-v` and `M-v`.
  ;;
  ;; - If you get out of multiple-cursors-mode and yank - it will yank only
  ;;   from the kill-ring of main cursor. To yank from the kill-rings of every
  ;;   cursor use yank-rectangle, normally found at C-x r y.

  :bind (("<C-m> ^"     . mc/edit-beginnings-of-lines)
         ("<C-m> `"     . mc/edit-beginnings-of-lines)
         ("<C-m> $"     . mc/edit-ends-of-lines)
         ("<C-m> '"     . mc/edit-ends-of-lines)
         ("<C-m> R"     . mc/reverse-regions)
         ("<C-m> S"     . mc/sort-regions)
         ("<C-m> W"     . mc/mark-all-words-like-this)
         ("<C-m> Y"     . mc/mark-all-symbols-like-this)
         ("<C-m> a"     . mc/mark-all-like-this-dwim)
         ("<C-m> c"     . mc/mark-all-dwim)
         ("<C-m> l"     . mc/insert-letters)
         ("<C-m> n"     . mc/insert-numbers)
         ("<C-m> r"     . mc/mark-all-in-region)
         ("<C-m> s"     . set-rectangular-region-anchor)
         ("<C-m> %"     . mc/mark-all-in-region-regexp)
         ("<C-m> t"     . mc/mark-sgml-tag-pair)
         ("<C-m> w"     . mc/mark-next-like-this-word)
         ("<C-m> x"     . mc/mark-more-like-this-extended)
         ("<C-m> y"     . mc/mark-next-like-this-symbol)
         ("<C-m> C-x"   . reactivate-mark)
         ("<C-m> C-SPC" . mc/mark-pop)
         ("<C-m> ("     . mc/mark-all-symbols-like-this-in-defun)
         ("<C-m> C-("   . mc/mark-all-words-like-this-in-defun)
         ("<C-m> M-("   . mc/mark-all-like-this-in-defun)
         ("<C-m> ["     . mc/vertical-align-with-space)
         ("<C-m> {"     . mc/vertical-align)

         ("S-<down-mouse-1>")
         ("S-<mouse-1>" . mc/add-cursor-on-click))

  :bind (:map selected-keymap
              ("c"   . mc/edit-lines)
              ("."   . mc/mark-next-like-this)
              ("<"   . mc/unmark-next-like-this)
              ("C->" . mc/skip-to-next-like-this)
              (","   . mc/mark-previous-like-this)
              (">"   . mc/unmark-previous-like-this)
              ("C-<" . mc/skip-to-previous-like-this)
              ("y"   . mc/mark-next-symbol-like-this)
              ("Y"   . mc/mark-previous-symbol-like-this)
              ("w"   . mc/mark-next-word-like-this)
              ("W"   . mc/mark-previous-word-like-this))

  :preface
  (defun reactivate-mark ()
    (interactive)
    (activate-mark)))

(use-package mc-calc
  :after multiple-cursors
  :bind (("<C-m> = c" . mc-calc)
         ("<C-m> = =" . mc-calc-eval)
         ("<C-m> = g" . mc-calc-grab)
         ("<C-m> = b" . mc-calc-copy-to-buffer)))

(use-package mc-extras
  :after multiple-cursors
  :bind (("<C-m> M-C-f" . mc/mark-next-sexps)
         ("<C-m> M-C-b" . mc/mark-previous-sexps)
         ("<C-m> <"     . mc/mark-all-above)
         ("<C-m> >"     . mc/mark-all-below)
         ("<C-m> C-d"   . mc/remove-current-cursor)
         ("<C-m> C-k"   . mc/remove-cursors-at-eol)
         ("<C-m> M-d"   . mc/remove-duplicated-cursors)
         ("<C-m> |"     . mc/move-to-column)
         ("<C-m> ~"     . mc/compare-chars)))

(use-package mc-freeze
  :after multiple-cursors
  :bind ("<C-m> f" . mc/freeze-fake-cursors-dwim))

(use-package mc-rect
  :after multiple-cursors
  :bind ("<C-m> ]" . mc/rect-rectangle-to-multiple-cursors))

(use-package nginx-mode
  :commands nginx-mode)

(use-package nix-shell
  :no-require t
  :init
  (defun nix-shell ()
    (interactive)
    (let ((explicit-shell-file-name "shell")
          (explicit-shell-args nil))
      (call-interactively 'shell))))

(use-package nix-mode
  :mode "\\.nix\\'")

(use-package nix-update
  :load-path "lisp/nix-update"
  :bind ("C-c U" . nix-update-fetch))

(use-package nov
  :mode ("\\.epub\\'" . nov-mode))

(use-package nroff-mode
  :commands nroff-mode
  :config
  (defun update-nroff-timestamp ()
    (save-excursion
      (goto-char (point-min))
      (when (re-search-forward "^\\.Dd " nil t)
        (let ((stamp (format-time-string "%B %e, %Y")))
          (unless (looking-at stamp)
            (delete-region (point) (line-end-position))
            (insert stamp)
            (let (after-save-hook)
              (save-buffer)))))))

  (add-hook 'nroff-mode-hook
            #'(lambda () (add-hook 'after-save-hook #'update-nroff-timestamp nil t))))

(use-package nxml-mode
  :commands nxml-mode
  :bind (:map nxml-mode-map
              ("<return>" . newline-and-indent)
              ("C-c M-h"  . tidy-xml-buffer))
  :preface
  (defun tidy-xml-buffer ()
    (interactive)
    (save-excursion
      (call-process-region (point-min) (point-max) "tidy" t t nil
                           "-xml" "-i" "-wrap" "0" "-omit" "-q" "-utf8")))
  :init
  (defalias 'xml-mode 'nxml-mode)
  :config
  (autoload 'sgml-skip-tag-forward "sgml-mode")
  (add-to-list 'hs-special-modes-alist
               '(nxml-mode
                 "<!--\\|<[^/>]*[^/]>"
                 "-->\\|</[^/>]*[^/]>"
                 "<!--"
                 sgml-skip-tag-forward
                 nil)))

(use-package olivetti
  :commands olivetti-mode)

(use-package operate-on-number
  :bind ("C-c N" . operate-on-number-at-point))

(use-package origami
  :hook (rust-mode . origami-mode)
  :bind (:map origami-mode-map
              ("C-, C-h" . origami-toggle-node))
  :init
  ;; We need to tell origami how to work under rust mode
  (with-eval-after-load "origami"
    (add-to-list 'origami-parser-alist '(rust-mode . origami-c-style-parser)))
  :custom
  ;; Highlights the line the fold starts on
  (origami-show-fold-header t)
  :config
  (defun origami-header-overlay-range (fold-overlay)
    "Given a `fold-overlay', return the range that the corresponding
header overlay should cover. Result is a cons cell of (begin . end)."
    (with-current-buffer (overlay-buffer fold-overlay)
      (let ((fold-begin
             (save-excursion
               (goto-char (overlay-start fold-overlay))
               (line-beginning-position)))
            (fold-end
             ;; Find the end of the folded region -- include the following
             ;; newline if possible. The header will span the entire fold.
             (save-excursion
               (save-match-data
                 (goto-char (overlay-end fold-overlay))
                 (when (looking-at ".")
                   (forward-char 1)
                   (when (looking-at "\n")
                     (forward-char 1)))
                 (point)))))
        (cons fold-begin fold-end)))))

(use-package outline
  :diminish outline-minor-mode
  :hook ((emacs-lisp-mode LaTeX-mode) . outline-minor-mode))

(use-package ovpn-mode
  :commands ovpn
  :config
  (advice-add
   'ovpn-mode-pull-authinfo :around
   #'(lambda (ad-do-it config)
       (if (string= config "OpenVPN_PoC_2019_johnwiegley.ovpn")
           (list "johnwiegley"
                 (concat (lookup-password "demonet OpenVPN" "johnwiegley" 80)
                         (password-store--run "otp" "demonet OpenVPN")))
         (funcall ad-do-it config)))))

(use-package package-lint
  :commands package-lint-current-buffer)

(use-package pact-mode
  :mode "\\.pact\\'"
  :config
  (add-hook 'pact-mode-hook
            #'(lambda ()
                (bind-key "C-c C-c"
                          #'(lambda () (interactive)
                              (save-excursion
                                (call-interactively 'pact-compile)))
                          'slime-mode-map))))

(use-package pandoc-mode
  :hook (markdown-mode
         (pandoc-mode   . pandoc-load-default-settings)))

(use-package paradox
  :commands paradox-list-packages)

(use-package paredit
  :diminish
  :hook ((lisp-mode emacs-lisp-mode) . paredit-mode)
  :bind (:map paredit-mode-map
              ("[")
              ("M-k"   . paredit-raise-sexp)
              ("M-I"   . paredit-splice-sexp)
              ("C-M-l" . paredit-recentre-on-sexp)
              ("C-c ( n"   . paredit-add-to-next-list)
              ("C-c ( p"   . paredit-add-to-previous-list)
              ("C-c ( j"   . paredit-join-with-next-list)
              ("C-c ( J"   . paredit-join-with-previous-list))
  :bind (:map lisp-mode-map       ("<return>" . paredit-newline))
  :bind (:map emacs-lisp-mode-map ("<return>" . paredit-newline))
  :hook (paredit-mode
         . (lambda ()
             (unbind-key "M-r" paredit-mode-map)
             (unbind-key "M-s" paredit-mode-map)))
  :config
  (require 'eldoc)
  (eldoc-add-command 'paredit-backward-delete
                     'paredit-close-round))

(use-package paredit-ext
  :after paredit)

(use-package pass
  :commands (pass pass-view-mode)
  :mode ("\\.passwords/.*\\.gpg\\'" . pass-view-mode)
  :preface
  (defun insert-password ()
    (interactive)
    (shell-command "apg -m24 -x24 -a1 -n1" t))

  (add-hook 'pass-view-mode-hook #'pass-view--prepare-otp))

(use-package password-store
  :defer 5
  :commands (password-store-insert
             password-store-copy
             password-store-get)
  :config
  (defun password-store--run-edit (entry)
    (require 'pass)
    (find-file (concat (expand-file-name entry (password-store-dir)) ".gpg")))

  (defun password-store-insert (entry login password)
    "Insert a new ENTRY containing PASSWORD."
    (interactive (list (read-string "Password entry: ")
                       (read-string "Login: ")
                       (read-passwd "Password: " t)))
    (message "%s" (shell-command-to-string
                   (if (string= "" login)
                       (format "echo %s | %s insert -m -f %s"
                               (shell-quote-argument password)
                               password-store-executable
                               (shell-quote-argument entry))
                     (format "echo -e '%s\nlogin: %s' | %s insert -m -f %s"
                             password login password-store-executable
                             (shell-quote-argument entry)))))))

(use-package password-store-otp
  :defer t
  :config
  (defun password-store-otp-append-from-image (entry)
    "Check clipboard for an image and scan it to get an OTP URI,
append it to ENTRY."
    (interactive (list (read-string "Password entry: ")))
    (let ((qr-image-filename (password-store-otp--get-qr-image-filename entry)))
      (when (not (zerop (call-process "screencapture" nil nil nil
                                      "-T5" qr-image-filename)))
        (error "Couldn't get image from clipboard"))
      (with-temp-buffer
        (condition-case nil
            (call-process "zbarimg" nil t nil "-q" "--raw"
                          qr-image-filename)
          (error
           (error "It seems you don't have `zbar-tools' installed")))
        (password-store-otp-append
         entry
         (buffer-substring (point-min) (point-max))))
      (when (not password-store-otp-screenshots-path)
        (delete-file qr-image-filename)))))

(use-package pcre2el
  :commands (rxt-mode rxt-global-mode))

(use-package pdf-tools
  :defer 15
  :magic ("%PDF" . pdf-view-mode)
  :config
  (dolist
      (pkg
       '(pdf-annot pdf-cache pdf-dev pdf-history pdf-info pdf-isearch
                   pdf-links pdf-misc pdf-occur pdf-outline pdf-sync
                   pdf-util pdf-view pdf-virtual))
    (require pkg))
  (pdf-tools-install))

(use-package per-window-point
  :defer 5
  :commands pwp-mode
  :config
  (pwp-mode 1))

(use-package persistent-scratch
  :unless (or (null window-system)
              alternate-emacs
              noninteractive)
  :defer 5
  :config
  (persistent-scratch-autosave-mode)
  (with-demoted-errors "Error: %S"
    (persistent-scratch-setup-default))
  :commands persistent-scratch-setup-default)

(use-package personal
  :init
  (define-key key-translation-map (kbd "A-TAB") (kbd "C-TAB"))

  :commands unfill-region
  :bind (("M-L"  . mark-line)
         ("M-S"  . mark-sentence)
         ("M-j"  . delete-indentation-forward)

         ("M-D"  . my-open-Messages)
         ("M-R"  . my-open-PathFinder)
         ("M-K"  . my-open-KeyboardMaestro)

         ("C-c )"   . close-all-parentheses)
         ("C-c 0"   . recursive-edit-preserving-window-config-pop)
         ("C-c 1"   . recursive-edit-preserving-window-config)
         ("C-c C-0" . copy-current-buffer-name)
         ("C-c C-z" . delete-to-end-of-buffer)
         ("C-c M-q" . unfill-paragraph)
         ("C-c e P" . check-papers)
         ("C-c e b" . do-eval-buffer)
         ("C-c e r" . do-eval-region)
         ("C-c e s" . scratch)
         ("C-c n u" . insert-user-timestamp)
         ("C-x C-d" . duplicate-line)
         ("C-x C-v" . find-alternate-file-with-sudo)
         ("C-x K"   . delete-current-buffer-file)
         ("C-x M-q" . refill-paragraph)
         ("C-x C-n" . next-line)
         ("C-x C-p" . previous-line))
  :preface
  (defun my-open-Messages ()
    (interactive)
    (call-process "/usr/bin/open" nil nil nil
                  "/Applications/Messages.app"))

  (defun my-open-PathFinder ()
    (interactive)
    (call-process "/usr/bin/open" nil nil nil
                  (expand-file-name
                   "~/Applications/Path Finder.app")))

  (defun my-open-KeyboardMaestro ()
    (interactive)
    (call-process "/usr/bin/open" nil nil nil
                  (expand-file-name
                   "~/Applications/Keyboard Maestro.app")))

  :init
  (bind-keys ("<C-M-backspace>" . backward-kill-sexp)

             ("M-'"   . insert-pair)
             ("M-J"   . delete-indentation)
             ("M-\""  . insert-pair)
             ("M-`"   . other-frame)
             ("M-g c" . goto-char)

             ("C-c SPC" . just-one-space)
             ("C-c M-;" . comment-and-copy)
             ("C-c e c" . cancel-debug-on-entry)
             ("C-c e d" . debug-on-entry)
             ("C-c e e" . toggle-debug-on-error)
             ("C-c e f" . emacs-lisp-byte-compile-and-load)
             ("C-c e j" . emacs-lisp-mode)
             ("C-c e z" . byte-recompile-directory)
             ("C-c f"   . flush-lines)
             ("C-c g"   . goto-line)
             ("C-c k"   . keep-lines)
             ("C-c m k" . kmacro-keymap)
             ("C-c m m" . emacs-toggle-size)
             ("C-c q"   . fill-region)
             ("C-c s"   . replace-string)
             ("C-c u"   . rename-uniquely)
             ("C-h e a" . apropos-value)
             ("C-h e e" . view-echo-area-messages)
             ("C-h e f" . find-function)
             ("C-h e k" . find-function-on-key)
             ("C-h e v" . find-variable)
             ("C-h h")
             ("C-h v"   . describe-variable)
             ("C-x C-e" . pp-eval-last-sexp)
             ("C-x d"   . delete-whitespace-rectangle)
             ("C-x t"   . toggle-truncate-lines)
             ("C-z"     . delete-other-windows))

  :init
  (defun my-adjust-created-frame ()
    (set-frame-font
     "-*-DejaVu Sans Mono-normal-normal-normal-*-16-*-*-*-m-0-iso10646-1")
    (set-frame-size (selected-frame) 75 50)
    (set-frame-position (selected-frame) 10 35))

  (advice-add 'make-frame-command :after #'my-adjust-created-frame))

(use-package phi-search
  :defer 5)

(use-package phi-search-mc
  :after (phi-search multiple-cursors)
  :config
  (phi-search-mc/setup-keys)
  (add-hook 'isearch-mode-mode #'phi-search-from-isearch-mc/setup-keys))

(use-package plantuml-mode
  :mode "\\.plantuml\\'")

(use-package po-mode
  :disabled t
  :mode "\\.\\(po\\'\\|po\\.\\)")

(use-package popup-ruler
  :disabled t
  :bind ("C-c R" . popup-ruler))

(use-package pp-c-l
  :hook (prog-mode . pretty-control-l-mode))

(use-package prodigy
  :commands prodigy)

(use-package projectile
  :defer 5
  :diminish
  :bind* (("C-c TAB" . projectile-find-other-file)
          ("C-c P" . (lambda () (interactive)
                       (projectile-cleanup-known-projects)
                       (projectile-discover-projects-in-search-path))))
  :bind-keymap ("C-c p" . projectile-command-map)
  :config
  (projectile-global-mode)

  (defun my-projectile-invalidate-cache (&rest _args)
    ;; We ignore the args to `magit-checkout'.
    (projectile-invalidate-cache nil))

  (eval-after-load 'magit-branch
    '(progn
       (advice-add 'magit-checkout
                   :after #'my-projectile-invalidate-cache)
       (advice-add 'magit-branch-and-checkout
                   :after #'my-projectile-invalidate-cache))))

(use-package proof-site
  :preface
  (defun my-layout-proof-windows ()
    (interactive)
    (proof-layout-windows)
    (proof-prf))

  :config
  (use-package coq
    :defer t
    :config
    (defalias 'coq-SearchPattern #'coq-SearchIsos)

    (bind-keys :map coq-mode-map
               ("M-RET"       . proof-goto-point)
               ("RET"         . newline-and-indent)
               ("C-c h")
               ("C-c C-p"     . my-layout-proof-windows)
               ("C-c C-a C-s" . coq-Search)
               ("C-c C-a C-o" . coq-SearchPattern)
               ("C-c C-a C-a" . coq-Search)
               ("C-c C-a C-r" . coq-SearchRewrite))

    (add-hook 'coq-mode-hook
              #'(lambda ()
                  (set-input-method "Agda")
                  (holes-mode -1)
                  (when (featurep 'company)
                    (company-coq-mode 1))
                  (abbrev-mode -1)

                  (bind-key "A-g" #'(lambda () (interactive) (insert "Γ")) 'coq-mode-map)
                  (bind-key "A-t" #'(lambda () (interactive) (insert "τ")) 'coq-mode-map)
                  (bind-key "A-r" #'(lambda () (interactive) (insert "ρ")) 'coq-mode-map)
                  (bind-key "A-k" #'(lambda () (interactive) (insert "κ")) 'coq-mode-map)

                  (set (make-local-variable 'fill-nobreak-predicate)
                       #'(lambda ()
                           (pcase (get-text-property (point) 'face)
                             ('font-lock-comment-face nil)
                             ((and (pred listp)
                                   x (guard (memq 'font-lock-comment-face x)))
                              nil)
                             (_ t)))))))

  (use-package pg-user
    :defer t
    :config
    (defadvice proof-retract-buffer
        (around my-proof-retract-buffer activate)
      (condition-case err ad-do-it
        (error (shell-command "killall coqtop"))))))

(use-package protobuf-mode
  :mode "\\.proto\\'")

(use-package prover
  :after coq)

(use-package ps-print
  :defer t
  :preface
  (defun ps-spool-to-pdf (beg end &rest ignore)
    (interactive "r")
    (let ((temp-file (concat (make-temp-name "ps2pdf") ".pdf")))
      (call-process-region beg end (executable-find "ps2pdf")
                           nil nil nil "-" temp-file)
      (call-process (executable-find "open") nil nil nil temp-file)))
  :config
  (setq ps-print-region-function 'ps-spool-to-pdf))

(use-package python-mode
  :mode "\\.py\\'"
  :interpreter "python"
  :bind (:map python-mode-map
              ("C-c c")
              ("C-c C-z" . python-shell))
  :config
  (defvar python-mode-initialized nil)

  (defun my-python-mode-hook ()
    (unless python-mode-initialized
      (setq python-mode-initialized t)

      (info-lookup-add-help
       :mode 'python-mode
       :regexp "[a-zA-Z_0-9.]+"
       :doc-spec
       '(("(python)Python Module Index" )
         ("(python)Index"
          (lambda
            (item)
            (cond
             ((string-match
               "\\([A-Za-z0-9_]+\\)() (in module \\([A-Za-z0-9_.]+\\))" item)
              (format "%s.%s" (match-string 2 item)
                      (match-string 1 item)))))))))

    (set (make-local-variable 'parens-require-spaces) nil)
    (setq indent-tabs-mode nil))

  (add-hook 'python-mode-hook #'my-python-mode-hook))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))

(use-package rainbow-mode
  :commands rainbow-mode)

(use-package re-builder
  :bind (("C-c R" . re-builder))
  :config (setq reb-re-syntax 'string))

(use-package recentf
  :defer 10
  :commands (recentf-mode
             recentf-add-file
             recentf-apply-filename-handlers)
  :preface
  (defun recentf-add-dired-directory ()
    (if (and dired-directory
             (file-directory-p dired-directory)
             (not (string= "/" dired-directory)))
        (let ((last-idx (1- (length dired-directory))))
          (recentf-add-file
           (if (= ?/ (aref dired-directory last-idx))
               (substring dired-directory 0 last-idx)
             dired-directory)))))
  :hook (dired-mode . recentf-add-dired-directory)
  :config
  (recentf-mode 1))

(use-package rect
  :bind ("C-c ]" . rectangle-mark-mode))

(use-package redshank
  :diminish
  :hook ((lisp-mode emacs-lisp-mode) . redshank-mode))

(use-package reftex
  :after auctex
  :hook (LaTeX-mode . reftex-mode))

(use-package regex-tool
  :load-path "lisp/regex-tool"
  :commands regex-tool)

(use-package repl-toggle
  ;; jww (2017-12-10): Need to configure.
  :disabled t)

(use-package restclient
  :mode ("\\.rest\\'" . restclient-mode))

(use-package reveal-in-osx-finder
  :no-require t
  :bind ("C-c M-v" .
         (lambda () (interactive)
           (call-process "/usr/bin/open" nil nil nil
                         "-R" (expand-file-name
                               (or (buffer-file-name)
                                   default-directory))))))

(use-package riscv-mode
  :commands riscv-mode)

(use-package rtags
  ;; jww (2018-01-09): https://github.com/Andersbakken/rtags/issues/1123
  :disabled t
  :load-path "~/.nix-profile/share/emacs/site-lisp/rtags"
  :commands rtags-mode
  :bind (("C-c . D" . rtags-dependency-tree)
         ("C-c . F" . rtags-fixit)
         ("C-c . R" . rtags-rename-symbol)
         ("C-c . T" . rtags-tagslist)
         ("C-c . d" . rtags-create-doxygen-comment)
         ("C-c . c" . rtags-display-summary)
         ("C-c . e" . rtags-print-enum-value-at-point)
         ("C-c . f" . rtags-find-file)
         ("C-c . i" . rtags-include-file)
         ("C-c . i" . rtags-symbol-info)
         ("C-c . m" . rtags-imenu)
         ("C-c . n" . rtags-next-match)
         ("C-c . p" . rtags-previous-match)
         ("C-c . r" . rtags-find-references)
         ("C-c . s" . rtags-find-symbol)
         ("C-c . v" . rtags-find-virtuals-at-point))
  :bind (:map c-mode-base-map
              ("M-." . rtags-find-symbol-at-point)))

(use-package ruby-mode
  :mode "\\.rb\\'"
  :interpreter "ruby"
  :bind (:map ruby-mode-map
              ("<return>" . my-ruby-smart-return))
  :preface
  (defun my-ruby-smart-return ()
    (interactive)
    (when (memq (char-after) '(?\| ?\" ?\'))
      (forward-char))
    (call-interactively 'newline-and-indent)))

(use-package rust-mode
  :mode "\\.rs\\'"
  :init
  (add-hook 'rust-mode-hook #'my-rust-mode-init)
  :preface
  (defun my-update-cargo-path (&rest _args)
    (setq cargo-process--custom-path-to-bin
          (executable-find "cargo")))

  (defun my-cargo-target-dir (path)
    (replace-regexp-in-string "kadena" "Products" path))

  (defun my-update-cargo-args (ad-do-it name command &optional last-cmd opens-external)
    (let* ((cmd (car (split-string command)))
           (new-args
            (if (member cmd '("build" "check" "clippy" "doc" "test"))
                (let ((args
                       (format "--target-dir=%s -j8"
                               (my-cargo-target-dir
                                (replace-regexp-in-string
                                 "target" "target--custom"
                                 (regexp-quote (getenv "CARGO_TARGET_DIR")))))))
                  (if (member cmd '("build"))
                      (concat "--message-format=short " args)
                    args))
              ""))
           (cargo-process--command-flags
            (pcase (split-string cargo-process--command-flags " -- ")
              (`(,before ,after)
               (concat before " " new-args " -- " after))
              (_ (concat cargo-process--command-flags new-args)))))
      (funcall ad-do-it name command last-cmd opens-external)))

  (defun my-rust-mode-init ()
    (advice-add 'direnv-update-directory-environment
                :after #'my-update-cargo-path)
    (advice-add 'cargo-process--start :around #'my-update-cargo-args)
    (direnv-update-environment default-directory)

    (cargo-minor-mode 1)
    (yas-minor-mode-on)

    (if dot-emacs-use-eglot
        (progn
          (require 'eglot)
          (when (functionp 'eglot)
            (bind-key "M-n" #'flymake-goto-next-error rust-mode-map)
            (bind-key "M-p" #'flymake-goto-prev-error rust-mode-map)

            (bind-key "C-c C-c v" #'(lambda ()
                                      (interactive)
                                      (shell-command "rustdocs std"))
                      rust-mode-map)

            (defun my-rust-project-find-function (dir)
              (let ((root (locate-dominating-file dir "Cargo.toml")))
                (and root (cons 'transient root))))

            (with-eval-after-load 'project
              (add-to-list 'project-find-functions 'my-rust-project-find-function))

            (let* ((current-server (eglot-current-server))
                   (live-p (and current-server (jsonrpc-running-p current-server))))
              (unless live-p
                (call-interactively #'eglot)))

            (company-mode 1)))
      (when (functionp 'lsp)
        (lsp)))))

(use-package rustic
  :disabled t
  :unless dot-emacs-use-eglot
  :mode ("\\.rs\\'" . rustic-mode)
  :preface
  (defun my-update-cargo-args (ad-do-it command &optional args)
    (let* ((cmd (car (split-string command)))
           (new-args
            (if (member cmd '("build" "check" "clippy" "doc" "test"))
                (let ((args
                       (format "--target-dir=%s -j8"
                               (my-cargo-target-dir
                                (replace-regexp-in-string
                                 "target" "target--custom"
                                 (regexp-quote (getenv "CARGO_TARGET_DIR")))))))
                  (if (member cmd '("build"))
                      (concat "--message-format=short " args)
                    args))
              ""))
           (args
            (pcase (and args (split-string args " -- "))
              (`(,before ,after)
               (concat before " " new-args " -- " after))
              (_ (concat args new-args)))))
      (funcall ad-do-it command args)))

  (defun my-rustic-mode-hook ()
    (advice-add 'rustic-run-cargo-command :around #'my-update-cargo-args)
    (direnv-update-environment default-directory)

    (setq lsp-rust-analyzer-server-command
          (list (substring (shell-command-to-string "which rust-analyzer") 0 -1)))
    (setq rustic-analyzer-command lsp-rust-analyzer-server-command)

    (flycheck-mode 1)
    (yas-minor-mode-on)

    ;; so that run C-c C-c C-r works without having to confirm, but don't try to
    ;; save rust buffers that are not file visiting. Once
    ;; https://github.com/brotzeit/rustic/issues/253 has been resolved this should
    ;; no longer be necessary.
    (when buffer-file-name
      (setq-local buffer-save-without-query t)))
  :bind (:map rustic-mode-map
              ("M-j"         . lsp-ui-imenu)
              ("M-?"         . lsp-find-references)
              ("C-c d"       . lsp-ui-doc-show)
              ("C-c h"       . lsp-ui-doc-hide)
              ("C-c C-c l"   . flycheck-list-errors)
              ("C-c C-c a"   . lsp-execute-code-action)
              ("C-c C-c r"   . lsp-rename)
              ("C-c C-c q"   . lsp-workspace-restart)
              ("C-c C-c Q"   . lsp-workspace-shutdown)
              ("C-c C-c s"   . lsp-rust-analyzer-status)
              ("C-c C-c C-y" . rustic-cargo-clippy))
  :config
  (setq rustic-format-on-save t)
  (add-hook 'rustic-mode-hook 'my-rustic-mode-hook))

(use-package rustic-flycheck
  :after rustic
  :config
  (defun my-rust-project-find-function (dir)
    (let ((root (locate-dominating-file dir "Cargo.toml")))
      (and root (cons 'transient root))))

  (with-eval-after-load 'project
    (add-to-list 'project-find-functions 'my-rust-project-find-function))

  (defun project-root (project)
    (car (project-roots project)))

  (defun first-dominating-file (file name)
    (aif (locate-dominating-file file name)
        (or (first-dominating-file
             (file-name-directory (directory-file-name it)) name) it)))

  (defun flycheck-rust-manifest-directory ()
    (and buffer-file-name
         (first-dominating-file buffer-file-name "Cargo.toml")))

  (require 'flycheck)
  (push 'rustic-clippy flycheck-checkers)

  (setq rustic-clippy-arguments
        (concat "--all-targets "
                "--all-features "
                "-- "
                "-D warnings "
                "-D clippy::all "
                "-D clippy::mem_forget "
                "-C debug-assertions=off"))

  (defun rustic-cargo-clippy (&optional arg)
    (interactive "P")
    (rustic-cargo-clippy-run
     (cond (arg
            (setq rustic-clippy-arguments (read-from-minibuffer "Cargo clippy arguments: " rustic-clippy-arguments)))
           ((eq major-mode 'rustic-popup-mode)
            rustic-clippy-arguments)
           (t rustic-clippy-arguments))))

  (setq rustic-flycheck-clippy-params
        (concat "--message-format=json " rustic-clippy-arguments)))

(use-package savehist
  :unless noninteractive
  :config
  (savehist-mode 1))

(use-package saveplace
  :unless noninteractive
  :config
  (save-place-mode 1))

(use-package sbt-mode
  :mode "\\.sbt\\'")

(use-package scala-mode
  :mode "\\.scala\\'")

(use-package sdcv-mode
  :bind ("C-c W" . my-sdcv-search)
  :config
  (defvar sdcv-index nil)

  (defun my-sdcv-search ()
    (interactive)
    (flet ((read-string
            (prompt &optional initial-input history
                    default-value inherit-input-method)
            (ivy-read
             prompt
             (or sdcv-index
                 (with-temp-buffer
                   (insert-file-contents
                    "~/.local/share/dictionary/websters.index")
                   (goto-char (point-max))
                   (insert ")")
                   (goto-char (point-min))
                   (insert "(")
                   (goto-char (point-min))
                   (setq sdcv-index (read (current-buffer)))))
             :history history
             :initial-input initial-input
             :def default-value)))
      (call-interactively #'sdcv-search))))

(use-package selected
  :demand t
  :diminish selected-minor-mode
  :bind (:map selected-keymap
              ("[" . align-code)
              ("f" . fill-region)
              ("U" . unfill-region)
              ("d" . downcase-region)
              ("r" . reverse-region)
              ("S" . sort-lines))
  :config
  (selected-global-mode 1))

(use-package separedit
  :commands separedit)

(use-package server
  :unless (or noninteractive
              alternate-emacs)
  :no-require
  :config
  (unless (file-exists-p "/tmp/johnw-emacs")
    (make-directory "/tmp/johnw-emacs")
    (chmod "/tmp/johnw-emacs" 448))
  (setq server-socket-dir "/tmp/johnw-emacs")
  :hook (after-init . server-start))

(use-package sh-script
  :defer t
  :init
  (defvar sh-script-initialized nil)
  (defun initialize-sh-script ()
    (unless sh-script-initialized
      (setq sh-script-initialized t)
      (info-lookup-add-help :mode 'shell-script-mode
                            :regexp ".*"
                            :doc-spec '(("(bash)Index")))))
  (add-hook 'shell-mode-hook #'initialize-sh-script))

(use-package shackle
  :unless alternate-emacs
  :defer 5
  :commands shackle-mode
  :config
  (shackle-mode 1))

(use-package shell-toggle
  :bind ("C-, C-z" . shell-toggle))

(use-package shift-number
  :bind (("C-c +" . shift-number-up)
         ("C-c -" . shift-number-down)))

(use-package sky-color-clock
  :defer 5
  :commands sky-color-clock
  :config
  (require 'solar)
  (sky-color-clock-initialize calendar-latitude)
  ;; (sky-color-clock-initialize-openweathermap-client
  ;;  (with-temp-buffer
  ;;    (insert-file-contents-literally "~/.config/weather/apikey")
  ;;    (buffer-substring (point-min) (1- (point-max))))
  ;;  5408211 ;; West Sacramento, CA, USA
  ;;  )
  (setq display-time-string-forms '((sky-color-clock))))

(use-package slime
  :commands slime
  :init
  ;; (unless (memq major-mode
  ;;               '(emacs-lisp-mode inferior-emacs-lisp-mode ielm-mode))
  ;;   ("M-q" . slime-reindent-defun)
  ;;   ("M-l" . slime-selector))

  (setq inferior-lisp-program "sbcl"
        slime-contribs '(slime-fancy)))

(use-package smart-mode-line
  :config
  ;; See https://github.com/Malabarba/smart-mode-line/issues/217
  (setq mode-line-format (delq 'mode-line-position mode-line-format))
  (sml/setup)
  (sml/apply-theme 'light)
  (remove-hook 'display-time-hook 'sml/propertize-time-string))

(use-package smart-newline
  :diminish
  :commands smart-newline-mode)

(use-package smartparens-config
  :commands smartparens-mode)

(use-package smartscan
  :defer 5
  :bind (:map smartscan-map
              ("C->" . smartscan-symbol-go-forward)
              ("C-<" . smartscan-symbol-go-backward)))

(use-package smerge-mode
  :commands smerge-mode)

(use-package smex
  :defer 5
  :commands smex)

(use-package sort-words
  :commands sort-words)

(use-package sql-indent
  :commands sqlind-minor-mode)

(use-package stock-quote
  :disabled t
  :demand t
  :commands stock-quote
  :config
  (when (file-readable-p "/tmp/icp.txt")
    (defun stock-quote-from-file (&rest ticker)
      (with-temp-buffer
        (insert-file-contents-literally "/tmp/icp.txt")
        (string-to-number (buffer-substring (point-min) (1- (point-max))))))
    (setq stock-quote-data-functions '(stock-quote-from-file))
    (stock-quote-in-modeline "ICP"))
  ;; :init
  ;; (load "~/src/thinkorswim/thinkorswim-el/thinkorswim")
  ;; :config
  ;; (setq tos-client-id
  ;;       (lookup-password "developer.tdameritrade.com.client-id"
  ;;                        tos-user-id 80))
  )

(use-package string-edit
  :disabled t
  :bind ("C-c C-'" . string-edit-at-point))

(use-package string-inflection
  :bind ("C-c `" . string-inflection-toggle))

(use-package super-save
  :diminish
  :commands super-save-mode
  :config
  (setq super-save-auto-save-when-idle t))

(use-package swift-mode
  :commands swift-mode)

(use-package swiper
  :after ivy
  :bind ("C-M-s" . swiper)
  :bind (:map swiper-map
              ("M-y" . yank)
              ("M-%" . swiper-query-replace)
              ("C-." . swiper-avy)
              ("M-c" . swiper-mc))
  :bind (:map isearch-mode-map
              ("C-o" . swiper-from-isearch)))

(use-package tagedit
  :commands tagedit-mode)

(use-package term
  :bind (:map term-mode-map
              ("C-c C-y" . term-paste)))

(use-package terraform-mode
  :mode "\.tf\\'")

(use-package texinfo
  :mode ("\\.texi\\'" . texinfo-mode)
  :config
  (defun my-texinfo-mode-hook ()
    (dolist (mapping '((?b . "emph")
                       (?c . "code")
                       (?s . "samp")
                       (?d . "dfn")
                       (?o . "option")
                       (?x . "pxref")))
      (local-set-key (vector (list 'alt (car mapping)))
                     `(lambda () (interactive)
                        (TeX-insert-macro ,(cdr mapping))))))

  (add-hook 'texinfo-mode-hook #'my-texinfo-mode-hook)

  (defun texinfo-outline-level ()
    ;; Calculate level of current texinfo outline heading.
    (require 'texinfo)
    (save-excursion
      (if (bobp)
          0
        (forward-char 1)
        (let* ((word (buffer-substring-no-properties
                      (point) (progn (forward-word 1) (point))))
               (entry (assoc word texinfo-section-list)))
          (if entry
              (nth 1 entry)
            5))))))

(use-package tidy
  :commands (tidy-buffer
             tidy-parse-config-file
             tidy-save-settings
             tidy-describe-options))

(use-package tla-mode
  :mode "\\.tla\\'"
  :config
  (add-hook 'tla-mode-hook
            #'(lambda ()
                (setq-local comment-start nil)
                (setq-local comment-end ""))))

(use-package tracking
  :defer t
  :config
  (define-key tracking-mode-map [(control ?c) space] #'tracking-next-buffer))

(use-package tramp
  :defer 5
  :config
  ;; jww (2018-02-20): Without this change, tramp ends up sending hundreds of
  ;; shell commands to the remote side to ask what the temporary directory is.
  (put 'temporary-file-directory 'standard-value '("/tmp"))
  (setq tramp-auto-save-directory "~/.cache/emacs/backups"
        tramp-persistency-file-name "~/.emacs.d/data/tramp"))

(use-package tramp-sh
  :defer t
  :config
  (add-to-list 'tramp-remote-path "/run/current-system/sw/bin"))

(use-package transpose-mark
  :commands (transpose-mark
             transpose-mark-line
             transpose-mark-region))

(use-package treemacs
  :commands treemacs)

(use-package tuareg
  :mode (("\\.ml[4ip]?\\'" . tuareg-mode)
         ("\\.eliomi?\\'"  . tuareg-mode)))

(use-package typo
  :commands typo-mode)

(use-package undo-propose
  :commands undo-propose)

(use-package unicode-fonts
  :config
  (unicode-fonts-setup)
  ;; (setq face-font-rescale-alist '((".*Scheher.*" . 1.8)))
  )

(use-package vagrant
  :commands (vagrant-up
             vagrant-ssh
             vagrant-halt
             vagrant-status)
  :config
  (vagrant-tramp-enable))

(use-package vagrant-tramp
  :after tramp
  :defer 5)

(use-package vdiff
  :commands (vdiff-files
             vdiff-files3
             vdiff-buffers
             vdiff-buffers3))

(use-package vimish-fold
  :bind (("C-c V f" . vimish-fold)
         ("C-c V d" . vimish-fold-delete)
         ("C-c V D" . vimish-fold-delete-all)))

(use-package visual-fill-column
  :commands visual-fill-column-mode)

(use-package visual-regexp
  :bind (("C-c r"   . vr/replace)
         ("C-c %"   . vr/query-replace)
         ("<C-m> /" . vr/mc-mark)))

(use-package virtual-auto-fill
  :commands virtual-auto-fill-mode)

(use-package vline
  :commands vline-mode)

(use-package w3m
  :commands (w3m-browse-url w3m-find-file))

(use-package wat-mode
  :mode "\\.was?t\\'")

(use-package web-mode
  :commands web-mode)

(use-package wgrep
  :defer 5)

(use-package which-func
  :hook (c-mode-common . which-function-mode))

(use-package which-key
  :defer 5
  :diminish
  :commands which-key-mode
  :config
  (which-key-mode))

(use-package whitespace
  :diminish (global-whitespace-mode
             whitespace-mode
             whitespace-newline-mode)
  :commands (whitespace-buffer
             whitespace-cleanup
             whitespace-mode
             whitespace-turn-off)
  :preface
  (defvar normalize-hook nil)

  (defun normalize-file ()
    (interactive)
    (save-excursion
      (goto-char (point-min))
      (whitespace-cleanup)
      (run-hook-with-args normalize-hook)
      (delete-trailing-whitespace)
      (goto-char (point-max))
      (delete-blank-lines)
      (set-buffer-file-coding-system 'unix)
      (goto-char (point-min))
      (while (re-search-forward "\r$" nil t)
        (replace-match ""))
      (set-buffer-file-coding-system 'utf-8)
      (let ((require-final-newline t))
        (save-buffer))))

  (defun maybe-turn-on-whitespace ()
    "depending on the file, maybe clean up whitespace."
    (when (and (not (or (memq major-mode '(markdown-mode))
                        (and buffer-file-name
                             (string-match "\\(\\.texi\\|COMMIT_EDITMSG\\)\\'"
                                           buffer-file-name))))
               (locate-dominating-file default-directory ".clean")
               (not (locate-dominating-file default-directory ".noclean")))
      (whitespace-mode 1)
      ;; For some reason, having these in settings.el gets ignored if
      ;; whitespace loads lazily.
      (setq whitespace-auto-cleanup t
            whitespace-line-column 80
            whitespace-rescan-timer-time nil
            whitespace-silent t
            whitespace-style '(face trailing lines space-before-tab empty))
      (add-hook 'write-contents-hooks
                #'(lambda () (ignore (whitespace-cleanup))) nil t)
      (whitespace-cleanup)))

  :init
  (add-hook 'find-file-hooks #'maybe-turn-on-whitespace t)

  :config
  (remove-hook 'find-file-hooks 'whitespace-buffer)
  (remove-hook 'kill-buffer-hook 'whitespace-buffer))

(use-package whitespace-cleanup-mode
  :defer 5
  :diminish
  :commands whitespace-cleanup-mode
  :config
  (global-whitespace-cleanup-mode 1))

(use-package window-purpose
  :commands purpose-mode)

(use-package winner
  :unless noninteractive
  :defer 5
  :bind (("M-N" . winner-redo)
         ("M-P" . winner-undo))
  :config
  (winner-mode 1))

(use-package word-count
  :bind ("C-c \"" . word-count-mode))

(use-package x86-lookup
  :bind ("C-h X" . x86-lookup))

(use-package xray
  :bind (("C-h x b" . xray-buffer)
         ("C-h x f" . xray-faces)
         ("C-h x F" . xray-features)
         ("C-h x R" . xray-frame)
         ("C-h x h" . xray-hooks)
         ("C-h x m" . xray-marker)
         ("C-h x o" . xray-overlay)
         ("C-h x p" . xray-position)
         ("C-h x S" . xray-screen)
         ("C-h x s" . xray-symbol)
         ("C-h x w" . xray-window)))

(use-package yaml-mode
  :mode "\\.ya?ml\\'")

(use-package yaoddmuse
  :bind (("C-c w f" . yaoddmuse-browse-page-default)
         ("C-c w e" . yaoddmuse-edit-default)
         ("C-c w p" . yaoddmuse-post-library-default)))

(use-package yasnippet
  :demand t
  :diminish yas-minor-mode
  :bind (("C-c y d" . yas-load-directory)
         ("C-c y i" . yas-insert-snippet)
         ("C-c y f" . yas-visit-snippet-file)
         ("C-c y n" . yas-new-snippet)
         ("C-c y t" . yas-tryout-snippet)
         ("C-c y l" . yas-describe-tables)
         ("C-c y g" . yas/global-mode)
         ("C-c y m" . yas/minor-mode)
         ("C-c y r" . yas-reload-all)
         ("C-c y x" . yas-expand))
  :bind (:map yas-keymap
              ("C-i" . yas-next-field-or-maybe-expand))
  :mode ("/\\.emacs\\.d/snippets/" . snippet-mode)
  :config
  (yas-load-directory (emacs-path "snippets"))
  (yas-global-mode 1))

(use-package z3-mode
  :mode (("\\.smt\\'" . z3-mode))
  :bind (:map z3-mode-map
              ("C-c C-c" . z3-execute-region)))

(use-package zoom
  :bind ("C-x +" . zoom)
  :preface
  (defun size-callback ()
    (cond ((> (frame-pixel-width) 1280) '(90 . 0.75))
          (t '(0.5 . 0.5)))))

(use-package ztree-diff
  :commands ztree-diff)

(defconst display-name
  (pcase (display-pixel-width)
    (`3840 'dell-wide)
    (`4480 'imac)
    (`2560 'imac)
    (`1920 'macbook-pro-vga)
    (`1792 'macbook-pro-16)
    (`1680 'macbook-pro-15)
    ;; (`1680 'macbook-pro-13)
    ))

(defsubst bookerly-font (height)
  (format "-*-Bookerly-normal-normal-normal-*-%d-*-*-*-p-0-iso10646-1" height))

(defsubst dejavu-sans-mono-font (height)
  (format "-*-DejaVu Sans Mono-normal-normal-normal-*-%d-*-*-*-m-0-iso10646-1" height))

(defun emacs-min-font ()
  (pcase display-name
    ((guard alternate-emacs) (bookerly-font 18))
    (`imac (dejavu-sans-mono-font 18))
    (_     (dejavu-sans-mono-font 18))))

(defun emacs-min-font-height ()
  (aref (font-info (emacs-min-font)) 3))

(defun emacs-min-left ()
  (pcase display-name
    ((guard alternate-emacs)    0)
    (`dell-wide              1000)
    (`imac              (pcase (emacs-min-font-height)
                          (28  20)
                          (24 116)
                          (21 318)
                          (t    0)))
    (`macbook-pro-vga         700)
    (`macbook-pro-16          672)
    (`macbook-pro-15          464)
    (`macbook-pro-13          464)))

(defun emacs-min-height ()
  (pcase display-name
    ((guard alternate-emacs)   58)
    (`dell-wide                64)
    (`imac               (pcase (emacs-min-font-height)
                           (28 50)
                           (24 58)
                           (21 67)
                           (t  40)))
    (`macbook-pro-vga          55)
    (`macbook-pro-16           51)
    (`macbook-pro-15           47)
    (`macbook-pro-13           47)))

(defun emacs-min-width ()
  (pcase display-name
    ((guard alternate-emacs)   80)
    (`dell-wide               202)
    (`imac              (pcase (emacs-min-font-height)
                          (28 180)
                          (24 202)
                          (21 202)
                          (t  100)))
    (`macbook-pro-vga         100)
    (`macbook-pro-16          100)
    (`macbook-pro-15          100)
    (`macbook-pro-13          100)))

(defun emacs-min ()
  (interactive)
  (cl-flet ((set-param (p v) (set-frame-parameter (selected-frame) p v)))
    (set-param 'fullscreen nil)
    (set-param 'vertical-scroll-bars nil)
    (set-param 'horizontal-scroll-bars nil))
  (message "display-name:     %S" display-name)
  (message "Font name:        %s" (emacs-min-font))
  (message "Font height:      %s" (aref (font-info (emacs-min-font)) 3))
  (message "emacs-min-left:   %s" (emacs-min-left))
  (message "emacs-min-height: %s" (emacs-min-height))
  (message "emacs-min-width:  %s" (emacs-min-width))
  (and (emacs-min-left)
       (set-frame-position (selected-frame) (emacs-min-left) 0))
  (and (emacs-min-height)
       (set-frame-height (selected-frame) (emacs-min-height)))
  (and (emacs-min-width)
       (set-frame-width (selected-frame) (emacs-min-width)))
  (and (emacs-min-font)
       (set-frame-font (emacs-min-font)))
  (message "Emacs is ready"))

(defun emacs-max ()
  (interactive)
  (cl-flet ((set-param (p v) (set-frame-parameter (selected-frame) p v)))
    (set-param 'fullscreen 'fullboth)
    (set-param 'vertical-scroll-bars nil)
    (set-param 'horizontal-scroll-bars nil))
  (and (emacs-min-font)
       (set-frame-font (emacs-min-font))))

(defun emacs-toggle-size ()
  (interactive)
  (if (alist-get 'fullscreen (frame-parameters))
      (emacs-min)
    (emacs-max)))

(add-hook 'emacs-startup-hook #'emacs-min t)

(use-package color-theme
  :config
  (load "color-theme-library")
  (color-theme-midnight))

(let ((elapsed (float-time (time-subtract (current-time)
                                          emacs-start-time))))
  (message "Loading %s...done (%.3fs)" load-file-name elapsed))

(add-hook 'after-init-hook
          `(lambda ()
             (let ((elapsed
                    (float-time
                     (time-subtract (current-time) emacs-start-time))))
               (message "Loading %s...done (%.3fs) [after-init]"
                        ,load-file-name elapsed))) t)

(defun add-journal-entry (title)
  (interactive "sTitle: ")
  (let* ((moniker
          (replace-regexp-in-string
           "[,!]" ""
           (replace-regexp-in-string " " "-" (downcase title))))
         (most-recent
          (split-string
           (car (last (directory-files "~/doc/johnwiegley/posts"))) "-"))
         (year (nth 0 most-recent))
         (month (nth 1 most-recent))
         (day (nth 2 most-recent))
         (date (calendar-gregorian-from-absolute
                (+ 7 (calendar-absolute-from-gregorian
                      (list (string-to-number month)
                            (string-to-number day)
                            (string-to-number year))))))
         (path (expand-file-name (format "%02d-%02d-%02d-%s.md"
                                         (nth 2 date)
                                         (nth 0 date)
                                         (nth 1 date)
                                         moniker)
                                 "~/doc/johnwiegley/posts")))
    (switch-to-buffer (find-file path))
    (insert (format "---
title: %s
tags: journal
---

%s" title (current-kill 0)))))

(bind-key "C-c J" #'add-journal-entry)

(ignore-errors
  (message "4: gnus-kill-files-directory: %s" gnus-kill-files-directory))
(require 'gnus)
(require 'starttls)
(require 'message)
(eval-and-compile
  (require 'gnus-start)
  (require 'gnus-sum)
  (require 'gnus-art)
  (require 'mml))
(ignore-errors
  (message "5: gnus-kill-files-directory: %s" gnus-kill-files-directory))

(gnus-delay-initialize)

(defvar switch-to-gnus-unplugged nil)
(defvar switch-to-gnus-run nil)

(eval-when-compile
  (defvar ido-default-buffer-method)
  (declare-function ido-visit-buffer "ido"))

(defun switch-to-gnus (&optional arg)
  (interactive "P")
  (push-window-configuration)
  (let* ((alist '("\\`\\*unsent" "\\`\\*Summary" "\\`\\*Group"))
         (candidate
          (catch 'found
            (dolist (regexp alist)
              (dolist (buf (buffer-list))
                (if (string-match regexp (buffer-name buf))
                    (throw 'found buf)))))))
    (if (and switch-to-gnus-run candidate)
        (progn
          (if (featurep 'ido)
              (ido-visit-buffer candidate ido-default-buffer-method)
            (switch-to-buffer candidate))
          (if (string-match "Group" (buffer-name candidate))
              (gnus-group-get-new-news)))
      (let ((switch-to-gnus-unplugged arg))
        ;; (gnus)
        (gnus-unplugged)
        (gnus-group-list-groups gnus-activate-level)
        (gnus-group-get-all-new-news)
        (setq switch-to-gnus-run t)))))

(defun quickping (host)
  (= 0 (call-process "ping" nil nil nil "-c1" "-W50" "-q" host)))

(fset 'retrieve-attached-mail
      [?\C-d ?\C-n ?B ?c ?I ?N ?B ?O ?X return ?q ?\C-p ?B backspace ?\M-g])

(use-package fetchmail-ctl
  :disabled t
  :after gnus-group
  :bind (:map gnus-group-mode-map
              ("v b" . switch-to-fetchmail)
              ("v d" . shutdown-fetchmail)
              ("v k" . kick-fetchmail)
              ;; ("v p" . fetchnews-post)
              ))

(use-package gnus-sum
  :bind (:map gnus-summary-mode-map
              ("F" . gnus-summary-wide-reply-with-original)))

(use-package gnus-art
  :bind (:map gnus-article-mode-map
              ("F" . gnus-article-wide-reply-with-original)))

(add-hook 'gnus-group-mode-hook 'gnus-topic-mode)
(add-hook 'gnus-group-mode-hook 'hl-line-mode)

(add-hook 'gnus-summary-mode-hook 'hl-line-mode)

(defun my-message-header-setup-hook ()
  (message-remove-header "From")
  (let ((gcc (message-field-value "Gcc")))
    (when (or (null gcc)
              (string-match "nnfolder\\+archive:" gcc))
      (message-remove-header "Bcc")
      (message-remove-header "Gcc")
      ;; (message-add-header (format "Bcc: %s" user-mail-address))
      ;; (message-add-header
      ;;  (format "Gcc: %s"
      ;;          (if (string-match "\\`list\\." (or gnus-newsgroup-name ""))
      ;;              "mail.sent"
      ;;            "INBOX")))
      )))

(add-hook 'message-header-setup-hook 'my-message-header-setup-hook)

(defadvice gnus-summary-resend-message-edit (after call-my-mhs-hook activate)
  (my-message-header-setup-hook))

(defun my-gnus-summary-save-parts (&optional arg)
  (interactive "P")
  (let ((directory "~/Downloads"))
    (message "Saving all MIME parts to %s..." directory)
    (gnus-summary-save-parts ".*" directory arg)
    (message "Saving all MIME parts to %s...done" directory)))

(bind-key "X m" 'my-gnus-summary-save-parts gnus-summary-mode-map)

(eval-when-compile
  (defvar gnus-agent-queue-mail))

(defun queue-message-if-not-connected ()
  (set (make-local-variable 'gnus-agent-queue-mail)
       (if (quickping "smtp.gmail.com") t 'always)))

(add-hook 'message-send-hook 'queue-message-if-not-connected)
(add-hook 'message-sent-hook 'gnus-score-followup-thread)

(defun exit-gnus-on-exit ()
  (if (and (fboundp 'gnus-group-exit)
           (gnus-alive-p))
      (with-current-buffer (get-buffer "*Group*")
        (let (gnus-interactive-exit)
          (gnus-group-exit)))))

(add-hook 'kill-emacs-hook 'exit-gnus-on-exit)

(defun switch-in-other-buffer (buf)
  (when buf
    (split-window-vertically)
    (balance-windows)
    (switch-to-buffer-other-window buf)))

(defun my-gnus-trash-article (arg)
  (interactive "P")
  (if (string-match "\\(drafts\\|queue\\|delayed\\)" gnus-newsgroup-name)
      (gnus-summary-delete-article arg)
    (gnus-summary-move-article arg "mail.trash")))

(define-key gnus-summary-mode-map [(meta ?q)] 'gnus-article-fill-long-lines)
(define-key gnus-summary-mode-map [?B delete] 'gnus-summary-delete-article)
(define-key gnus-summary-mode-map [?B backspace] 'my-gnus-trash-article)

(define-key gnus-article-mode-map [(meta ?q)] 'gnus-article-fill-long-lines)

(defface gnus-summary-expirable-face
  '((((class color) (background dark))
     (:foreground "grey50" :italic t :strike-through t))
    (((class color) (background light))
     (:foreground "grey55" :italic t :strike-through t)))
  "Face used to highlight articles marked as expirable."
  :group 'gnus-summary-visual)

(push '((eq mark gnus-expirable-mark) . gnus-summary-expirable-face)
      gnus-summary-highlight)

(if window-system
    (setq
     gnus-sum-thread-tree-false-root      ""
     gnus-sum-thread-tree-single-indent   ""
     gnus-sum-thread-tree-root            ""
     gnus-sum-thread-tree-vertical        "|"
     gnus-sum-thread-tree-leaf-with-other "+-> "
     gnus-sum-thread-tree-single-leaf     "\\-> "
     gnus-sum-thread-tree-indent          " "))

(defsubst dot-gnus-tos (time)
  "Convert TIME to a floating point number."
  (+ (* (car time) 65536.0)
     (cadr time)
     (/ (or (car (cdr (cdr time))) 0) 1000000.0)))

(defun gnus-user-format-function-S (header)
  "Return how much time it's been since something was sent."
  (condition-case err
      (let ((date (mail-header-date header)))
        (if (> (length date) 0)
            (let*
                ((then (dot-gnus-tos
                        (apply 'encode-time (parse-time-string date))))
                 (now (dot-gnus-tos (current-time)))
                 (diff (- now then))
                 (str
                  (cond
                   ((>= diff (* 86400.0 7.0 52.0))
                    (if (>= diff (* 86400.0 7.0 52.0 10.0))
                        (format "%3dY" (floor (/ diff (* 86400.0 7.0 52.0))))
                      (format "%3.1fY" (/ diff (* 86400.0 7.0 52.0)))))
                   ((>= diff (* 86400.0 30.0))
                    (if (>= diff (* 86400.0 30.0 10.0))
                        (format "%3dM" (floor (/ diff (* 86400.0 30.0))))
                      (format "%3.1fM" (/ diff (* 86400.0 30.0)))))
                   ((>= diff (* 86400.0 7.0))
                    (if (>= diff (* 86400.0 7.0 10.0))
                        (format "%3dw" (floor (/ diff (* 86400.0 7.0))))
                      (format "%3.1fw" (/ diff (* 86400.0 7.0)))))
                   ((>= diff 86400.0)
                    (if (>= diff (* 86400.0 10.0))
                        (format "%3dd" (floor (/ diff 86400.0)))
                      (format "%3.1fd" (/ diff 86400.0))))
                   ((>= diff 3600.0)
                    (if (>= diff (* 3600.0 10.0))
                        (format "%3dh" (floor (/ diff 3600.0)))
                      (format "%3.1fh" (/ diff 3600.0))))
                   ((>= diff 60.0)
                    (if (>= diff (* 60.0 10.0))
                        (format "%3dm" (floor (/ diff 60.0)))
                      (format "%3.1fm" (/ diff 60.0))))
                   (t
                    (format "%3ds" (floor diff)))))
                 (stripped
                  (replace-regexp-in-string "\\.0" "" str)))
              (concat (cond
                       ((= 2 (length stripped)) "  ")
                       ((= 3 (length stripped)) " ")
                       (t ""))
                      stripped))))
    (error "    ")))

(defun gnus-user-format-function-X (header)
  (let* ((to (or (cdr (assoc 'To (mail-header-extra header))) ""))
         (cc (or (cdr (assoc 'Cc (mail-header-extra header))) ""))
         )
    (message "to-address: %s" to-address)
    (message "recipients: %s" recipients)
    (if (and recipients to-address (not (member to-address recipients)))
        (propertize "X" 'face 'font-lock-warning-face)
      " ")))

(defvar gnus-count-recipients-threshold 5
  "*Number of recipients to consider as large.")

(defun gnus-user-format-function-r (header)
  "Given a Gnus message header, returns priority mark.
Here are the meanings:

The first column represent my relationship to the To: field.  It can be:

         I didn't appear (and the letter had one recipient)
   :     I didn't appear (and the letter had more than one recipient)
   <     I was the sole recipient
   +     I was among a few recipients
   *     There were many recipients

The second column represents the Cc: field:

         I wasn't mentioned, nor was anyone else
    .    I wasn't mentioned, but one other was
    :    I wasn't mentioned, but others were
    ^    I was the only Cc mentioned
    &    I was among a few Cc recipients
    %    I was among many Cc recipients
    X    This is a mailing list, but it wasn't on the recipients list

These can combine in some ways to tell you at a glance how visible the message
is:

   <.    Someone wrote to me and one other
    &    I was copied along with several other people
   *:    Mail to lots of people in both the To and Cc!"
  (ignore-errors
    (let* ((to (or (cdr (assoc 'To (mail-header-extra header))) ""))
           (cc (or (cdr (assoc 'Cc (mail-header-extra header))) ""))
           (to-len (length (split-string to "\\s-*,\\s-*")))
           (cc-len (length (split-string cc "\\s-*,\\s-*")))
           (msg-recipients (concat to (and to cc ", ") cc))
           (recipients
            (mapcar 'mail-strip-quoted-names
	            (message-tokenize-header msg-recipients)))
           (to-address
            (alist-get 'to-address
                       (gnus-parameters-get-parameter gnus-newsgroup-name)))
           (privatized
            (and recipients to-address (not (member to-address recipients)))))
      (cond ((string-match gnus-ignored-from-addresses to)
             (cond ((= to-len 1)
                    (cond (privatized "<X")
                          ((string= cc "") "< ")
                          ((= cc-len 1) "<.")
                          (t "<:")))
                   ((< to-len gnus-count-recipients-threshold)
                    (cond (privatized "+X")
                          ((string= cc "") "+ ")
                          ((= cc-len 1) "+.")
                          (t "+:")))
                   (t
                    (cond (privatized "*X")
                          ((string= cc "") "* ")
                          ((= cc-len 1) "*.")
                          (t "*:")))))

            ((string-match gnus-ignored-from-addresses cc)
             (cond (privatized " X")
                   ((= cc-len 1)
                    (cond ((= to-len 1) " ^")
                          (t ":^")))
                   ((< cc-len gnus-count-recipients-threshold)
                    (cond ((= to-len 1) " &")
                          (t ":&")))
                   (t
                    (cond ((= to-len 1) " %")
                          (t ":%")))))
            (t "  ")))))

(use-package message-x)

(use-package gnus-dired
  :commands gnus-dired-mode
  :init
  (add-hook 'dired-mode-hook 'gnus-dired-mode))

(use-package my-gnus-score
  :commands (my-gnus-score-groups my-gnus-score-followup)
  :init
  (defun gnus-group-get-all-new-news (&optional arg)
    (interactive "P")
    (gnus-group-get-new-news 5)
    (gnus-group-list-groups (or arg 4))
    (my-gnus-score-groups)
    (gnus-group-list-groups (or arg 3))
    (gnus-group-save-newsrc t))

  (define-key gnus-group-mode-map [?v ?g] 'gnus-group-get-all-new-news))

(use-package gnus-demon
  :init
  (progn
    (defun gnus-demon-scan-news-2 ()
      (when gnus-plugged
        (let ((win (current-window-configuration))
              (gnus-read-active-file nil)
              (gnus-check-new-newsgroups nil)
              (gnus-verbose 2)
              (gnus-verbose-backends 5))
          (unwind-protect
              (save-window-excursion
                (when (gnus-alive-p)
                  (with-current-buffer gnus-group-buffer
                    (gnus-group-get-new-news gnus-activate-level))))
            (set-window-configuration win)))))

    ;; (gnus-demon-add-handler 'gnus-demon-scan-news-2 5 2)

    (defun save-gnus-newsrc ()
      (if (and (fboundp 'gnus-group-exit)
               (gnus-alive-p))
          (with-current-buffer (get-buffer "*Group*")
            (gnus-save-newsrc-file))))

    (gnus-demon-add-handler 'save-gnus-newsrc nil 1)
    (gnus-demon-add-handler 'gnus-demon-close-connections nil 3)))

(defun activate-gnus ()
  (unless (get-buffer "*Group*") (gnus)))

(defun gnus-goto-article (message-id)
  (activate-gnus)
  ;; (gnus-summary-read-group "mail.archive" 15 t)
  (gnus-group-read-ephemeral-search-group
   t (list
      (cons
       'search-query-spec
       (list (cons 'query
                   (concat "HEADER \"Message-ID\" \"<" message-id ">\""))
             '(raw)))
      (cons
       'search-group-spec
       '(("nnimap:Local" "mail.archive")
         ("nnimap:Local" "mail.kadena")
         ("nnimap:Local" "INBOX")))))
  (gnus-summary-next-page))

(use-package epa
  :defer t
  :config
  (defun epa--key-widget-value-create (widget)
    (let* ((key (widget-get widget :value))
           (primary-sub-key (car (last (epg-key-sub-key-list key) 3)))
           (primary-user-id (car (epg-key-user-id-list key))))
      (insert (format "%c "
                      (if (epg-sub-key-validity primary-sub-key)
                          (car (rassq (epg-sub-key-validity primary-sub-key)
                                      epg-key-validity-alist))
                        ? ))
              (epg-sub-key-id primary-sub-key)
              " "
              (if primary-user-id
                  (if (stringp (epg-user-id-string primary-user-id))
                      (epg-user-id-string primary-user-id)
                    (epg-decode-dn (epg-user-id-string primary-user-id)))
                "")))))

(use-package gnus-harvest
  :load-path "lisp/gnus-harvest"
  :commands gnus-harvest-install
  :demand t
  :config
  (if (featurep 'message-x)
      (gnus-harvest-install 'message-x)
    (gnus-harvest-install)))

(use-package gnus-alias
  :commands (gnus-alias-determine-identity
             gnus-alias-message-x-completion
             gnus-alias-select-identity
             gnus-alias-use-identity)
  :bind (:map  message-mode-map
               ("C-c C-f C-p" . gnus-alias-select-identity))
  :preface
  (defsubst match-in-strings (re strs)
    (cl-some (apply-partially #'string-match re) strs))

  (defun my-gnus-alias-determine-identity ()
    (let ((addrs
           (ignore-errors
             (with-current-buffer (gnus-copy-article-buffer)
               (apply #'nconc
                      (mapcar
                       #'(lambda (x)
                           (split-string (or (gnus-fetch-field x) "") ","))
                       '("To" "Cc" "From" "Reply-To")))))))
      (cond
       ((or (match-in-strings "johnw@gnu\\.org" addrs)
            (match-in-strings "emacs-.*@gnu" addrs)
            (string-match "\\(gnu\\|emacs\\)" gnus-newsgroup-name))
        (gnus-alias-use-identity "Gnu"))
       ((or (match-in-strings "jwiegley@gmail.com" addrs)
            (match-in-strings "@baesystems\\.com" addrs)
            (string-match "\\(brass\\|safe\\|riscv\\)" gnus-newsgroup-name))
        (gnus-alias-use-identity "Gmail"))
       ((or (match-in-strings "johnw@newartisans\\.com" addrs)
            (string-match "\\(haskell\\|coq\\|agda\\|idris\\|acl2\\)"
                          gnus-newsgroup-name))
        (gnus-alias-use-identity "NewArtisans"))
       ((match-in-strings "john\\.wiegley@baesystems\\.com" addrs)
        (gnus-alias-use-identity "BAE"))
       (t
        (gnus-alias-determine-identity)))))
  :init
  (when (featurep 'message-x)
    (add-hook 'message-x-after-completion-functions
              'gnus-alias-message-x-completion))

  (add-hook 'message-setup-hook #'my-gnus-alias-determine-identity))

(use-package gnus-recent
  :after gnus
  :bind (("M-s a" . gnus-recent-goto-ivy)
         :map gnus-summary-mode-map
         ("l" . gnus-recent-goto-previous)
         :map gnus-group-mode-map
         ("C-c L" . gnus-recent-goto-previous)))

(eval-when-compile
  (defvar gnus-balloon-face-0)
  (defvar gnus-balloon-face-1))

(use-package rs-gnus-summary
  :config
  (defalias 'gnus-user-format-function-size
    'rs-gnus-summary-line-message-size)

  (setq gnus-balloon-face-0 'rs-gnus-balloon-0)
  (setq gnus-balloon-face-1 'rs-gnus-balloon-1))

(use-package supercite
  :commands sc-cite-original
  :init
  (add-hook 'mail-citation-hook 'sc-cite-original)

  (defun sc-remove-existing-signature ()
    (save-excursion
      (goto-char (region-beginning))
      (when (re-search-forward message-signature-separator (region-end) t)
        (delete-region (match-beginning 0) (region-end)))))

  (add-hook 'mail-citation-hook 'sc-remove-existing-signature)

  (defun sc-remove-if-not-mailing-list ()
    (unless (assoc "list-id" sc-mail-info)
      (setq attribution sc-default-attribution
            citation (concat sc-citation-delimiter
                             sc-citation-separator))))

  (add-hook 'sc-attribs-postselect-hook 'sc-remove-if-not-mailing-list)

  :config
  (defun sc-fill-if-different (&optional prefix)
    "Fill the region bounded by `sc-fill-begin' and point.
Only fill if optional PREFIX is different than
`sc-fill-line-prefix'.  If `sc-auto-fill-region-p' is nil, do not
fill region.  If PREFIX is not supplied, initialize fill
variables.  This is useful for a regi `begin' frame-entry."
    (if (not prefix)
        (setq sc-fill-line-prefix ""
              sc-fill-begin (line-beginning-position))
      (if (and sc-auto-fill-region-p
               (not (string= prefix sc-fill-line-prefix)))
          (let ((fill-prefix sc-fill-line-prefix))
            (unless (or (string= fill-prefix "")
                        (save-excursion
                          (goto-char sc-fill-begin)
                          (or (looking-at ">+  +")
                              (< (length
                                  (buffer-substring (point)
                                                    (line-end-position)))
                                 65))))
              (fill-region sc-fill-begin (line-beginning-position)))
            (setq sc-fill-line-prefix prefix
                  sc-fill-begin (line-beginning-position)))))
    nil))

(defun gnus-article-get-urls-region (min max)
  "Return a list of urls found in the region between MIN and MAX"
  (let (url-list)
    (save-excursion
      (save-restriction
        (narrow-to-region min max)
        (goto-char (point-min))
        (while (re-search-forward gnus-button-url-regexp nil t)
          (let ((match-string (match-string-no-properties 0)))
            (if (and (not (equal (substring match-string 0 4) "file"))
                     (not (member match-string url-list)))
                (setq url-list (cons match-string url-list)))))))
    url-list))

(defun gnus-article-get-current-urls ()
  "Return a list of the urls found in the current `gnus-article-buffer'"
  (let (url-list)
    (with-current-buffer gnus-article-buffer
      (setq url-list
            (gnus-article-get-urls-region (point-min) (point-max))))
    url-list))

(defun gnus-article-browse-urls ()
  "Visit a URL from the `gnus-article-buffer' by showing a
buffer with the list of URLs found with the `gnus-button-url-regexp'."
  (interactive)
  (gnus-configure-windows 'article)
  (gnus-summary-select-article nil nil 'pseudo)
  (let ((temp-buffer (generate-new-buffer " *Article URLS*"))
        (urls (gnus-article-get-current-urls))
        (this-window (selected-window))
        (browse-window (get-buffer-window gnus-article-buffer))
        (count 0))
    (save-excursion
      (save-window-excursion
        (with-current-buffer temp-buffer
          (mapc (lambda (string)
                  (insert (format "\t%d: %s\n" count string))
                  (setq count (1+ count))) urls)
          (set-buffer-modified-p nil)
          (pop-to-buffer temp-buffer)
          (setq count
                (string-to-number
                 (char-to-string (if (fboundp
                                      'read-char-exclusive)
                                     (read-char-exclusive)
                                   (read-char)))))
          (kill-buffer temp-buffer)))
      (if browse-window
          (progn (select-window browse-window)
                 (browse-url (nth count urls)))))
    (select-window this-window)))

(use-package mml
  :defer t
  :preface
  (defvar mml-signing-attachment nil)
  (defun mml-sign-attached-file (file &optional type description disposition)
    (unless (or mml-signing-attachment
                (null current-prefix-arg))
      (let ((signature
             (expand-file-name (concat (file-name-nondirectory file) ".sig")
                               temporary-file-directory))
            (mml-signing-attachment t))
        (message "Signing %s..." file)
        (if t
            (call-process epg-gpg-program file nil nil
                          "--output" signature "--detach-sign" file)
          (with-temp-file signature
            (setq buffer-file-coding-system 'raw-text-unix)
            (call-process epg-gpg-program file t nil "--detach-sign")))
        (message "Signing %s...done" file)
        (mml-attach-file signature))))
  :config
  (advice-add 'mml-attach-file :after #'mml-sign-attached-file))

;;;; Org

(require 'org)
(require 'org-agenda)
(require 'org-habit)

(add-hook 'org-capture-mode-hook #'(lambda () (setq-local fill-column (- 78 2))))

(unless window-system
  (setq org-agenda-files
        '("~/doc/org/todo.org")))

;; (setq org-version "8.2.11")
;; (defun org-release () "8.2.11")
;; (defun org-git-version () "8.2.11")

(unbind-key "C-," org-mode-map)
(unbind-key "C-'" org-mode-map)

(defconst my-org-soft-red    "#fcebeb")
(defconst my-org-soft-orange "#fcf5eb")
(defconst my-org-soft-yellow "#fcfceb")
(defconst my-org-soft-green  "#e9f9e8")
(defconst my-org-soft-blue   "#e8eff9")
(defconst my-org-soft-purple "#f3e8f9")

(when nil
  (custom-set-faces
   '(variable-pitch ((t (:family "ETBembo")))))
  (custom-set-faces
   '(org-document-title ((t (:foreground "#f7f7f7" :weight bold :height 1.5)))))
  (custom-set-faces
   '(org-image-actual-width '(600)))
  (custom-set-faces
   '(org-block-begin-line ((t (:background "#fbf8ef")))))
  (custom-set-faces
   '(org-block-end-line ((t (:background "#fbf8ef")))))

  (setq default-major-mode 'org-mode)

  (add-hook 'org-mode-hook
            #'(lambda ()
                (variable-pitch-mode 1) ;; All fonts with variable pitch.
                (mapc
                 (lambda (face) ;; Other fonts with fixed-pitch.
                   (set-face-attribute face nil :inherit 'fixed-pitch))
                 (list 'org-code
                       'org-link
                       'org-block
                       'org-table
                       'org-verbatim
                       'org-block-begin-line
                       'org-block-end-line
                       'org-meta-line
                       'org-document-info-keyword)))))

(add-hook 'org-mode-hook
          #'(lambda ()
              (abbrev-mode 1)))

(defun org-fit-agenda-window ()
  "Fit the window to the buffer size."
  (and (memq org-agenda-window-setup '(reorganize-frame))
       (fboundp 'fit-window-to-buffer)
       (fit-window-to-buffer)))

(defun my-org-startup ()
  (org-agenda-list)
  (org-fit-agenda-window)
  (org-agenda-to-appt)
  (call-interactively #'org-resolve-clocks))

(defadvice org-refile-get-location (before clear-refile-history activate)
  "Fit the Org Agenda to its buffer."
  (setq org-refile-history nil))

(defun org-linkify ()
  (interactive)
  (goto-char (point-min))
  (while (re-search-forward " \\(\\(VER\\|SDK\\|IC\\|ICSUP\\|NNS1\\|IDX\\)-\\([0-9]+\\)\\) " nil t)
    (replace-match (format " [[%s:\\3][\\2-\\3]] " (downcase (match-string 2))) t)
    (goto-char (match-end 0)))
  (while (re-search-forward " \\(\\(quill\\)#\\([0-9]+\\)\\) " nil t)
    (replace-match (format " [[%s:\\3][\\2#\\3]] " (downcase (match-string 2))) t)
    (goto-char (match-end 0))))

(defun jump-to-org-agenda ()
  (interactive)
  (push-window-configuration)
  (cl-flet ((prep-window (wind)
                         (with-selected-window wind
                           (org-fit-window-to-buffer wind)
                           (ignore-errors
                             (window-resize
                              wind
                              (- 100 (window-width wind)) t)))))
    (aif (or (get-buffer "*Org Agenda*")
             (get-buffer "*Org Agenda(a)*"))
        (let ((buf it))
          (aif (get-buffer-window it)
              (when (called-interactively-p 'any)
                (funcall #'prep-window it))
            (if (called-interactively-p 'any)
                (funcall #'prep-window (display-buffer buf t t))
              (funcall #'prep-window (display-buffer buf)))))
      (call-interactively 'org-agenda-list)
      (funcall #'prep-window (selected-window)))))

(defun org-get-global-property (name)
  (save-excursion
    (goto-char (point-min))
    (and (re-search-forward (concat "#\\+PROPERTY: " name " \\(.*\\)") nil t)
         (match-string 1))))

(defun org-agenda-add-overlays (&optional line)
  "Add overlays found in OVERLAY properties to agenda items.
Note that habitual items are excluded, as they already
extensively use text properties to draw the habits graph.

For example, for work tasks I like to use a subtle, yellow
background color; for tasks involving other people, green; and
for tasks concerning only myself, blue.  This way I know at a
glance how different responsibilities are divided for any given
day.

To achieve this, I have the following in my todo file:

  * Work
    :PROPERTIES:
    :CATEGORY: Work
    :OVERLAY:  (face (:background \"#fdfdeb\"))
    :END:
  ** TODO Task
  * Family
    :PROPERTIES:
    :CATEGORY: Personal
    :OVERLAY:  (face (:background \"#e8f9e8\"))
    :END:
  ** TODO Task
  * Personal
    :PROPERTIES:
    :CATEGORY: Personal
    :OVERLAY:  (face (:background \"#e8eff9\"))
    :END:
  ** TODO Task

The colors (which only work well for white backgrounds) are:

  Yellow: #fdfdeb
  Green:  #e8f9e8
  Blue:   #e8eff9

To use this function, add it to `org-agenda-finalize-hook':

  (add-hook 'org-finalize-agenda-hook 'org-agenda-add-overlays)"
  (let ((inhibit-read-only t) l c
        (buffer-invisibility-spec '(org-link)))
    (save-excursion
      (goto-char (if line (point-at-bol) (point-min)))
      (while (not (eobp))
        (let ((org-marker (get-text-property (point) 'org-marker)))
          (when (and org-marker
                     (null (overlays-at (point)))
                     (not (get-text-property (point) 'org-habit-p))
                     (get-text-property (point) 'type)
                     (string-match "\\(sched\\|dead\\|todo\\)"
                                   (get-text-property (point) 'type)))
            (let ((overlays
                   (or (org-entry-get org-marker "OVERLAY" t)
                       (with-current-buffer (marker-buffer org-marker)
                         (org-get-global-property "OVERLAY")))))
              (when overlays
                (goto-char (line-end-position))
                (let ((rest (- (window-width) (current-column))))
                  (if (> rest 0)
                      (insert (make-string rest ? ))))
                (let ((ol (make-overlay (line-beginning-position)
                                        (line-end-position)))
                      (proplist (read overlays)))
                  (while proplist
                    (overlay-put ol (car proplist) (cadr proplist))
                    (setq proplist (cddr proplist))))))))
        (forward-line)))))

(add-hook 'org-agenda-finalize-hook 'org-agenda-add-overlays)

(autoload 'gnus-string-remove-all-properties "gnus-util")

(defun gnus-summary-mark-read-and-unread-as-read (&optional new-mark)
  "Intended to be used by `gnus-mark-article-hook'."
  (let ((mark (gnus-summary-article-mark)))
    (when (or (gnus-unread-mark-p mark)
	      (gnus-read-mark-p mark))
      (ignore-errors
        (gnus-summary-mark-article gnus-current-article
                                   (or new-mark gnus-read-mark))))))

(defun org-todo-age-time (&optional pos)
  (let ((stamp (org-entry-get (or pos (point)) "CREATED" t)))
    (when stamp
      (time-subtract (current-time)
                     (org-time-string-to-time
                      (org-entry-get (or pos (point)) "CREATED" t))))))

(defun org-todo-age (&optional pos)
  (let ((days (time-to-number-of-days (org-todo-age-time pos))))
    (cond
     ((< days 1)   "today")
     ((< days 7)   (format "%dd" days))
     ((< days 30)  (format "%.1fw" (/ days 7.0)))
     ((< days 358) (format "%.1fM" (/ days 30.0)))
     (t            (format "%.1fY" (/ days 365.0))))))

(defun org-compare-todo-age (a b)
  (let ((time-a (org-todo-age-time (get-text-property 0 'org-hd-marker a)))
        (time-b (org-todo-age-time (get-text-property 0 'org-hd-marker b))))
    (if (time-less-p time-a time-b)
        -1
      (if (equal time-a time-b)
          0
        1))))

(defun org-my-message-open (message-id)
  (if (get-buffer "*Group*")
      (gnus-goto-article
       (gnus-string-remove-all-properties (substring message-id 2)))
    (error "Gnus is not running")))

;; (add-to-list 'org-link-protocols (list "message" 'org-my-message-open nil))
(org-link-set-parameters "message"
			 :follow #'org-my-message-open
			 :store #'org-gnus-store-link)

(defun save-org-mode-files ()
  (dolist (buf (buffer-list))
    (with-current-buffer buf
      (when (eq major-mode 'org-mode)
        (if (and (buffer-modified-p) (buffer-file-name))
            (save-buffer))))))

(run-with-idle-timer 25 t 'save-org-mode-files)

(defun my-org-push-mobile ()
  (interactive)
  (with-current-buffer (find-file-noselect "~/doc/org/todo.org")
    (org-mobile-push)))

(eval-when-compile
  (defvar org-clock-current-task)
  (defvar org-mobile-directory)
  (defvar org-mobile-capture-file))

(defun quickping (host)
  (= 0 (call-process "ping" nil nil nil "-c1" "-W50" "-q" host)))

(defun org-my-auto-exclude-function (tag)
  (and (cond
        ((string= tag "call")
         (let ((hour (nth 2 (decode-time))))
           (or (< hour 8) (> hour 21))))
        ((string= tag "errand")
         (let ((hour (nth 2 (decode-time))))
           (or (< hour 12) (> hour 17))))
        ((or (string= tag "home") (string= tag "nasim"))
         (with-temp-buffer
           (call-process "ifconfig" nil t nil "en0" "inet")
           (call-process "ifconfig" nil t nil "en1" "inet")
           (call-process "ifconfig" nil t nil "bond0" "inet")
           (goto-char (point-min))
           (not (re-search-forward "inet 192\\.168\\.1\\." nil t))))
        ((string= tag "net")
         (not (quickping "imap.fastmail.com")))
        ((string= tag "fun")
         org-clock-current-task))
       (concat "-" tag)))

(defun my-mobileorg-convert ()
  (interactive)
  (while (re-search-forward "^\\* " nil t)
    (goto-char (match-beginning 0))
    (insert ?*)
    (forward-char 2)
    (insert "TODO ")
    (goto-char (line-beginning-position))
    (forward-line)
    (re-search-forward "^\\[")
    (goto-char (match-beginning 0))
    (let ((uuid
           (save-excursion
             (re-search-forward "^\\*\\* Note ID: \\(.+\\)")
             (prog1
                 (match-string 1)
               (delete-region (match-beginning 0)
                              (match-end 0))))))
      ;; (insert (format "SCHEDULED: %s\n:PROPERTIES:\n"
      ;;                 (format-time-string (org-time-stamp-format))))
      (insert ":PROPERTIES:\n")
      (insert (format ":ID:       %s\n:CREATED:  " uuid)))
    (forward-line)
    (insert ":END:")))

(defun my-org-convert-incoming-items ()
  (interactive)
  (with-current-buffer
      (find-file-noselect (expand-file-name org-mobile-capture-file
                                            org-mobile-directory))
    (goto-char (point-min))
    (unless (eobp)
      (my-mobileorg-convert)
      (goto-char (point-max))
      (if (bolp)
          (delete-char -1))
      (let ((tasks (buffer-string)))
        (set-buffer-modified-p nil)
        (kill-buffer (current-buffer))
        (with-current-buffer (find-file-noselect "~/doc/org/todo.org")
          (save-excursion
            (goto-char (point-min))
            (re-search-forward "^\\* Inbox$")
            (re-search-forward "^:END:")
            (forward-line)
            (goto-char (line-beginning-position))
            (if (and tasks (> (length tasks) 0))
                (insert tasks ?\n))))))))

(defun my-org-mobile-pre-pull-function ()
  (my-org-convert-incoming-items))

(add-hook 'org-mobile-pre-pull-hook 'my-org-mobile-pre-pull-function)

(defun org-my-state-after-clock-out (state)
  (if (string= state "STARTED") "TODO" state))

(defvar org-my-archive-expiry-days 9
  "The number of days after which a completed task should be auto-archived.
This can be 0 for immediate, or a floating point value.")

(defconst org-my-ts-regexp
  "[[<]\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\} [^]>\r\n]*?\\)[]>]"
  "Regular expression for fast inactive time stamp matching.")

(defun org-my-closing-time ()
  (let* ((state-regexp
          (concat "- State \"\\(?:" (regexp-opt org-done-keywords)
                  "\\)\"\\s-*\\[\\([^]\n]+\\)\\]"))
         (regexp (concat "\\(" state-regexp "\\|" org-my-ts-regexp "\\)"))
         (end (save-excursion
                (outline-next-heading)
                (point)))
         begin
         end-time)
    (goto-char (line-beginning-position))
    (while (re-search-forward regexp end t)
      (let ((moment (org-parse-time-string (match-string 1))))
        (if (or (not end-time)
                (time-less-p (apply #'encode-time end-time)
                             (apply #'encode-time moment)))
            (setq end-time moment))))
    (goto-char end)
    end-time))

(defun org-archive-expired-tasks ()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((done-regexp
           (concat "^\\*\\* \\(" (regexp-opt org-done-keywords) "\\) ")))
      (while (re-search-forward done-regexp nil t)
        (if (>= (time-to-number-of-days
                 (time-subtract (current-time)
                                (apply #'encode-time (org-my-closing-time))))
                org-my-archive-expiry-days)
            (org-archive-subtree))))
    (save-buffer)))

(defalias 'archive-expired-tasks 'org-archive-expired-tasks)

(defun org-archive-done-tasks ()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "\* \\(DONE\\|CANCELED\\) " nil t)
      (if (save-restriction
            (save-excursion
              (org-narrow-to-subtree)
              (search-forward ":LOGBOOK:" nil t)))
          (forward-line)
        (org-archive-subtree)
        (goto-char (line-beginning-position))))))

(defalias 'archive-done-tasks 'org-archive-done-tasks)

(defun org-get-inactive-time ()
  (float-time (org-time-string-to-time
               (or (org-entry-get (point) "TIMESTAMP")
                   (org-entry-get (point) "TIMESTAMP_IA")
                   (org-entry-get (point) "CREATED")
                   (debug)))))

(defun org-get-completed-time ()
  (let ((begin (point)))
    (save-excursion
      (outline-next-heading)
      (and (re-search-backward
            (concat "\\(- State \"\\(DONE\\|DEFERRED\\|CANCELED\\)\""
                    "\\s-+\\[\\(.+?\\)\\]\\|CLOSED: \\[\\(.+?\\)\\]\\)")
            begin t)
           (float-time (org-time-string-to-time (or (match-string 3)
                                                    (match-string 4))))))))

(defun org-sort-done-tasks ()
  (interactive)
  (goto-char (point-min))
  (org-sort-entries t ?F #'org-get-inactive-time #'<)
  (goto-char (point-min))
  (while (re-search-forward "


+" nil t)
    (delete-region (match-beginning 0) (match-end 0))
    (insert "
"))
  (let (after-save-hook)
    (save-buffer))
  (org-overview))

(defalias 'sort-done-tasks 'org-sort-done-tasks)

(defun org-sort-all ()
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^\* " nil t)
      (goto-char (match-beginning 0))
      (condition-case err
          (progn
            ;; (org-sort-entries t ?a)
            (org-sort-entries t ?p)
            (org-sort-entries t ?o))
        (error nil))
      (forward-line))
    (goto-char (point-min))
    (while (re-search-forward "\* PROJECT " nil t)
      (goto-char (line-beginning-position))
      (ignore-errors
        ;; (org-sort-entries t ?a)
        (org-sort-entries t ?p)
        (org-sort-entries t ?o))
      (forward-line))))

(defun org-cleanup ()
  (interactive)
  (org-archive-expired-tasks)
  (org-sort-all))

(defvar my-org-wrap-region-history nil)

(defun my-org-wrap-region (&optional arg)
  (interactive "P")
  (save-excursion
    (goto-char (region-end))
    (if arg
        (insert "#+end_src\n")
      (insert ":END:\n"))
    (goto-char (region-beginning))
    (if arg
        (insert "#+begin_src "
                (read-string "Language: " nil 'my-org-wrap-region-history)
                ?\n)
      (insert ":OUTPUT:\n"))))

(defun org-get-message-link (&optional title)
  (let (message-id subject)
    (with-current-buffer gnus-original-article-buffer
      (setq message-id (substring (message-field-value "message-id") 1 -1)
            subject (or title (message-field-value "subject"))))
    (org-make-link-string (concat "message://" message-id)
                          (rfc2047-decode-string subject))))

(defun org-insert-message-link (&optional arg)
  (interactive "P")
  (insert (org-get-message-link (if arg "writes"))))

(defun org-set-message-link ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "Message" (org-get-message-link)))

(defun org-get-message-sender ()
  (let (message-id subject)
    (with-current-buffer gnus-original-article-buffer
      (message-field-value "from"))))

(defun org-set-message-sender ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "Submitter" (org-get-message-sender)))

(defun org-get-safari-link ()
  (let ((subject (substring (do-applescript
                             (string-to-multibyte "tell application \"Safari\"
        name of document of front window
end tell")) 1 -1))
        (url (substring (do-applescript
                         (string-to-multibyte "tell application \"Safari\"
        URL of document of front window
end tell")) 1 -1)))
    (org-make-link-string url subject)))

(defun org-get-chrome-link ()
  (let ((subject (do-applescript
                  (string-to-multibyte "tell application \"Google Chrome\"
        title of active tab of front window
end tell")))
        (url (do-applescript
              (string-to-multibyte "tell application \"Google Chrome\"
        URL of active tab of front window
end tell"))))
    (org-make-link-string (substring url 1 -1) (substring subject 1 -1))))

(defun org-insert-url-link ()
  (interactive)
  (insert (org-get-safari-link)))

(defun org-set-url-link ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "URL" (org-get-safari-link)))

(defun org-set-url-from-clipboard ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "URL" (gui--selection-value-internal 'CLIPBOARD)))

(defun org-get-file-link ()
  (let* ((subject (do-applescript "tell application \"Path Finder\"
     set theItems to the selection
     name of beginning of theItems
end tell"))
         (path (do-applescript "tell application \"Path Finder\"
     set theItems to the selection
     (POSIX path of beginning of theItems) as text
end tell"))
         (short-path
          (replace-regexp-in-string abbreviated-home-dir "~/"
                                    (substring path 1 -1))))
    (org-make-link-string (concat "file:" short-path)
                          (substring subject 1 -1))))

(defun org-insert-file-link ()
  (interactive)
  (insert (org-get-file-link)))

(defun org-set-file-link ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "File" (org-get-file-link)))

(defun org-set-dtp-link ()
  "Set a property for the current headline."
  (interactive)
  (org-set-property "Document" (org-get-dtp-link)))

(defun org-dtp-message-open ()
  "Visit the message with the given MESSAGE-ID.
This will use the command `open' with the message URL."
  (interactive)
  (re-search-backward "\\[\\[message://\\(.+?\\)\\]\\[")
  (do-applescript
   (format "tell application \"DEVONthink Pro\"
        set searchResults to search \"%%3C%s%%3E\" within URLs
        open window for record (get beginning of searchResults)
end tell" (shell-quote-argument (match-string 1)))))

(defun org-message-reply ()
  (interactive)
  (let* ((org-marker (get-text-property (point) 'org-marker))
         (author (org-entry-get (or org-marker (point)) "Author"))
         (subject (if org-marker
                      (with-current-buffer (marker-buffer org-marker)
                        (goto-char org-marker)
                        (nth 4 (org-heading-components)))
                    (nth 4 (org-heading-components)))))
    (setq subject (replace-regexp-in-string "\\`(.*?) " "" subject))
    (compose-mail-other-window author (concat "Re: " subject))))

;;;_  . keybindings

(defvar org-mode-completion-keys
  '((?d . "DONE")
    (?g . "DELEGATED")
    (?n . "NOTE")
    (?r . "DEFERRED")
    (?s . "STARTED")
    (?t . "TODO")
    (?e . "EPIC")
    (?o . "STORY")
    (?w . "WAITING")
    (?x . "CANCELED")
    (?y . "SOMEDAY")
    ))

(eval-and-compile
  (defvar org-todo-state-map nil)
  (define-prefix-command 'org-todo-state-map))

(dolist (ckey org-mode-completion-keys)
  (let* ((key (car ckey))
         (label (cdr ckey))
         (org-sym (intern (concat "my-org-todo-" (downcase label))))
         (org-sym-no-logging
          (intern (concat "my-org-todo-" (downcase label) "-no-logging")))
         (org-agenda-sym
          (intern (concat "my-org-agenda-todo-" (downcase label))))
         (org-agenda-sym-no-logging
          (intern (concat "my-org-agenda-todo-"
                          (downcase label) "-no-logging"))))
    (eval
     `(progn
        (defun ,org-sym ()
          (interactive)
          (org-todo ,label))
        (bind-key (concat "C-c x " (char-to-string ,key)) ',org-sym
                  org-mode-map)

        (defun ,org-sym-no-logging ()
          (interactive)
          (let ((org-inhibit-logging t))
            (org-todo ,label)))
        (bind-key (concat "C-c x " (char-to-string  ,(upcase key)))
                  ',org-sym-no-logging org-mode-map)

        (defun ,org-agenda-sym ()
          (interactive)
          (let ((org-inhibit-logging
                 (let ((style (org-entry-get
                               (get-text-property (point) 'org-marker)
                               "STYLE")))
                   (and style (stringp style)
                        (string= style "habit")))))
            (org-agenda-todo ,label)))
        (define-key org-todo-state-map [,key] ',org-agenda-sym)

        (defun ,org-agenda-sym-no-logging ()
          (interactive)
          (let ((org-inhibit-logging t))
            (org-agenda-todo ,label)))
        (define-key org-todo-state-map [,(upcase key)]
          ',org-agenda-sym-no-logging)))))

(defun org-wrap-quote-block (beg end)
  (interactive "r")
  (save-excursion
    (goto-char end)
    (insert "#+END_QUOTE\n")
    (goto-char beg)
    (insert "#+BEGIN_QUOTE\n")))

(defun org-wrap-verse-block (beg end)
  (interactive "r")
  (save-excursion
    (goto-char end)
    (insert "#+END_VERSE\n")
    (goto-char beg)
    (insert "#+BEGIN_VERSE\n")))

(defun org-wrap-output-block (beg end)
  (interactive "r")
  (save-excursion
    (goto-char end)
    (insert ":OUTPUT:\n")
    (goto-char beg)
    (insert ":END:\n")))

(bind-keys :map org-mode-map
           ("C-c x l" . org-insert-dtp-link)
           ("C-c x L" . org-set-dtp-link)
           ("C-c x i" . org-id-get-create)
           ("C-c x m" . org-insert-message-link)
           ("C-c x M" . org-set-message-link)
           ("C-c x u" . org-set-url-from-clipboard)
           ("C-c x U" . org-insert-url-link)
           ("C-c x f" . org-insert-file-link)
           ("C-c x F" . org-set-file-link)
           ("C-c x Q" . org-wrap-quote-block)
           ("C-c x V" . org-wrap-verse-block)
           ("C-c x O" . org-wrap-output-block)

           ("C-c C-x @" . visible-mode)
           ("C-c M-m"   . my-org-wrap-region)

           ("C-c #"     . org-priority)
           ("C-c ,"     . org-priority)

           ([return]                . org-return-indent)
           ([(control return)]      . other-window)
           ([(control meta return)] . org-insert-heading-after-current))

(remove-hook 'kill-emacs-hook 'org-babel-remove-temporary-directory)

;;;_  . org-agenda-mode

(defun my-org-publish-ical ()
  (interactive)
  (async-shell-command "make -C ~/doc/org"))

(bind-keys :map org-agenda-mode-map
           ("C-c C-x C-p" . my-org-publish-ical)
           ("C-n" . next-line)
           ("C-p" . previous-line)
           ("M-n" . org-agenda-later)
           ("M-p" . org-agenda-earlier)
           (" "   . org-agenda-tree-to-indirect-buffer)
           (">"   . org-agenda-filter-by-top-headline)
           ("g"   . org-agenda-redo)
           ("f"   . org-agenda-date-later)
           ("b"   . org-agenda-date-earlier)
           ("r"   . org-agenda-refile)
           ("F"   . org-agenda-follow-mode)
           ("q"   . delete-window)
           ("x"   . org-todo-state-map)
           ("z"   . pop-window-configuration))

(unbind-key "M-m" org-agenda-keymap)

(defadvice org-agenda-redo (after fit-windows-for-agenda-redo activate)
  "Fit the Org Agenda to its buffer."
  (org-fit-agenda-window))

(defadvice org-agenda (around fit-windows-for-agenda activate)
  "Fit the Org Agenda to its buffer."
  (let ((notes
         (ignore-errors
           (directory-files
            "~/Library/Mobile Documents/iCloud~com~agiletortoise~Drafts5/Documents"
            t "[0-9].*\\.txt\\'" nil))))
    (when notes
      (with-current-buffer (find-file-noselect "~/doc/org/todo.org")
        (save-excursion
          (goto-char (point-min))
          (re-search-forward "^\\* Inbox$")
          (re-search-forward "^:END:")
          (forward-line 1)
          (dolist (note notes)
            (insert
             "** TODO "
             (with-temp-buffer
               (insert-file-contents note)
               (goto-char (point-min))
               (forward-line)
               (unless (bolp))
               (insert ?\n)
               ;; (insert (format "SCHEDULED: %s\n"
               ;;                 (format-time-string (org-time-stamp-format))))
               (goto-char (point-max))
               (unless (bolp)
                 (insert ?\n))
               (let ((uuid (substring (shell-command-to-string "uuidgen") 0 -1))
                     (file (file-name-nondirectory note)))
                 (string-match
                  (concat "\\`\\([0-9]\\{4\\}\\)"
                          "-\\([0-9]\\{2\\}\\)"
                          "-\\([0-9]\\{2\\}\\)"
                          "-\\([0-9]\\{2\\}\\)"
                          "-\\([0-9]\\{2\\}\\)"
                          "-\\([0-9]\\{2\\}\\)"
                          "\\.txt\\'") file)
                 (let* ((year (string-to-number (match-string 1 file)))
                        (mon (string-to-number (match-string 2 file)))
                        (day (string-to-number (match-string 3 file)))
                        (hour (string-to-number (match-string 4 file)))
                        (min (string-to-number (match-string 5 file)))
                        (sec (string-to-number (match-string 6 file)))
                        (date (format "%04d-%02d-%02d %s"
                                      year mon day
                                      (calendar-day-name (list mon day year) t))))
                   (insert (format (concat ;; "SCHEDULED: <%s>\n"
                                    ":PROPERTIES:\n"
                                    ":ID:       %s\n"
                                    ":CREATED:  ")
                                   uuid))
                   (insert (format "[%s %02d:%02d]\n:END:\n" date hour min))))
               (buffer-string)))
            (delete-file note t)))
        (when (buffer-modified-p)
          (save-buffer)))))
  ad-do-it
  (org-fit-agenda-window))

(defun org-refile-heading-p ()
  (let ((heading (org-get-heading)))
    (not (string-match "Colophon" heading))))

(defadvice org-archive-subtree (before set-billcode-before-archiving activate)
  "Before archiving a task, set its BILLCODE and TASKCODE."
  (let ((billcode (org-entry-get (point) "BILLCODE" t))
        (taskcode (org-entry-get (point) "TASKCODE" t))
        (project  (org-entry-get (point) "PROJECT" t)))
    (if billcode (org-entry-put (point) "BILLCODE" billcode))
    (if taskcode (org-entry-put (point) "TASKCODE" taskcode))
    (if project (org-entry-put (point) "PROJECT" project))))

(font-lock-add-keywords
 'org-mode
 '(("^ *\\(-\\) "
    (0 (ignore (compose-region (match-beginning 1) (match-end 1) "•"))))))

(defconst first-year-in-list 172)

(defconst naw-ruz
  '((3 21 2015)
    (3 20 2016)
    (3 20 2017)
    (3 21 2018)
    (3 21 2019)
    (3 20 2020)
    (3 20 2021)
    (3 21 2022)
    (3 21 2023)
    (3 20 2024)
    (3 20 2025)
    (3 21 2026)
    (3 21 2027)
    (3 20 2028)
    (3 20 2029)
    (3 20 2030)
    (3 21 2031)
    (3 20 2032)
    (3 20 2033)
    (3 20 2034)
    (3 21 2035)
    (3 20 2036)
    (3 20 2037)
    (3 20 2038)
    (3 21 2039)
    (3 20 2040)
    (3 20 2041)
    (3 20 2042)
    (3 21 2043)
    (3 20 2044)
    (3 20 2045)
    (3 20 2046)
    (3 21 2047)
    (3 20 2048)
    (3 20 2049)
    (3 20 2050)
    (3 21 2051)
    (3 20 2052)
    (3 20 2053)
    (3 20 2054)
    (3 21 2055)
    (3 20 2056)
    (3 20 2057)
    (3 20 2058)
    (3 20 2059)
    (3 20 2060)
    (3 20 2061)
    (3 20 2062)
    (3 20 2063)
    (3 20 2064))
  "The days when Naw-Rúz begins, for the next fifty years.")

(defconst days-of-há
  '(4 4 5 4 4 4 5 4 4 4 5 4 4 4 4 5 4 4 4 5 4 4 4 5 4
      4 4 5 4 4 4 5 4 4 4 5 4 4 4 5 4 4 4 4 5 4 4 4 5 4)
  "The days when Naw-Rúz begins, for the next fifty years.")

(defconst bahai-months
  '("Bahá"      ; 1
    "Jalál"     ; 2
    "Jamál"     ; 3
    "‘Aẓamat"   ; 4
    "Núr"       ; 5
    "Raḥmat"    ; 6
    "Kalimát"   ; 7
    "Kamál"     ; 8
    "Asmá’"     ; 9
    "‘Izzat"    ; 10
    "Mashíyyat" ; 11
    "‘Ilm"      ; 12
    "Qudrat"    ; 13
    "Qawl"      ; 14
    "Masá’il"   ; 15
    "Sharaf"    ; 16
    "Sulṭán"    ; 17
    "Mulk"      ; 18
    "‘Alá’"     ; 19
    ))

(eval-and-compile
  (require 'cal-julian)
  (require 'diary-lib))

(defun bahai-date (month day &optional bahai-year)
  (let* ((greg-year (if bahai-year
                        (+ 1844 (1- bahai-year))
                      (nth 2 (calendar-current-date))))
         (year (1+ (- greg-year 1844)))
         (first-day (cl-find-if #'(lambda (x) (= greg-year (nth 2 x)))
                                naw-ruz))
         (greg-base (calendar-julian-to-absolute first-day))
         (hdays (nth (- year first-year-in-list) days-of-há))
         (offset (+ (1- day) (* 19 (1- month))
                    (if (= month 19)
                        hdays
                      0)))
         (greg-date (calendar-julian-from-absolute (+ greg-base offset))))
    (apply #'diary-date greg-date)))

(defun org-current-is-todo ()
  (member (org-get-todo-state) '("TODO" "EPIC" "STORY" "STARTED")))

(defun my-org-agenda-should-skip-p ()
  "Skip all but the first non-done entry."
  (let (should-skip-entry)
    (unless (org-current-is-todo)
      (setq should-skip-entry t))
    (when (or (org-get-scheduled-time (point))
              (org-get-deadline-time (point)))
      (setq should-skip-entry t))
    (when (/= (point)
              (save-excursion
                (org-goto-first-child)
                (point)))
      (setq should-skip-entry t))
    (save-excursion
      (while (and (not should-skip-entry) (org-goto-sibling t))
        (when (and (org-current-is-todo)
                   (not (org-get-scheduled-time (point)))
                   (not (org-get-deadline-time (point))))
          (setq should-skip-entry t))))
    should-skip-entry))

(defun my-org-agenda-skip-all-siblings-but-first ()
  "Skip all but the first non-done entry."
  (when (my-org-agenda-should-skip-p)
    (or (outline-next-heading)
        (goto-char (point-max)))))

(defun my-org-current-tags (depth)
  (save-excursion
    (ignore-errors
      (let (should-skip)
        (while (and (> depth 0)
                    (not should-skip)
                    (prog1
                        (setq depth (1- depth))
                      (not (org-up-element))))
          (if (looking-at "^\*+\\s-+")
              (setq should-skip (org-get-local-tags))))
        should-skip))))

(defun my-org-agenda-skip-all-siblings-but-first-hot ()
  "Skip all but the first non-done entry."
  (when (or (my-org-agenda-should-skip-p)
            (not (member "HOT" (my-org-current-tags 1))))
    (or (outline-next-heading)
        (goto-char (point-max)))))

(unless (fboundp 'org-link-set-parameters)
  (defun org-link-set-parameters (type &rest parameters)
    (with-no-warnings
      (org-add-link-type type
                         (plist-get parameters :follow)
                         (plist-get parameters :export))
      (add-hook 'org-store-link-functions
                (plist-get parameters :store)))))

(use-package anki-editor
  :disabled t
  :commands anki-editor-submit)

(use-package calfw
  :disabled t
  :bind (("C-c A" . my-calendar)
         :map cfw:calendar-mode-map
         ("M-n" . cfw:navi-next-month-command)
         ("M-p" . cfw:navi-previous-month-command)
         ("j"   . cfw:navi-goto-date-command)
         ("g"   . cfw:refresh-calendar-buffer))
  :commands cfw:open-calendar-buffer
  :functions (cfw:open-calendar-buffer
              cfw:refresh-calendar-buffer
              cfw:org-create-source
              cfw:cal-create-source)
  :preface
  (defun my-calendar ()
    (interactive)
    (let ((buf (get-buffer "*cfw-calendar*"))
          (org-agenda-files
           (cons "~/doc/org/Nasim.org"
                 org-agenda-files)))
      (if buf
          (pop-to-buffer buf nil)
        (cfw:open-calendar-buffer
         :contents-sources
         (list (cfw:org-create-source "Dark Blue")
               (cfw:cal-create-source "Dark Orange"))
         :view 'two-weeks)
        (setq-local org-agenda-files org-agenda-files))))

  :config
  (require 'calfw-cal)
  (use-package calfw-org
    :config
    (setq cfw:org-agenda-schedule-args '(:deadline :timestamp :sexp)))

  (setq cfw:fchar-junction         ?╋
        cfw:fchar-vertical-line    ?┃
        cfw:fchar-horizontal-line  ?━
        cfw:fchar-left-junction    ?┣
        cfw:fchar-right-junction   ?┫
        cfw:fchar-top-junction     ?┯
        cfw:fchar-top-left-corner  ?┏
        cfw:fchar-top-right-corner ?┓))

(use-package helm-org-rifle
  :disabled t
  :bind ("A-M-r" . helm-org-rifle))

(use-package ob-diagrams
  :disabled t)

(use-package ob-restclient
  :disabled t)

(use-package ob-verb)

(use-package org-attach
  :init
  (defun my-org-attach-visit-headline-from-dired ()
    "Go to the headline corresponding to this org-attach directory."
    (interactive)
    (let* ((id-parts (last (split-string default-directory "/" t) 2))
           (id (apply #'concat id-parts)))
      (let ((m (org-id-find id 'marker)))
        (unless m (user-error "Cannot find entry with ID \"%s\"" id))
        (pop-to-buffer (marker-buffer m))
        (goto-char m)
        (move-marker m nil)))))

(use-package org-attach-git)

(use-package org-babel
  :no-require
  :after ob-restclient
  :config
  (org-babel-do-load-languages
   'org-babel-load-languages
   '((python     . t)
     (emacs-lisp . t)
     ;; (coq        . t)
     (haskell    . t)
     (calc       . t)
     ;; (ledger     . t)
     (ditaa      . t)
     (plantuml   . t)
     ;; (sh         . t)
     (sql        . t)
     (dot        . t)
     ;; (verb       . t)
     (restclient . t)))

  (defun org-babel-sh-strip-weird-long-prompt (string)
    "Remove prompt cruft from a string of shell output."
    (while (string-match "^.+?;C;" string)
      (setq string (substring string (match-end 0))))
    string))

(use-package org-bookmark-heading)

(use-package org-crypt
  :bind (:map org-mode-map
              ("C-c C-x C-/" . org-decrypt-entry)))

(use-package org-devonthink)

(use-package org-download
  :bind (:map org-mode-map
              ("C-, i" . org-download-clipboard)
              ("C-, y" . org-download-yank))
  :custom
  (org-download-method 'attach))

(use-package org-mime
  :defer 5
  :config
  (add-hook 'message-mode-hook
            #'(lambda ()
                (local-set-key "\C-c\M-o" 'org-mime-htmlize)))

  (add-hook 'org-mode-hook
            #'(lambda ()
                (local-set-key "\C-c\M-o" 'org-mime-org-buffer-htmlize)))

  (add-hook 'org-mime-html-hook
            #'(lambda ()
                (org-mime-change-element-style
                 "blockquote" "border-left: 2px solid gray; padding-left: 4px;")
                (org-mime-change-element-style
                 "pre" (format "color: %s; background-color: %s; padding: 0.5em;"
                               "#E6E1DC" "#232323")))))

(use-package org-noter
  :after pdf-tools
  :commands org-noter)

(use-package org-protocol)

(use-package org-ql
  :commands org-ql-search)

(use-package org-rich-yank
  :defer 5
  :bind (:map org-mode-map
              ("C-M-y" . org-rich-yank)))

(use-package org-smart-capture)

(use-package org-super-agenda
  :disabled t
  :preface
  (defun super-jump-to-org-agenda ()
    (interactive)
    (let ((org-super-agenda-groups
           '((:name "Today"
                    :time-grid t
                    :todo "TODAY")
             (:name "Important"
                    :tag "bills"
                    :priority "A")
             (:order-multi
              (2 (:name "Shopping in town"
                        :and (:tag "shopping" :tag "@town"))
                 (:name "Food-related"
                        :tag ("food" "dinner"))
                 (:name "Personal"
                        :habit t
                        :tag "personal")
                 (:name "Space-related (non-moon-or-planet-related)"
                        :and (:regexp ("space" "NASA")
                                      :not (:regexp "moon" :tag "planet")))))
             (:todo "WAITING" :order 8)
             (:todo ("SOMEDAY" "TO-READ" "CHECK" "TO-WATCH" "WATCHING")
                    :order 9)
             (:priority<= "B" :order 1))))
      (org-agenda nil "a")))
  :config
  (org-super-agenda-mode))

(use-package org-velocity
  :disabled t
  :bind ("C-, C-." . org-velocity)
  :config
  (defun org-velocity-incremental-read (prompt)
    "Read string with PROMPT and display results incrementally."
    (let ((res
           (unwind-protect
               (let* ((match-window (display-buffer (org-velocity-match-buffer)))
                      (org-velocity-index
                       ;; Truncate the index to the size of the buffer to be
                       ;; displayed.
                       (with-selected-window match-window
                         (if (> (window-height) (length org-velocity-index))
                             ;; (subseq org-velocity-index 0 (window-height))
                             org-velocity-index
                           (let ((hints (copy-sequence org-velocity-index)))
                             (setcdr (nthcdr (window-height) hints) nil)
                             hints)))))
                 (catch 'click
                   (add-hook 'post-command-hook 'org-velocity-update)
                   (if (eq org-velocity-search-method 'regexp)
                       (read-regexp prompt)
                     (if org-velocity-use-completion
                         (org-velocity-read-with-completion prompt)
                       (read-string prompt)))))
             (remove-hook 'post-command-hook 'org-velocity-update))))
      (if (bufferp res) (org-pop-to-buffer-same-window res) res))))

(use-package org-web-tools
  :bind (("C-c x C-y" . my-org-insert-url)
         ("C-c x C-M-y" . org-web-tools-insert-web-page-as-entry))
  :functions (org-web-tools--org-link-for-url
              org-web-tools--get-first-url)
  :preface
  (declare-function org-web-tools--org-link-for-url "org-web-tools")
  (declare-function org-web-tools--get-first-url "org-web-tools")

  (defun my-org-insert-url (&optional arg)
    (interactive "P")
    (require' org-web-tools)
    (let ((link (org-web-tools--org-link-for-url
                 (org-web-tools--get-first-url))))
      (if arg
          (progn
            (org-set-property "URL" link)
            (message "Added pasteboard link to URL property"))
        (insert link)))))

(use-package orgnav)

(use-package orgtbl-aggregate
  :disabled t)

(use-package ox-gfm)

(use-package ox-md)

(use-package ox-texinfo-plus
  :disabled t
  :defer t)

(use-package yankpad
  :disabled t
  :defer 10
  :init
  (setq yankpad-file "~/doc/org/yankpad.org"))

(use-package worf
  :disabled t
  :bind (:map org-mode-map
              ("C-c C-j" . worf-goto)))

(use-package xeft
  :commands xeft)

(defun my-org-export-each-headline (&optional scope)
  "Export each headline to a markdown file with the title as filename.
If SCOPE is nil headlines in the current buffer are exported.
For other valid values for SCOPE see `org-map-entries'.
Already existing files are overwritten."
  (interactive)
  (while (not (eobp))
    (let* ((title (subst-char-in-string ?/ ?: (car (last (org-get-outline-path t))) t))
           (dir (file-name-directory buffer-file-name))
           (filename (concat dir title ".org"))
           (beg (point)))
      (call-interactively #'org-forward-heading-same-level)
      (write-region beg (point) filename))))

(defun my-org-current-entry-and-skip ()
  (let* ((title (subst-char-in-string ?/ ?: (car (last (org-get-outline-path t))) t))
         (beg (point)))
    (call-interactively #'org-forward-heading-same-level)
    (list beg (if (= beg (point))
                  (point-max)
                (point))
          title)))

(defun my-org-created-time (end)
  (save-excursion
    (re-search-forward ":CREATED: +\\[\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\) ... \\([0-9]\\{2\\}\\):\\([0-9]\\{2\\}\\)\\]" end)
    (list (string-to-number (match-string 1))
          (string-to-number (match-string 2))
          (string-to-number (match-string 3))
          (string-to-number (match-string 4))
          (string-to-number (match-string 5)))))

(defun my-org-headline ()
  (looking-at "\\(\\*+\\(:? NOTE\\)? +\\)\\(.+\\)\n")
  (list (match-beginning 1) (match-end 1)
        (match-string 2)))

(defun my-org-property-drawer (end)
  (save-excursion
    (re-search-forward org-property-drawer-re end)
    (list (match-beginning 0) (1+ (match-end 0)))))

(defun my-org-simplify-title (title)
  (replace-regexp-in-string
   "[^A-Za-z0-9_:]" "#"
   (replace-regexp-in-string
    "[']" ""
    (replace-regexp-in-string
     "/" ":"
     (replace-regexp-in-string
      " " "_"
      title)))))

(defun my-org-prepare-dated-note ()
  (interactive)
  (save-excursion
    (forward-line)
    (insert "#+filetags: :thoughts:\n"))
  (delete-blank-lines)
  (let ((id (org-id-get-create))
        (title (save-excursion
                 (cl-destructuring-bind (beg end title)
                     (my-org-current-entry-and-skip)
                   title))))
    (org-entry-put (point) "CREATED" title)
    (goto-char (line-end-position))
    (backward-kill-sexp)))

(defun my-org-prepare-note ()
  (interactive)
  (save-excursion
    (cl-destructuring-bind (beg end title) (my-org-current-entry-and-skip)
      (let ((text (buffer-substring beg end)))
        (with-temp-buffer
          (insert text)
          (goto-char (point-min))
          (cl-destructuring-bind (beg end title2) (my-org-headline)
            ;; (unless (string= title title2)
            ;;   (error "TITLE: %s != %s" title title2))
            (goto-char beg)
            (delete-region beg end)
            (insert "#+title: ")
            (goto-char (line-end-position))
            (insert ?\n)
            (cl-destructuring-bind (beg end) (my-org-property-drawer (point-max))
              (let ((properties (buffer-substring beg end)))
                (delete-region beg end)
                (goto-char (point-min))
                (insert properties)))
            (goto-char (point-max))
            (delete-blank-lines)
            (whitespace-cleanup)
            (goto-char (point-min))
            (cl-destructuring-bind (year mon day hour min)
                (my-org-created-time (point-max))
              (write-region (point-min) (point-max)
                            (expand-file-name (format "%04d%02d%02d%02d%02d-%s.org"
                                                      year mon day hour min
                                                      (my-org-simplify-title title))
                                              org-roam-directory)
                            nil nil nil t))))
        (delete-region beg end)))))

(use-package org-roam
  :demand t  ;; Ensure org-roam is loaded by default
  :init
  (setq org-roam-v2-ack t)
  :custom
  (org-roam-directory "~/doc/org/roam/")
  (org-roam-completion-everywhere t)
  :bind (("C-c n l" . org-roam-buffer-toggle)
         ("C-c n f" . org-roam-node-find)
         ("C-c n h" . helm-org-roam)
         ("C-c n i" . org-roam-node-insert)
         ("C-c n I" . org-roam-node-insert-immediate)
         ("C-c n j" . org-roam-dailies-capture-today)
         ("C-c n p" . my/org-roam-find-project)
         ("C-c n t" . org-roam-tag-add)
         ("C-c n T" . org-roam-tag-remove)
         ("C-c n b" . my/org-roam-capture-inbox)
         ("C-c n w" . my-org-prepare-note)
         ("C-c n x" . xeft)
         :map org-mode-map
         ("C-M-i" . completion-at-point)
         :map org-roam-dailies-map
         ("Y" . org-roam-dailies-capture-yesterday)
         ("T" . org-roam-dailies-capture-tomorrow)
         )
  :bind-keymap ("C-c n d" . org-roam-dailies-map)
  :config
  (use-package org-roam-dailies
    :demand t
    :custom
    (org-roam-dailies-directory "~/doc/org/roam/journal/"))
  (org-roam-db-autosync-mode))

(use-package deft
  :bind ("C-, C-," . deft)
  :config
  (defun my-deft-parse-title-skip-properties (orig-func title contents)
    (funcall orig-func title
             (with-temp-buffer
               (insert contents)
               (goto-char (point-min))
               (when (looking-at org-property-drawer-re)
                 (goto-char (1+ (match-end 0))))
               (buffer-substring (point) (point-max)))))

  (advice-add 'deft-parse-title :around #'my-deft-parse-title-skip-properties)

  (defun my-deft-parse-summary-skip-properties (orig-func contents title)
    (funcall orig-func (with-temp-buffer
                         (insert contents)
                         (goto-char (point-min))
                         (when (looking-at org-property-drawer-re)
                           (goto-char (1+ (match-end 0))))
                         (when (looking-at "#\\+title: ")
                           (forward-line))
                         (buffer-substring (point) (point-max)))
             title))

  (advice-add 'deft-parse-summary :around #'my-deft-parse-summary-skip-properties))

(defun org-roam-node-insert-immediate (arg &rest args)
  (interactive "P")
  (let ((args (push arg args))
        (org-roam-capture-templates (list (append (car org-roam-capture-templates)
                                                  '(:immediate-finish t)))))
    (apply #'org-roam-node-insert args)))

(defun my/org-roam-filter-by-tag (tag-name)
  (lambda (node)
    (member tag-name (org-roam-node-tags node))))

(defun my/org-roam-list-notes-by-tag (tag-name)
  (mapcar #'org-roam-node-file
          (seq-filter
           (my/org-roam-filter-by-tag tag-name)
           (org-roam-node-list))))

;; (defun my/org-roam-refresh-agenda-list ()
;;   (interactive)
;;   (setq org-agenda-files (my/org-roam-list-notes-by-tag "Project")))

;; Build the agenda list the first time for the session
;; (my/org-roam-refresh-agenda-list)

(defun my/org-roam-project-finalize-hook ()
  "Adds the captured project file to `org-agenda-files' if the
capture was not aborted."
  ;; Remove the hook since it was added temporarily
  (remove-hook 'org-capture-after-finalize-hook #'my/org-roam-project-finalize-hook)

  ;; Add project file to the agenda list if the capture was confirmed
  (unless org-note-abort
    (with-current-buffer (org-capture-get :buffer)
      (add-to-list 'org-agenda-files (buffer-file-name)))))

(defun my/org-roam-find-project ()
  (interactive)
  ;; Add the project file to the agenda after capture is finished
  (add-hook 'org-capture-after-finalize-hook #'my/org-roam-project-finalize-hook)

  ;; Select a project file to open, creating it if necessary
  (org-roam-node-find
   nil
   nil
   (my/org-roam-filter-by-tag "Project")
   :templates
   '(("p" "project" plain "* Goals\n\n%?\n\n* Tasks\n\n** TODO Add initial tasks\n\n* Dates\n\n"
      :if-new (file+head "%<%Y%m%d%H%M%S>-${slug}.org" "#+title: ${title}\n#+category: ${title}\n#+filetags: Project")
      :unnarrowed t))))

(defun my/org-roam-capture-inbox ()
  (interactive)
  (org-roam-capture- :node (org-roam-node-create)
                     :templates '(("i" "inbox" plain "* %?"
                                   :if-new (file+head "Inbox.org" "#+title: Inbox\n")))))

(defun my/org-roam-capture-task ()
  (interactive)
  ;; Add the project file to the agenda after capture is finished
  (add-hook 'org-capture-after-finalize-hook #'my/org-roam-project-finalize-hook)

  ;; Capture the new task, creating the project file if necessary
  (org-roam-capture- :node (org-roam-node-read
                            nil
                            (my/org-roam-filter-by-tag "Project"))
                     :templates '(("p" "project" plain "** TODO %?"
                                   :if-new (file+head+olp "%<%Y%m%d%H%M%S>-${slug}.org"
                                                          "#+title: ${title}\n#+category: ${title}\n#+filetags: Project"
                                                          ("Tasks"))))))

(defun my/org-roam-copy-todo-to-today ()
  (interactive)
  (let ((org-refile-keep t) ;; Set this to nil to delete the original!
        (org-roam-dailies-capture-templates
         '(("t" "tasks" entry "%?"
            :if-new (file+head+olp "%<%Y-%m-%d>.org" "#+title: %<%Y-%m-%d>\n" ("Tasks")))))
        (org-after-refile-insert-hook #'save-buffer)
        today-file
        pos)
    (save-window-excursion
      (org-roam-dailies--capture (current-time) t)
      (setq today-file (buffer-file-name))
      (setq pos (point)))

    ;; Only refile if the target file is different than the current file
    (unless (equal (file-truename today-file)
                   (file-truename (buffer-file-name)))
      (org-refile nil nil (list "Tasks" today-file nil pos)))))

(defun my-org-roam-get-all-tags ()
  "Save all roam tags to a buffer visting the file ~/Test."
  (interactive)
  (save-excursion
    (let ((buf (find-file-noselect "~/Test")))
      (set-buffer buf)
      (erase-buffer)
      (mapcar (lambda (n) (insert (car n) "\n"))
              (org-roam-db-query
               [:select :distinct [tag] :from tags ])))))

(defun my-org-roam-find-in-thoughts (node)
  (interactive)
  (let ((tags (org-roam-node-tags node)))
    (member "thoughts" tags)))

(defun helm-org-roam (&optional input candidates)
  (interactive)
  (require 'org-roam)
  (helm
   :input input
   :sources (list
             (helm-build-sync-source "Roam: "
               :must-match nil
               :fuzzy-match t
               :candidates (or candidates (org-roam--get-titles))
               :action
               '(("Find File" . (lambda (x)
                                  (--> x
                                       org-roam-node-from-title-or-alias
                                       (org-roam-node-visit it t))))
                 ("Insert link" . (lambda (x)
                                    (--> x
                                         org-roam-node-from-title-or-alias
                                         (insert
                                          (format
                                           "[[id:%s][%s]]"
                                           (org-roam-node-id it)
                                           (org-roam-node-title it))))))
                 ("Follow backlinks" . (lambda (x)
                                         (let ((candidates
                                                (--> x
                                                     org-roam-node-from-title-or-alias
                                                     org-roam-backlinks-get
                                                     (--map
                                                      (org-roam-node-title
                                                       (org-roam-backlink-source-node it))
                                                      it))))
                                           (helm-org-roam nil (or candidates (list x))))))))
             (helm-build-dummy-source
                 "Create note"
               :action '(("Capture note" . (lambda (candidate)
                                             (org-roam-capture-
                                              :node (org-roam-node-create :title candidate)
                                              :props '(:finalize find-file)))))))))

(defun my-xeft-get-title (file)
  "Return the title of FILE.
Return the first line as title, recognize Org Mode’s #+TITLE:
cookie, if the first line is empty, return the file name as the
title."
  (re-search-forward (rx "#+title:" (* whitespace)) nil t)
  (let ((bol (point)))
    (goto-char (line-end-position))
    (let ((title (buffer-substring-no-properties bol (point))))
      (if (string= title "")
          (file-name-base file)
        title))))

(defun my-xeft-file-filter (file)
  "Return nil if FILE should be ignored.
FILE is an absolute path. This default implementation ignores
directories, dot files, and files matched by
‘xeft-ignore-extension’."
  (and (file-regular-p file)
       (not (string-prefix-p
             "." (file-name-base file)))
       (not (string-suffix-p
             "~" file))))

(defun startup ()
  (interactive)
  (eshell-toggle nil)
  (switch-to-gnus)
  ;; (switch-to-fetchmail)
  (jump-to-org-agenda)
  (org-resolve-clocks)
  (unless (eq display-name 'imac)
    (display-battery-mode 1))
  ;; (stock-quote "/ES")
  )

(use-package corfu
  :disabled t
  ;; Optional customizations
  ;; :custom
  ;; (corfu-cycle t)                ;; Enable cycling for `corfu-next/previous'
  ;; (corfu-auto t)                 ;; Enable auto completion
  ;; (corfu-separator ?\s)          ;; Orderless field separator
  ;; (corfu-quit-at-boundary nil)   ;; Never quit at completion boundary
  ;; (corfu-quit-no-match nil)      ;; Never quit, even if there is no match
  ;; (corfu-preview-current nil)    ;; Disable current candidate preview
  ;; (corfu-preselect 'prompt)      ;; Preselect the prompt
  ;; (corfu-on-exact-match nil)     ;; Configure handling of exact matches
  ;; (corfu-scroll-margin 5)        ;; Use scroll margin

  ;; Enable Corfu only for certain modes.
  ;; :hook ((prog-mode . corfu-mode)
  ;;        (shell-mode . corfu-mode)
  ;;        (eshell-mode . corfu-mode))

  ;; Recommended: Enable Corfu globally.
  ;; This is recommended since Dabbrev can be used globally (M-/).
  ;; See also `corfu-exclude-modes'.
  :init
  (global-corfu-mode))

;; Use Dabbrev with Corfu!
(use-package dabbrev
  :disabled t
  ;; Swap M-/ and C-M-/
  :bind (("M-/" . dabbrev-completion)
         ("C-M-/" . dabbrev-expand))
  ;; Other useful Dabbrev configurations.
  :custom
  (dabbrev-ignored-buffer-regexps '("\\.\\(?:pdf\\|jpe?g\\|png\\)\\'")))

;; A few more useful configurations...
(use-package emacs
  :disabled t
  :init
  ;; TAB cycle if there are only few candidates
  (setq completion-cycle-threshold 3)

  ;; Emacs 28: Hide commands in M-x which do not apply to the current mode.
  ;; Corfu commands are hidden, since they are not supposed to be used via M-x.
  ;; (setq read-extended-command-predicate
  ;;       #'command-completion-default-include-p)

  ;; Enable indentation+completion using the TAB key.
  ;; `completion-at-point' is often bound to M-TAB.
  (setq tab-always-indent 'complete))

;; Enable rich annotations using the Marginalia package
(use-package marginalia
  :disabled t
  ;; Either bind `marginalia-cycle' globally or only in the minibuffer
  :bind (("M-A" . marginalia-cycle)
         :map minibuffer-local-map
         ("M-A" . marginalia-cycle))

  ;; The :init configuration is always executed (Not lazy!)
  :init

  ;; Must be in the :init section of use-package such that the mode gets
  ;; enabled right away. Note that this forces loading the package.
  (marginalia-mode))

(use-package orderless
  :disabled t
  :ensure t
  :custom
  (completion-styles '(orderless basic))
  (completion-category-overrides '((file (styles basic partial-completion)))))

;; Enable vertico
(use-package vertico
  :disabled t
  :init
  (vertico-mode)

  ;; Different scroll margin
  ;; (setq vertico-scroll-margin 0)

  ;; Show more candidates
  ;; (setq vertico-count 20)

  ;; Grow and shrink the Vertico minibuffer
  ;; (setq vertico-resize t)

  ;; Optionally enable cycling for `vertico-next' and `vertico-previous'.
  ;; (setq vertico-cycle t)
  )

;; Example configuration for Consult
(use-package consult
  :disabled t
  ;; Replace bindings. Lazily loaded due by `use-package'.
  ;; :bind (;; C-c bindings (mode-specific-map)
  ;;        ("C-c M-x" . consult-mode-command)
  ;;        ("C-c h" . consult-history)
  ;;        ("C-c k" . consult-kmacro)
  ;;        ("C-c m" . consult-man)
  ;;        ("C-c i" . consult-info)
  ;;        ([remap Info-search] . consult-info)
  ;;        ;; C-x bindings (ctl-x-map)
  ;;        ("C-x M-:" . consult-complex-command)     ;; orig. repeat-complex-command
  ;;        ("C-x b" . consult-buffer)                ;; orig. switch-to-buffer
  ;;        ("C-x 4 b" . consult-buffer-other-window) ;; orig. switch-to-buffer-other-window
  ;;        ("C-x 5 b" . consult-buffer-other-frame)  ;; orig. switch-to-buffer-other-frame
  ;;        ("C-x r b" . consult-bookmark)            ;; orig. bookmark-jump
  ;;        ("C-x p b" . consult-project-buffer)      ;; orig. project-switch-to-buffer
  ;;        ;; Custom M-# bindings for fast register access
  ;;        ("M-#" . consult-register-load)
  ;;        ("M-'" . consult-register-store)          ;; orig. abbrev-prefix-mark (unrelated)
  ;;        ("C-M-#" . consult-register)
  ;;        ;; Other custom bindings
  ;;        ("M-y" . consult-yank-pop)                ;; orig. yank-pop
  ;;        ;; M-g bindings (goto-map)
  ;;        ("M-g e" . consult-compile-error)
  ;;        ("M-g f" . consult-flymake)               ;; Alternative: consult-flycheck
  ;;        ("M-g g" . consult-goto-line)             ;; orig. goto-line
  ;;        ("M-g M-g" . consult-goto-line)           ;; orig. goto-line
  ;;        ("M-g o" . consult-outline)               ;; Alternative: consult-org-heading
  ;;        ("M-g m" . consult-mark)
  ;;        ("M-g k" . consult-global-mark)
  ;;        ("M-g i" . consult-imenu)
  ;;        ("M-g I" . consult-imenu-multi)
  ;;        ;; M-s bindings (search-map)
  ;;        ("M-s d" . consult-find)
  ;;        ("M-s D" . consult-locate)
  ;;        ("M-s g" . consult-grep)
  ;;        ("M-s G" . consult-git-grep)
  ;;        ("M-s r" . consult-ripgrep)
  ;;        ("M-s l" . consult-line)
  ;;        ("M-s L" . consult-line-multi)
  ;;        ("M-s k" . consult-keep-lines)
  ;;        ("M-s u" . consult-focus-lines)
  ;;        ;; Isearch integration
  ;;        ("M-s e" . consult-isearch-history)
  ;;        :map isearch-mode-map
  ;;        ("M-e" . consult-isearch-history)         ;; orig. isearch-edit-string
  ;;        ("M-s e" . consult-isearch-history)       ;; orig. isearch-edit-string
  ;;        ("M-s l" . consult-line)                  ;; needed by consult-line to detect isearch
  ;;        ("M-s L" . consult-line-multi)            ;; needed by consult-line to detect isearch
  ;;        ;; Minibuffer history
  ;;        :map minibuffer-local-map
  ;;        ("M-s" . consult-history)                 ;; orig. next-matching-history-element
  ;;        ("M-r" . consult-history))                ;; orig. previous-matching-history-element

  ;; Enable automatic preview at point in the *Completions* buffer. This is
  ;; relevant when you use the default completion UI.
  :hook (completion-list-mode . consult-preview-at-point-mode)

  ;; The :init configuration is always executed (Not lazy)
  :init

  ;; Optionally configure the register formatting. This improves the register
  ;; preview for `consult-register', `consult-register-load',
  ;; `consult-register-store' and the Emacs built-ins.
  (setq register-preview-delay 0.5
        register-preview-function #'consult-register-format)

  ;; Optionally tweak the register preview window.
  ;; This adds thin lines, sorting and hides the mode line of the window.
  (advice-add #'register-preview :override #'consult-register-window)

  ;; Use Consult to select xref locations with preview
  (setq xref-show-xrefs-function #'consult-xref
        xref-show-definitions-function #'consult-xref)

  ;; Configure other variables and modes in the :config section,
  ;; after lazily loading the package.
  :config

  ;; Optionally configure preview. The default value
  ;; is 'any, such that any key triggers the preview.
  ;; (setq consult-preview-key 'any)
  ;; (setq consult-preview-key "M-.")
  ;; (setq consult-preview-key '("S-<down>" "S-<up>"))
  ;; For some commands and buffer sources it is useful to configure the
  ;; :preview-key on a per-command basis using the `consult-customize' macro.
  (consult-customize
   consult-theme :preview-key '(:debounce 0.2 any)
   consult-ripgrep consult-git-grep consult-grep
   consult-bookmark consult-recent-file consult-xref
   consult--source-bookmark consult--source-file-register
   consult--source-recent-file consult--source-project-recent-file
   ;; :preview-key "M-."
   :preview-key '(:debounce 0.4 any))

  ;; Optionally configure the narrowing key.
  ;; Both < and C-+ work reasonably well.
  (setq consult-narrow-key "<") ;; "C-+"

  ;; Optionally make narrowing help available in the minibuffer.
  ;; You may want to use `embark-prefix-help-command' or which-key instead.
  ;; (define-key consult-narrow-map (vconcat consult-narrow-key "?") #'consult-narrow-help)

  ;; By default `consult-project-function' uses `project-root' from project.el.
  ;; Optionally configure a different project root function.
  ;;;; 1. project.el (the default)
  ;; (setq consult-project-function #'consult--default-project--function)
  ;;;; 2. vc.el (vc-root-dir)
  ;; (setq consult-project-function (lambda (_) (vc-root-dir)))
  ;;;; 3. locate-dominating-file
  ;; (setq consult-project-function (lambda (_) (locate-dominating-file "." ".git")))
  ;;;; 4. projectile.el (projectile-project-root)
  ;; (autoload 'projectile-project-root "projectile")
  ;; (setq consult-project-function (lambda (_) (projectile-project-root)))
  ;;;; 5. No project support
  ;; (setq consult-project-function nil)
  )

(use-package vundo
  :bind (("C-c C-/" . vundo)))
