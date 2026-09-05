;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
;;
;; image-merger entry point.  This file is *loaded by* chez-python (not run as
;; a standalone scheme-script), so the Python bindings (pyimport, pyapply,
;; with-python-runtime-handler, ...) are already present in the environment.
;;
;; Usage (normally through bin/image-merger):
;;   chez-python main.ss            ; reads IMAGE_MERGER_CONFIG / IMAGE_MERGER_ROOT
(import (image-merger config)
        (image-merger layout)
        (image-merger spec))

(define (sys-path-append! dir)
  (let* ((sys (pyimport "sys"))
         (path (object-get-attr sys "path"))
         (append! (object-get-attr path "append")))
    (pyapply append! (list dir))))

(define (python-str obj)
  (pyapply (object-get-attr (pyimport "builtins") "str") (list obj)))

(define (run)
  (define root (getenv "IMAGE_MERGER_ROOT"))
  (define config-path (getenv "IMAGE_MERGER_CONFIG"))
  (unless root
    (error 'image-merger "IMAGE_MERGER_ROOT is not set; run via bin/image-merger"))
  (unless config-path
    (error 'image-merger "no config file given; usage: image-merger <config-file>"))

  ;; Make the project venv (Pillow) and the python/ helper dir importable.
  (let ((minor (cadr (current-python-version))))
    (sys-path-append! (format "~a/.venv/lib/python3.~a/site-packages" root minor))
    (sys-path-append! (format "~a/.venv/lib64/python3.~a/site-packages" root minor)))
  (sys-path-append! (format "~a/python" root))

  (let* ((cfg (read-config config-path))
         (lay (compute-layout cfg))
         (spec (layout->spec lay))
         (merge (object-get-attr (pyimport "imagemerger") "merge")))
    (with-python-runtime-handler
      (lambda (exn pyexn)
        (errorf 'image-merger "python backend: ~a" (python-str pyexn)))
      (let ((out (pyapply merge (list spec))))
        (display out)
        (newline)))))

(run)
