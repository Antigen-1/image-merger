#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing)
        (image-merger config) (image-merger layout) (image-merger spec))

(test-begin "spec")

;; The contract must be flat positional data: no symbols, #f exact -> 0.
(let* ((cfg (parse-config
             '(image-merger
                (output "o.png")
                (canvas (grid 1 2) (cell-size 10 10))
                (cell (row 0) (column 0) (image "a.png") (scale fit) (align center middle))
                (cell (row 0) (column 1) (image "b.png") (scale (exact 30 40))))
             ))
       (lay (compute-layout cfg))
       (spec (layout->spec lay)))
  (test-equal "o.png" (car spec))
  (test-equal 20 (cadr spec))            ; width
  (test-equal 10 (caddr spec))           ; height
  (test-equal "#ffffff" (list-ref spec 3)) ; background
  (let ((items (list-ref spec 4)))
    (test-equal 2 (length items))
    ;; item: file x y w h mode align-h align-v ew eh
    (test-equal (list "a.png" 0 0 10 10 "fit" "center" "middle" 0 0)
                (car items))
    (test-equal (list "b.png" 10 0 10 10 "exact" "center" "middle" 30 40)
                (cadr items)))
  (test-equal '() (list-ref spec 5))
  (test-equal '() (list-ref spec 6)))

;; label fields include the #f font slot (for the default font)
(let* ((cfg (parse-config
             '(image-merger
                (output "o.png")
                (canvas (grid 1 1) (cell-size 10 10))
                (cell (row 0) (column 0) (image "a.png"))
                (row-labels (band 20)))))
       (spec (layout->spec (compute-layout cfg))))
  (let ((rl (list-ref spec 5)))
    (test-equal 1 (length rl))
    (test-equal (list "0" 0 0 20 10 "center" "middle" #f 12 "#000000")
                (car rl))))

(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
