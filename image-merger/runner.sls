;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; (image-merger runner) — the Python-boundary orchestration, as a library.
;;
;; It statically imports the chez-python *environment* libraries (api, coerce,
;; function), which is safe because this library is only ever instantiated from
;; inside the custom scheme-start program — after libpython3 has been loaded
;; and Python initialised there.
;;
;; The boot contains NO environment-specific paths: the Python module search
;; path (venv site-packages + the python/ backend dir) is injected by the
;; launcher (bin/image-merger) through the PYTHONPATH environment variable,
;; which the embedded interpreter picks up during Py_Initialize.
(library (image-merger runner)
  (export run)
  (import (chezscheme)
          (chez-python ffi env api)
          (chez-python ffi env function)
          (image-merger config)
          (image-merger layout)
          (image-merger spec))

  (define (python-str obj)
    (pyapply (object-get-attr (pyimport "builtins") "str") (list obj)))

  (define (load-merge)
    ;; Importing the backend outside of the call handler would surface only
    ;; chez-python's generic "Unknown internal errors" message; record the
    ;; python error here and raise it after the handler returns (raising
    ;; inside the handler body does not propagate reliably).
    (define pyerr #f)
    (define merge
      (with-python-runtime-handler
       (lambda (exn pyexn)
         (set! pyerr (python-str pyexn)))
       (object-get-attr (pyimport "imagemerger") "merge")))
    (when pyerr
      (errorf 'image-merger "python backend: ~a" pyerr))
    merge)

  (define (run config-path)
    (let* ((cfg (read-config config-path))
           (lay (compute-layout cfg))
           (spec (layout->spec lay))
           (merge (load-merge)))
      (with-python-runtime-handler
       (lambda (exn pyexn)
         (errorf 'image-merger "python backend: ~a" (python-str pyexn)))
       (let ((out (pyapply merge (list spec))))
         (display out)
         (newline)
         out)))))
