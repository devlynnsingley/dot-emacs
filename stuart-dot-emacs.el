(require 'package) ;; You might already have this line
(add-to-list 'package-archives
             '("melpa" . "https://melpa.org/packages/") t)

(package-initialize)

(setq custom-file "~/.emacs.d/custom.el")
(load custom-file)

;; ============= package dev =============
;; === flycheck-haskell: install from tar
;;;;(package-install-file "~/dev/flycheck-haskell/dist/flycheck-haskell-0.9snapshot.tar")
;; === haskell-mode: install from directory
;;;;(add-to-list 'load-path "~/dev/haskell-mode/")
;;;;(require 'haskell-mode-autoloads)
;; =======================================

;; ============ pact mode =========
(add-to-list 'load-path "~/dev/pact-mode/")
(require 'pact-mode)
;;(require 'pact-flycheck)
;; ================================

(add-to-list 'load-path "~/Music/lilypond/lilypond-2.22.1/elisp")
(require 'lilypond-mode)

(exec-path-from-shell-initialize)


(setq-default electric-indent-inhibit t)


(global-unset-key "")

(require 'haskell-mode)
(require 'comint)
(require 'multiple-cursors)
(require 'hindent)

;(load-library "haskell-string")

(add-hook 'before-save-hook 'delete-trailing-whitespace)

(defun my-haskell-mode-hook ()
  (electric-indent-local-mode -1)
  (turn-on-haskell-indentation)
  (interactive-haskell-mode)
  (substitute-key-definition 'haskell-process-cabal-build 'haskell-interactive-switch interactive-haskell-mode-map)
  (substitute-key-definition 'haskell-mode-jump-to-def-or-tag 'haskell-mode-tag-find interactive-haskell-mode-map)
  (hindent-mode)
  (local-set-key [M-up] 'haskell-goto-prev-error)
  (local-set-key [M-down] 'haskell-goto-next-error)
  )
(add-hook 'haskell-mode-hook 'my-haskell-mode-hook)

;;(add-hook 'haskell-mode-hook (lambda () (electric-indent-local-mode -1)))


;;(add-hook 'haskell-mode-hook 'turn-on-haskell-indentation)
;;(add-hook 'haskell-mode-hook 'interactive-haskell-mode)

;(eval-after-load 'flycheck
;  '(add-hook 'flycheck-mode-hook #'flycheck-haskell-setup))


;;get rid of Cmd-: invoking Flyspell, call eval-expression (mapped to Alt-:)
;;(substitute-key-definition 'spellchecker-panel-or-ispell 'eval-expression osx-key-mode-map)

(add-hook 'html-mode-hook (lambda () (semantic-mode -1)))

(substitute-key-definition 'comint-dynamic-list-input-ring
						   'next-multiframe-window
						   comint-mode-map)

(substitute-key-definition 'mark-paragraph 'ns-do-hide-emacs global-map)

(require 'dired)
(require 'magit)
(defalias 'git 'magit-status)

(setq haskell-process-args-stack-ghci
          '("--ghci-options=-ferror-spans -fshow-loaded-modules"
            "--no-build" "--no-load"))

(defmacro debug-read (msg &rest args)
  (let* ((fmt (concat msg ": " (mapconcat (lambda (arg)
											(concat (symbol-name arg) "=%s")) args ","))))
	`(read-string (format ,fmt ,@args))))

(defun rcirc-kill-all () (interactive)
  (let ((rbufs
		 (remove-if 'not
					(mapcar (lambda (buf)
							  (with-current-buffer buf
								(if (eq 'rcirc-mode major-mode) buf)))
							(buffer-list)))))
	(if rbufs
		(if (y-or-n-p (format "Kill %s?" (mapconcat 'buffer-name rbufs ", ")))
			(progn
			  (mapcar 'kill-buffer rbufs)
			  (message "rcirc-kill-all: done."))
		  (message "rcirc-kill-all: aborted."))
	  (message "rcirc-kill-all: no rcirc buffers found."))))


;(add-hook 'after-init-hook #'global-flycheck-mode)


(defun nerf-recentf (&rest ignore)
  (setq recentf-exclude (append '(".*") recentf-exclude)))

(defun restore-recentf (&rest ignore)
  (setq recentf-exclude (remove ".*" recentf-exclude)))


(run-at-time nil (* 5 60) 'recentf-save-list)


(defun my-init-hook ()
  ;(define-key haskell-mode-map [M-up] 'flycheck-previous-error)
  ;(define-key haskell-mode-map [M-down] 'flycheck-next-error)
  (advice-add 'haskell-mode-jump-to-def-or-tag :before #'push-mark-maybe)
  (advice-add 'package-install :before #'nerf-recentf)
  (advice-add 'package-install :after #'restore-recentf)
  (advice-add 'recentf-save-list :before #'nerf-recentf)
  (advice-add 'recentf-save-list :after #'restore-recentf)

  (add-hook 'markdown-mode-hook 'pandoc-mode)
  (add-hook 'pandoc-mode-hook 'pandoc-load-default-settings)

  (setq save-silently t)

)

(add-hook 'after-init-hook 'my-init-hook)


(defun colorize-buffer ()
  (interactive)
  (ansi-color-apply-on-region (point-min) (point-max)))
;(setq ido-enable-flex-matching t)
;(setq ido-everywhere t)
;(ido-mode 1)



(defun grab-regexp-search-ring () (interactive)
  (kill-new (car regexp-search-ring)))


(defun transpose-lines-down () (interactive)
  (line-move 1)
  (transpose-lines 1)
  (line-move -1))

(global-set-key [C-down] 'transpose-lines-down)

(defun transpose-lines-up () (interactive)
  (transpose-lines 1)
  (line-move -2))

(global-set-key [C-up] 'transpose-lines-up)

;;(add-to-list 'literate-haskell-mode-hook 'turn-on-pandoc)



(defun marker-is-point-p (marker)
  "test if marker is current point"
  (and (eq (marker-buffer marker) (current-buffer))
       (= (marker-position marker) (point))))

(defun push-mark-maybe (&optional whatevs)
  "push mark onto `global-mark-ring' if mark head or tail is not current location"
  (if (not global-mark-ring) (error "global-mark-ring empty")
    (unless (or (marker-is-point-p (car global-mark-ring))
                (marker-is-point-p (car (reverse global-mark-ring))))
      (push-mark))))


(defun backward-global-mark ()
  "use `pop-global-mark', pushing current point if not on ring."
  (interactive)
  (push-mark-maybe)
  (when (marker-is-point-p (car global-mark-ring))
    (call-interactively 'pop-global-mark))
  (call-interactively 'pop-global-mark))

(defun forward-global-mark ()
  "hack `pop-global-mark' to go in reverse, pushing current point if not on ring."
  (interactive)
  (push-mark-maybe)
  (setq global-mark-ring (nreverse global-mark-ring))
  (when (marker-is-point-p (car global-mark-ring))
    (call-interactively 'pop-global-mark))
  (call-interactively 'pop-global-mark)
  (setq global-mark-ring (nreverse global-mark-ring)))

(global-set-key [M-left] (quote backward-global-mark))
(global-set-key [M-right] (quote forward-global-mark))


(defun hgrep (pfx)
  (interactive "P")
  (grep-compute-defaults)
  (rgrep
   (read-regexp
    "Search for"
    (concat
     "\\b"
     (replace-regexp-in-string
      "^_" "_*" (grep-tag-default))
     "\\b")
    'grep-regexp-history)
   "*.hs"
   (let* ((bn (buffer-file-name))
          (dom-dir
           (and bn
                ;(concat
                 (locate-dominating-file
                  (buffer-file-name)
                  (lambda (file)
                    (and
                     file (file-directory-p file)
                     (directory-files file nil ".*\\.cabal$"))))
                 )))
                 ;"src"))))
     (if (and (not pfx) dom-dir) dom-dir
       (read-file-name "Base directory: " dom-dir nil nil nil 'file-directory-p)))))



(defun new-temp-buffer ()
  (interactive)
  (switch-to-buffer (generate-new-buffer "*tmp*")))

(global-set-key [C-n] 'new-temp-buffer)

(global-unset-key "")

(defun rb () (interactive) (revert-buffer nil t))

;When you have an active region that spans multiple lines, the following will
;add a cursor to each line:

;;(global-set-key (kbd "C-S-c C-S-c") 'mc/edit-lines)
(global-set-key [729] (quote set-rectangular-region-anchor))

;When you want to add multiple cursors not based on continuous lines, but based on
;keywords in the buffer, use:

(global-set-key (kbd "C->") 'mc/mark-next-like-this)
(global-set-key (kbd "C-<") 'mc/mark-previous-like-this)
(global-set-key (kbd "C-c C-<") 'mc/mark-all-like-this)

(global-set-key (kbd "C-c C-f") 'find-function)
(global-set-key (kbd "C-c C-v") 'find-variable)


(defun maximize ()
  (interactive)
  (let* ((f (selected-frame)))
    (mapcar
     (lambda (d)
       (when (member f (cdr (assoc 'frames d)))
         (let* ((wa (cdr (assoc 'workarea d))))
           (set-frame-position f (nth 0 wa) (nth 1 wa))
           (set-frame-size f (- (nth 2 wa) 36) (nth 3 wa) t))))
     (display-monitor-attributes-list))))

(setq visible-bell 1)

(defun filter-matches ()
  (interactive)
  (let ((re (read-regexp "search for: ")))
    (save-excursion
      (goto-char (point-min))
      (while (< (point) (point-max))
        (if (re-search-forward re (line-end-position) t)
            (beginning-of-line 2)
          (progn
            (beginning-of-line)
            (kill-line t)))))))

(defvar-local pact-repl-cursor-line nil
  "Stores cursor line where `pact-repl-next' was last called.")
(defvar-local pact-repl-last-line nil
  "Stores last line where `pact-repl-next' found a match.")

(defun pact-repl-find (fwd)
  (let* ((cursor-line (line-number-at-pos))
         (reset (not (eql cursor-line pact-repl-cursor-line)))
         (last-line
          (if reset (if fwd 0 cursor-line)
            (+ (if fwd 1 0) pact-repl-last-line)))
         (re "^pact> \\(.+\\)$")
         (foo (message "lkjhlkjh %s %s %s %s %s" last-line reset cursor-line pact-repl-cursor-line pact-repl-last-line))
         (found
          (save-excursion
            (goto-line last-line)
            (when (if fwd (re-search-forward re nil t)
                    (re-search-backward re nil t))
              (setq-local pact-repl-last-line (line-number-at-pos))
              (match-string 1)))))
    (if found
        (progn
          (save-excursion
            (beginning-of-line)
            (unless (looking-at "pact> ") (message "Not at 'pact> ' prompt"))
            (forward-char 6)
            (delete-forward-char (- (line-end-position) (point)))
            (set-text-properties 0 (length found) nil found)
            (setq-local pact-repl-cursor-line (line-number-at-pos)))
          (insert found))
      (message "No history found"))))

(defun pact-repl-next () (interactive) (pact-repl-find t))
(defun pact-repl-prev () (interactive) (pact-repl-find nil))

(global-set-key (kbd "C-c <C-down>") 'pact-repl-next)
(global-set-key (kbd "C-c <C-up>") 'pact-repl-prev)

(defun wc-para ()
  (interactive)
  (save-excursion
    (backward-paragraph)
    (let ((p (point)))
      (forward-paragraph)
      (let ((d (- (point) p)))
        (message "%d" d)
        d))))

(defun set-face-height (height)
  "Set global font face height to HEIGHT. Interactive prompts for value."
  (interactive (list (read-number "Set face height to: " (face-attribute 'default :height))))
  (set-face-attribute 'default nil :height height))

(defun rgrep-again ()
  "Re-run rgrep with a new regexp on history values for  FILES (last filename pattern)
and DIR (last directory). Note that DIR uses `file-name-history` so this gets dodgy
after e.g. `find-file`."
  (interactive)
  (rgrep (grep-read-regexp) (car grep-files-history) (car file-name-history)))

(set-face-height 160)
;;; .emacs ends here
