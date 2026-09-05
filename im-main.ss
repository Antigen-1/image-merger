;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; image-merger boot program — custom scheme-start.
;;
;; This program is compiled into .build/image-merger.boot on top of
;; chez-python.boot (which supplies the chez-python libraries).  Unlike
;; chez-python's own scheme-start it needs no flags, no file loading and no
;; REPL: it is a plain batch CLI that takes exactly one config file.
;;
;; Startup sequence (order matters — the chez-python *environment* libraries
;; must only be instantiated after libpython3 is loaded):
;;   1. load libpython3 and record the version          (safe libraries only)
;;   2. build the full environment (api/coerce/function/runner) and
;;      initialise the embedded Python interpreter
;;   3. run the merger for the given config, then exit 0/1/2
(import (chezscheme) (rnrs conditions))

(define usage-text
  "usage: image-merger <config-file>

Stitch images onto a grid according to an s-exp config file (see README).
Requires the cached boot built by `make build` (.build/image-merger.boot)
and the project venv created by `make venv`.

options:
  -h, --help    show this help and exit

exit status: 0 ok; 1 runtime error; 2 usage error
")

(define (say-usage port)
  (display usage-text port))

;; Format a condition like the Chez/chez-python runtime would: apply the
;; message template to its irritants when a format condition is present.
(define (condition-text exn)
  (cond
    ((and (format-condition? exn) (message-condition? exn))
     (apply format #f (condition-message exn) (condition-irritants exn)))
    ((message-condition? exn) (condition-message exn))
    (else (format "~s" exn))))

(scheme-start
 (lambda args
   (cond
    ((or (null? args) (> (length args) 1))
     (say-usage (current-error-port))
     (exit 2))
    ((member (car args) '("-h" "--help"))
     (say-usage (current-output-port))
     (exit 0))
    (else
     (guard (exn (else
                  (display (condition-text exn) (current-error-port))
                  (newline (current-error-port))
                  (exit 1)))
       ;; Stage 1: libpython3 must be loaded before anything from the
       ;; chez-python environment libraries is instantiated.
       (let ((e1 (copy-environment
                  (environment '(chezscheme)
                               '(chez-python ffi system)
                               '(chez-python ffi config))
                  #t)))
         (eval '(begin
                  (load-python)
                  (current-python-version (python-version)))
               e1))
       ;; Stage 2: full environment with the Python object API + the merger
       ;; runner, then initialise Python and run.
       (let ((e2 (copy-environment
                  (environment '(chezscheme)
                               '(chez-python ffi env api)
                               '(chez-python ffi env coerce)
                               '(chez-python ffi env function)
                               '(chez-python ffi config)
                               '(image-merger runner))
                  #t)))
         (eval '(initialize-python) e2)
         (eval `(run ,(car args)) e2))
       (exit 0))))))
