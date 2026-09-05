;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; (image-merger spec) — turn a layout into the flat, positional data contract
;; that is handed to the Python backend through chez-python.
;;
;; The contract contains no Scheme symbols and no dictionaries: `->py-datum`
;; only supports integers, flonums, strings, booleans, lists and vectors, so we
;; emit a single nested list that the Python `merge` function unpacks
;; positionally:
;;
;;   (output width height background items row-labels column-labels)
;;
;;   item        = (file x y w h mode align-h align-v exact-w exact-h)
;;   label       = (text x y w h align-h align-v font size color)
(library (image-merger spec)
  (export layout->spec)
  (import (chezscheme) (image-merger layout))

  (define (sym->str s) (symbol->string s))

  (define (item->spec it)
    ;; (file x y w h mode ah av ew eh) -> all-string/symbol fields flattened
    (list (car it)                       ; file
          (cadr it) (caddr it)           ; x y
          (cadddr it)                    ; w
          (list-ref it 4)                ; h
          (sym->str (list-ref it 5))     ; mode
          (sym->str (list-ref it 6))     ; align-h
          (sym->str (list-ref it 7))     ; align-v
          (or (list-ref it 8) 0)         ; exact-w
          (or (list-ref it 9) 0)))       ; exact-h

  (define (label->spec lb)
    ;; (text x y w h ah av font size color)
    (list (car lb)
          (cadr lb) (caddr lb) (cadddr lb) (list-ref lb 4)
          (sym->str (list-ref lb 5))
          (sym->str (list-ref lb 6))
          (list-ref lb 7)                ; font (string or #f)
          (list-ref lb 8)                ; size
          (list-ref lb 9)))              ; color

  (define (layout->spec layout)
    (list
      (layout-output layout)
      (layout-width layout)
      (layout-height layout)
      (layout-background layout)
      (map item->spec (layout-items layout))
      (map label->spec (layout-row-labels layout))
      (map label->spec (layout-column-labels layout)))))
