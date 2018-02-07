;;; playground.el --- Manage sandboxes for alternative configurations -*- lexical-binding: t -*-

;; Copyright (C) 2018 by Akira Komamura

;; Author: Akira Komamura <akira.komamura@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "24.4"))
;; Keywords: maint
;; URL: https://github.com/akirak/emacs-playground

;; This file is not part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Playground is a playground for Emacs. Its basic idea is to create
;; an isolated directory called a sandbox and make it $HOME of Emacs.
;; Playground allows you to easily experiment with various Emacs configuration
;; repositories available on GitHub, while keeping your current configuration
;; untouched (almost, except for a stuff for Playground). It can also simplify
;; your workflow in Emacs by hiding irrelevant files and directories
;; existing in your home directory.

;;; Code:

(require 'cl-lib)

(defconst playground-original-home-directory (concat "~" user-login-name)
  "The original home directory of the user.")

(defcustom playground-script-directory
  (expand-file-name ".local/bin" playground-original-home-directory)
  "The directory where the wrapper script is saved."
  :group 'playground)

(defcustom playground-directory
  (expand-file-name ".emacs-play" playground-original-home-directory)
  "The directory where home directories of playground are stored."
  :group 'playground)

(defcustom playground-inherited-contents
  '(".gnupg" ".config/git" ".gitconfig" ".cache/chromium" ".config/chromium")
  "Files and directories in the home directory that should be added to virtual home directories."
  :group 'playground)

(defcustom playground-dotemacs-list
      '(
        (:repo "https://github.com/bbatsov/prelude.git" :name "prelude")
        (:repo "https://github.com/seagle0128/.emacs.d.git")
        (:repo "https://github.com/purcell/emacs.d.git")
        (:repo "https://github.com/syl20bnr/spacemacs.git" :name "spacemacs")
        (:repo "https://github.com/eschulte/emacs24-starter-kit.git" :name "emacs24-starter-kit")
        (:repo "https://github.com/akirak/emacs.d.git")
        )
      "List of configuration repositories suggested in ‘playground-checkout’."
      :group 'playground)

(defun playground--emacs-executable ()
  "Get the executable file of Emacs."
  (executable-find (car command-line-args)))

(defun playground--script-paths ()
  "A list of script files generated by `playground-persist' command."
  (let ((dir playground-script-directory)
        (original-name (file-name-nondirectory (playground--emacs-executable))))
    (mapcar (lambda (filename) (expand-file-name filename dir))
            (list original-name (concat original-name "-noplay")))))

(defun playground--read-url (prompt)
  "Read a repository URL from the minibuffer, prompting with a string PROMPT."
  (read-from-minibuffer prompt))

(defun playground--update-symlinks (dest)
  "Produce missing symbolic links in the sandbox directory DEST."
  (let ((origin playground-original-home-directory))
    (cl-loop for relpath in playground-inherited-contents
             do (let ((src (expand-file-name relpath origin))
                      (new (expand-file-name relpath dest)))
                  (when (and (not (file-exists-p new))
                             (file-exists-p src))
                    (make-directory (file-name-directory new) t)
                    (make-symbolic-link src new))
                  ))))

(defconst playground--github-repo-path-pattern
  "\\(?:[0-9a-z][-0-9a-z]+/[-a-z0-9_.]+?[0-9a-z]\\)"
  "A regular expression for a repository path (user/repo) on GitHub.")

(defconst playground--github-repo-url-patterns
  (list (concat "^git@github\.com:\\("
                playground--github-repo-path-pattern
                "\\)\\(?:\.git\\)$")
        (concat "^https://github\.com/\\("
                playground--github-repo-path-pattern
                "\\)\\(\.git\\)?$"))
  "A list of regular expressions that match a repository URL on GitHub.")

(defun playground--github-repo-path-p (path)
  "Check if PATH is a repository path (user/repo) on GitHub."
  (let ((case-fold-search t))
    (string-match-p (concat "^" playground--github-repo-path-pattern "$") path)))

(defun playground--parse-github-url (url)
  "Return a repository path (user/repo) if URL is a repository URL on GitHub."
  (cl-loop for pattern in playground--github-repo-url-patterns
           when (string-match pattern url)
           return (match-string 1 url)))

(defun playground--github-repo-path-to-https-url (path)
  "Convert a GitHub repository PATH into a HTTPS url."
  (concat "https://github.com/" path ".git"))

(defun playground--build-name-from-url (url)
  "Produce a sandbox name from a repository URL."
  (pcase (playground--parse-github-url url)
    (`nil "")
    (rpath (car (split-string rpath "/")))))

(defun playground--directory (name)
  "Get the path of a sandbox named NAME."
  (expand-file-name name playground-directory))

;;;###autoload
(defun playground-update-symlinks ()
  "Update missing symbolic links in existing local sandboxes."
  (interactive)
  (mapc #'playground--update-symlinks
        (directory-files playground-directory t "^\[^.\]")))

(defvar playground-last-config-home nil
  "Path to the sandbox last run.")

(defun playground--process-buffer-name (name)
  "Generate the name of a buffer for a sandbox named NAME."
  (format "*play %s*" name))

(defun playground--start (name home)
  "Start a sandbox named NAME at HOME."
  ;; Fail if Emacs is not run inside a window system
  (unless window-system
    (error "Can't start another Emacs as you are not using a window system"))

  (let ((process-environment (cons (concat "HOME=" home)
                                   process-environment))
        ;; Convert default-directory to full-path so Playground can be run on cask
        (default-directory (expand-file-name default-directory)))
    (start-process "playground"
                   (playground--process-buffer-name name)
                   (playground--emacs-executable))
    (setq playground-last-config-home home)))

(defun playground--get-local-sandboxes ()
  (directory-files playground-directory nil "^\[^.\]"))

(defcustom playground-completion-type nil
  "Completion engine used for playground.

The possible values are: nil and helm. "
  :group 'playground
  :type 'symbol
  :options '(helm nil)
  :type 'symbol)

(defun playground--completion-engine ()
  "Determine which completion engine to use.

If `playground-use-completion' variable is defined, use the value.
Otherwise, consider the values of `helm-mode' and `ivy-mode' (or `counsel-mode')."
  (or playground-completion-type
      (cond
       ((and (boundp 'helm-mode) helm-mode) 'helm))))

(defun playground--dotemacs-alist (&optional list-of-plists)
  "Build an alist of (name . plist) from LIST-OF-PLISTS of dotemacs.

If the argument is not given, the value is taken from `playground-dotemacs-list'."
  (mapcar (lambda (plist)
            (let ((name (or (plist-get plist :name)
                            (playground--build-name-from-url (plist-get plist :repo)))))
              (cons name plist)))
          (or list-of-plists playground-dotemacs-list)))

(defun playground--helm-select-sandbox (prompt local remote)
  "Select a sandbox using a Helm interface with PROMPT.

LOCAL is a list of local sandbox names, and REMOTE is an alist of (name . spec)."
  (require 'helm)
  (helm :prompt prompt
        :sources (list (helm-build-sync-source
                           "Local"
                         :candidates local
                         :action
                         (lambda (name) (list name 'local)))
                       (helm-build-sync-source
                           "Clone .emacs.d from a remote repository"
                         :candidates
                         (cl-loop for (name . plist) in remote
                                  unless (member name local)
                                  collect (cons (format "%s: %s"
                                                        name
                                                        (plist-get plist :repo))
                                                (list name plist))))
                       (helm-build-dummy-source
                           "Clone from a URL"
                         :action
                         (lambda (url)
                           `(,(playground--build-name-from-url url)
                             (:repo ,url)))))))


(defun playground--select-sandbox (prompt &optional completion)
  "Let the user select an existing sandbox or a configuration spec and return
a list of (user &optional spec). The result is used in `playground-checkout'.

COMPLETION is a symbol representing a completion engine to be used. See
`playground-completion-type' for possible values. "
  (let ((local (playground--get-local-sandboxes))
        (remote (playground--dotemacs-alist)))
    (pcase (or completion (playground--completion-engine))
      ('helm (playground--helm-select-sandbox local remote))
      (_ (let* ((candidates (append (cl-loop for name in local
                                             collect (cons (format "%s" name)
                                                           (list name 'local)))
                                    (cl-loop for (name . plist) in remote
                                             unless (member name local)
                                             collect (cons (format "%s: %s"
                                                                   name
                                                                   (plist-get plist :repo))
                                                           (list name plist)))))
                (result (completing-read prompt candidates nil nil)))
           (pcase result
             (`nil nil)
             ((let `(,_ . ,pat) (assoc result candidates)) pat)
             ((pred playground--git-url-p)
              `(,(playground--build-name-from-url result)
                (:repo ,result)))))))))

(defun playground--git-url-p (s)
  "Test if S is a URL to a Git repository."
  (or (string-match-p "^\\(?:ssh|rsync|git|https?|file\\)://.+\.git/?$" s)
      (string-match-p "^\\(?:[-.a-zA-Z1-9]+@\\)?[-./a-zA-Z1-9]+:[-./a-zA-Z1-9]+\.git/?$" s)
      (string-match-p (concat "^https://github.com/"
                              playground--github-repo-path-pattern) s)
      (and (string-suffix-p ".git" s) (file-directory-p s)) ; local bare repository
      (and (file-directory-p s) (file-directory-p (expand-file-name ".git" s))) ; local working tree
      ))

(cl-defun playground--initialize-sandbox (name url
                                         &key
                                         (recursive t)
                                         (depth 1))
  "Initialize a sandbox with a configuration repository."
  (let ((dpath (playground--directory name)))
    (condition-case err
        (progn
          (make-directory dpath t)
          (apply 'process-lines
                 (remove nil (list "git" "clone"
                                   (when recursive "--recursive")
                                   (when depth
                                     (concat "--depth="
                                             (cond ((stringp depth) depth)
                                                   ((numberp depth) (int-to-string depth)))))
                                   url
                                   (expand-file-name ".emacs.d" dpath)))
                 )
          (playground--update-symlinks dpath)
          dpath)
      (error (progn (message (format "Cleaning up %s..." dpath))
                    (delete-directory dpath t)
                    (error (error-message-string err)))))))

(cl-defun playground--start-with-dotemacs (name
                                           &rest other-props
                                           &key repo &allow-other-keys)
  "Start Emacs on a sandbox named NAME."
  (when (null repo)
    (error "You must pass :repo to playground--start-with-dotemacs function"))
  (let ((url (if (playground--github-repo-path-p repo)
                 (playground--github-repo-path-to-https-url repo)
               repo)))
    (playground--start name
                       (apply 'playground--initialize-sandbox
                              name url
                              (cl-remprop 'repo other-props)))))

;;;###autoload
(defun playground-checkout (name &optional spec)
  "Start Emacs on a sandbox named NAME with a dotemacs SPEC."
  (interactive (playground--select-sandbox "Select a sandbox or enter a URL: "))

  (let* ((dpath (playground--directory name))
         (exists (file-directory-p dpath)))
    (cond
     (exists (playground--start name dpath))
     ((eq spec 'local) (error "A sandbox named %s does not exist locally" name))
     (spec (apply #'playground--start-with-dotemacs name spec))
     (t (pcase (assoc name (playground--sandbox-alist))
          (`nil (error "A sandbox named %s is not configured" name))
          (pair (apply #'playground--start-with-dotemacs pair)))))))

;;;###autoload
(defun playground-start-last ()
  "Start Emacs on the last sandbox run by Playground."
  (interactive)
  (pcase (and (boundp 'playground-last-config-home)
              playground-last-config-home)
    (`nil (error "Play has not been run yet. Run 'playground-checkout'"))
    (home (let* ((name (file-name-nondirectory home))
                 (proc (get-buffer-process (playground--process-buffer-name name))))
            (if (and proc (process-live-p proc))
                (when (yes-or-no-p (format "%s is still running. Kill it? " name))
                  (let ((sentinel (lambda (_ event)
                                            (cond
                                             ((string-prefix-p "killed" event) (playground--start name home))))))
                    (set-process-sentinel proc sentinel)
                    (kill-process proc)))
              (playground--start name home))))))

;;;###autoload
(defun playground-persist ()
  "Generate wrapper scripts to make the last sandbox environment the default."
  (interactive)

  (unless (boundp 'playground-last-config-home)
    (error "No play instance has been run yet"))

  (let ((home playground-last-config-home))
    (when (yes-or-no-p (format "Set $HOME of Emacs to %s? " home))
      (cl-destructuring-bind
          (wrapper unwrapper) (playground--script-paths)
        (playground--generate-runner wrapper home)
        (playground--generate-runner unwrapper playground-original-home-directory)
        (message (format "%s now starts with %s as $HOME. Use %s to start normally"
                         (file-name-nondirectory wrapper)
                         home
                         (file-name-nondirectory unwrapper)))))))

(defun playground--generate-runner (fpath home)
  "Generate an executable script at FPATH for running Emacs on HOME."
  (with-temp-file fpath
    (insert (concat "#!/bin/sh\n"
                    (format "HOME=%s exec %s \"$@\""
                            (shell-quote-argument home)
                            (shell-quote-argument (playground--emacs-executable))))))
  (set-file-modes fpath #o744))

;;;###autoload
(defun playground-return ()
  "Delete wrapper scripts generated by Playground."
  (interactive)
  (when (yes-or-no-p "Delete the scripts created by play? ")
    (mapc 'delete-file (cl-remove-if-not 'file-exists-p (playground--script-paths)))))

(provide 'playground)

;;; playground.el ends here
