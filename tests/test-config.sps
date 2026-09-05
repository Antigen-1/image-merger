#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing) (image-merger config))

(define (expect-error thunk)
  (guard (exn (else #t)) (thunk) #f))

(test-begin "config")

(test-runner-on-test-end!
 (test-runner-current)
 (lambda (r)
   (when (memq (test-result-kind r) '(fail))
     (display "FAILED: ")
     (write (test-result-ref r 'test-name))
     (display " expected=")
     (write (test-result-ref r 'expected-value))
     (display " actual=")
     (write (test-result-ref r 'actual-value))
     (newline))))

;; minimal config: required fields only, defaults elsewhere
(let ((cfg (parse-config
            '(image-merger
               (output "out.png")
               (canvas (grid 2 3) (cell-size 100 50))
               (cell (row 0) (column 0) (image "a.png"))))))
  (test-equal "out.png" (config-output cfg))
  (test-equal 2 (canvas-rows (config-canvas cfg)))
  (test-equal 3 (canvas-cols (config-canvas cfg)))
  (test-equal 100 (canvas-cell-width (config-canvas cfg)))
  (test-equal 50 (canvas-cell-height (config-canvas cfg)))
  (test-equal 0 (canvas-gap-x (config-canvas cfg)))
  (test-equal 0 (canvas-gap-y (config-canvas cfg)))
  (test-equal '(0 0 0 0) (canvas-margin (config-canvas cfg)))
  (test-equal "#ffffff" (canvas-background (config-canvas cfg)))
  (test-equal 'fit (cell-scale (car (config-cells cfg))))
  (test-equal 'center (cell-align-h (car (config-cells cfg))))
  (test-equal 'middle (cell-align-v (car (config-cells cfg))))
  (test-equal #f (config-row-labels cfg))
  (test-equal #f (config-column-labels cfg)))

;; gap and margin forms
(let ((cfg (parse-config
            '(image-merger
               (output "o.png")
               (canvas (grid 1 1) (cell-size 10 10)
                       (gap 8 4) (margin 1 2 3 4) (background "#000000"))
               (cell (row 0) (column 0) (image "a.png"))))))
  (test-equal 8 (canvas-gap-x (config-canvas cfg)))
  (test-equal 4 (canvas-gap-y (config-canvas cfg)))
  (test-equal '(1 2 3 4) (canvas-margin (config-canvas cfg)))
  (test-equal "#000000" (canvas-background (config-canvas cfg))))

;; scale modes and align
(let ((cfg (parse-config
            '(image-merger
               (output "o.png")
               (canvas (grid 1 3) (cell-size 10 10))
               (cell (row 0) (column 0) (image "a.png") (scale fill) (align right top))
               (cell (row 0) (column 1) (image "b.png") (scale stretch))
               (cell (row 0) (column 2) (image "c.png") (scale (exact 77 88)))))))
  (let ((cells (config-cells cfg)))
    (test-equal 'fill (cell-scale (car cells)))
    (test-equal 'right (cell-align-h (car cells)))
    (test-equal 'top (cell-align-v (car cells)))
    (test-equal 'stretch (cell-scale (cadr cells)))
    (test-equal 'exact (cell-scale (caddr cells)))
    (test-equal 77 (cell-exact-w (caddr cells)))
    (test-equal 88 (cell-exact-h (caddr cells)))))

;; labels
(let ((cfg (parse-config
            '(image-merger
               (output "o.png")
               (canvas (grid 2 2) (cell-size 10 10))
               (cell (row 0) (column 0) (image "a.png"))
               (row-labels (band 24) (start 1)
                           (style (font "F.ttf") (size 14) (color "#fff")
                                  (align right middle)))
               (column-labels (band 20)
                              (texts "A" "B"))))))
  (let ((rl (config-row-labels cfg)) (cl (config-column-labels cfg)))
    (test-assert rl)
    (test-equal 24 (labels-band rl))
    (test-equal 1 (labels-start rl))
    (test-equal "F.ttf" (style-font (labels-style rl)))
    (test-equal 14 (style-size (labels-style rl)))
    (test-equal 'right (style-align-h (labels-style rl)))
    (test-equal '("A" "B") (labels-texts cl))))

;; validation errors
(test-assert (expect-error (lambda () (parse-config '(not-image-merger)))))
(test-assert (expect-error (lambda ()
                             (parse-config '(image-merger (output "o.png"))))))
(test-assert (expect-error (lambda ()
                             (parse-config
                              '(image-merger
                                 (output "o.png")
                                 (canvas (grid 0 1) (cell-size 10 10)))))))
(test-assert (expect-error
              (lambda ()
                (parse-config
                 '(image-merger
                    (output "o.png")
                    (canvas (grid 1 1) (cell-size 10 10))
                    (cell (row 0) (column 0) (image "a.png")
                          (align up down)))))))

(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
