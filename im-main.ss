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
  "usage: image-merger [--pythonpath <dirs>] <config-file>

Stitch images onto a grid according to an s-exp config file (see README).
Requires the cached boot built by `make build` (.build/image-merger.boot).

options:
  --pythonpath <dirs>  colon-separated directories prepended to Python's
                       module search path (repeatable); set before the
                       embedded interpreter is initialised, so Pillow and the
                       backend module can come from any location
  -h, --help           show this help and exit

exit status: 0 ok; 1 runtime error; 2 usage error
")

;; Parse args: [--pythonpath dirs]* config
(define (starts-with-dash? s)
  (and (> (string-length s) 0) (char=? (string-ref s 0) #\-)))

(define (parse-args args)
  (let loop ((rest args) (pp '()) (pos '()))
    (cond
     ((null? rest)
      (if (null? pos)
          (errorf 'image-merger "usage: image-merger [--pythonpath <dirs>] <config-file>")
          (values (reverse pp) (reverse pos))))
     ((or (equal? (car rest) "-h") (equal? (car rest) "--help"))
      (say-usage (current-output-port))
      (exit 0))
     ((equal? (car rest) "--pythonpath")
      (if (or (null? (cdr rest)) (starts-with-dash? (cadr rest)))
          (errorf 'image-merger "--pythonpath requires a directory argument")
          (loop (cddr rest) (cons (cadr rest) pp) pos)))
     (else
      (loop (cdr rest) pp (cons (car rest) pos))))))

;; Make the --pythonpath directories visible to the embedded interpreter:
;; Py_Initialize reads PYTHONPATH from the process environment.
(define (colon-join strs)
  (let loop ((l strs) (acc ""))
    (cond ((null? l) acc)
          ((string=? acc "") (loop (cdr l) (car l)))
          (else (loop (cdr l) (format "~a:~a" acc (car l)))))))

(define (apply-pythonpath! pp)
  (unless (null? pp)
    (putenv "PYTHONPATH"
            (let ((extra (colon-join (reverse pp)))
                  (existing (or (getenv "PYTHONPATH") "")))
              (if (string=? existing "")
                  extra
                  (format "~a:~a" extra existing))))))

(define (say-usage port)
  (display usage-text port))

;; Which stage raised, for actionable errors
(define *stage* 'start)

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
   (guard (exn (else
                (display (format "[~a] " *stage*) (current-error-port))
                (display (condition-text exn) (current-error-port))
                (newline (current-error-port))
                (exit (if (eq? *stage* 'parse) 2 1))))
     ;; Stage 1: libpython3 must be loaded before anything from the
     ;; chez-python environment libraries is instantiated.
     (set! *stage* 'parse)
     (let-values (((pp config) (parse-args args)))
       (when (null? config)
         (say-usage (current-error-port))
         (exit 2))
       (apply-pythonpath! pp)
       (set! *stage* 'load-python)
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
       (set! *stage* 'env)
       (let ((e2 (copy-environment
                  (environment '(chezscheme)
                               '(chez-python ffi env api)
                               '(chez-python ffi env coerce)
                               '(chez-python ffi env function)
                               '(chez-python ffi config)
                               '(image-merger runner))
                  #t)))
         (set! *stage* 'initialize-python)
         (eval '(initialize-python) e2)
         (set! *stage* 'run)
         (eval `(run ,(car config)) e2))
       (exit 0)))))
