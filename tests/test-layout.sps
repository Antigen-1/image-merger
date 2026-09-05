#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs

(import (rnrs (6)) (srfi :64 testing)
        (image-merger config) (image-merger layout))

(test-begin "layout")

;; 2 rows x 3 cols, cell 100x50, gap 10 (uniform), no margin, no labels
(let* ((cfg (parse-config
             '(image-merger
                (output "o.png")
                (canvas (grid 2 3) (cell-size 100 50) (gap 10))
                (cell (row 0) (column 0) (image "a.png"))
                (cell (row 1) (column 2) (image "b.png")))))
       (lay (compute-layout cfg)))
  (test-equal (+ (* 3 100) (* 2 10)) (layout-width lay))   ; 320
  (test-equal (+ (* 2 50) (* 1 10)) (layout-height lay))   ; 110
  (test-equal 2 (length (layout-items lay)))
  ;; cell (0,0) -> (0,0); cell (1,2) -> x=2*110=220, y=1*60=60
  (test-equal '(0 0 100 50)
              (list (cadar (layout-items lay)) (caddar (layout-items lay))
                    (cadddr (car (layout-items lay))) (list-ref (car (layout-items lay)) 4)))
  (let ((it (cadr (layout-items lay))))
    (test-equal 220 (cadr it))
    (test-equal 60 (caddr it))
    (test-equal 100 (cadddr it))
    (test-equal 50 (list-ref it 4)))
  (test-equal '() (layout-row-labels lay))
  (test-equal '() (layout-column-labels lay)))

;; labels add bands to the canvas and produce anchored boxes
(let* ((cfg (parse-config
             '(image-merger
                (output "o.png")
                (canvas (grid 2 2) (cell-size 100 50) (gap 0) (margin 5))
                (cell (row 0) (column 0) (image "a.png"))
                (row-labels (band 20) (start 1))
                (column-labels (band 30)))))
       (lay (compute-layout cfg)))
  ;; content 2*100=200 wide, 2*50=100 high; + row band 20 + margins 5+5
  (test-equal (+ 5 20 200 5) (layout-width lay))    ; 230
  (test-equal (+ 5 30 100 5) (layout-height lay))   ; 140
  ;; two row labels "1" "2" and two column labels "0" "1"
  (test-equal 2 (length (layout-row-labels lay)))
  (test-equal 2 (length (layout-column-labels lay)))
  ;; first row label: text "1", box x=5 (margin-left), y=5+30=35, w=20, h=50
  (let ((rl (car (layout-row-labels lay))))
    (test-equal "1" (car rl))
    (test-equal 5 (cadr rl))
    (test-equal 35 (caddr rl))
    (test-equal 20 (cadddr rl))
    (test-equal 50 (list-ref rl 4)))
  ;; first column label: text "0", box x=5+20=25, y=5, w=100, h=30
  (let ((cl (car (layout-column-labels lay))))
    (test-equal "0" (car cl))
    (test-equal 25 (cadr cl))
    (test-equal 5 (caddr cl))
    (test-equal 100 (cadddr cl))
    (test-equal 30 (list-ref cl 4))))

;; empty cells are simply absent from items
(let* ((cfg (parse-config
             '(image-merger
                (output "o.png")
                (canvas (grid 1 3) (cell-size 10 10))
                (cell (row 0) (column 2) (image "only.png")))))
       (lay (compute-layout cfg)))
  (test-equal 1 (length (layout-items lay)))
  (test-equal 20 (cadar (layout-items lay)))) ; column 2 -> x=20

(test-end)

(exit (if (zero? (test-runner-fail-count (test-runner-get))) 0 1))
