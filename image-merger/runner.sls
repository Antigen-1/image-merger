;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; (image-merger runner) — the Python-boundary orchestration, as a library.
;;
;; It statically imports the chez-python *environment* libraries (api, coerce,
;; function), which is safe because this library is only ever instantiated from
;; inside the custom scheme-start program — after libpython3 has been loaded
;; and Python initialised there.  `run` reads the config path, computes the
;; layout/spec with the pure libraries and hands the spec to the Pillow
;; backend through one pyapply call.
(library (image-merger runner)
  (export run)
  (import (chezscheme)
          (chez-python ffi config)
          (chez-python ffi env api)
          (chez-python ffi env function)
          (image-merger config)
          (image-merger layout)
          (image-merger spec))

  (define (sys-path-append! dir)
    (let* ((sys (pyimport "sys"))
           (path (object-get-attr sys "path"))
           (append! (object-get-attr path "append")))
      (pyapply append! (list dir))))

  (define (python-str obj)
    (pyapply (object-get-attr (pyimport "builtins") "str") (list obj)))

  (define (run config-path)
    (define root (getenv "IMAGE_MERGER_ROOT"))
    (unless root
      (errorf 'image-merger
              "IMAGE_MERGER_ROOT is not set; run via bin/image-merger or `make run`"))
    ;; Make the project venv (Pillow) and the python/ helper dir importable.
    (let ((minor (cadr (current-python-version))))
      (sys-path-append!
       (format "~a/.venv/lib/python3.~a/site-packages" root minor))
      (sys-path-append!
       (format "~a/.venv/lib64/python3.~a/site-packages" root minor)))
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
         (newline)
         out)))))
