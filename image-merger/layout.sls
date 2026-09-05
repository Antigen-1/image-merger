;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; (image-merger layout) — pure geometry: turn a validated config into a
;; concrete layout (canvas size, per-cell boxes, label boxes).
;;
;; The grid is regular: cells are laid out left-to-right, top-to-bottom with a
;; fixed cell size and a gap between cells.  Row labels occupy a band on the
;; left; column labels occupy a band on the top.  Cells that are not mentioned
;; in the config are simply left empty (the background shows through).
;;
;; An "item" is a 9-element list:
;;   (file x y w h mode align-h align-v exact-w exact-h)
;; where (x y w h) is the *cell* rectangle; the exact placement of the image
;; inside that rectangle (fit/fill/stretch/...) is done by the Python backend.
;;
;; A "label" is a 9-element list:
;;   (text x y w h align-h align-v font size color)
;; where (x y w h) is the box in which the text is anchored.
(library (image-merger layout)
  (export make-layout layout? layout-output layout-width layout-height
          layout-background layout-items layout-row-labels layout-column-labels
          compute-layout)
  (import (chezscheme) (image-merger config))

  (define-record-type layout
    (fields output width height background items row-labels column-labels))

  (define (label-text texts i start)
    (if (and texts (< i (length texts)))
        (list-ref texts i)
        (number->string (+ i start))))

  (define (row-labels->list rl rows ch gy origin-y left right)
    (if (not rl)
        '()
        (let ((start (labels-start rl))
              (texts (labels-texts rl))
              (st (labels-style rl)))
          (let loop ((i 0))
            (if (= i rows)
                '()
                (cons (list (label-text texts i start)
                            left
                            (+ origin-y (* i (+ ch gy)))
                            (- right left)
                            ch
                            (style-align-h st)
                            (style-align-v st)
                            (style-font st)
                            (style-size st)
                            (style-color st))
                      (loop (+ i 1))))))))

  (define (column-labels->list cl cols cw gx origin-x top bottom)
    (if (not cl)
        '()
        (let ((start (labels-start cl))
              (texts (labels-texts cl))
              (st (labels-style cl)))
          (let loop ((j 0))
            (if (= j cols)
                '()
                (cons (list (label-text texts j start)
                            (+ origin-x (* j (+ cw gx)))
                            top
                            cw
                            (- bottom top)
                            (style-align-h st)
                            (style-align-v st)
                            (style-font st)
                            (style-size st)
                            (style-color st))
                      (loop (+ j 1))))))))

  (define (compute-layout cfg)
    (let* ((canvas (config-canvas cfg))
           (rows (canvas-rows canvas))
           (cols (canvas-cols canvas))
           (cw (canvas-cell-width canvas))
           (ch (canvas-cell-height canvas))
           (gx (canvas-gap-x canvas))
           (gy (canvas-gap-y canvas))
           (margin (canvas-margin canvas))
           (rl (config-row-labels cfg))
           (cl (config-column-labels cfg))
           (rb (if rl (labels-band rl) 0))   ; row-label band width
           (cb (if cl (labels-band cl) 0))   ; column-label band height
           (m-top (list-ref margin 0))
           (m-right (list-ref margin 1))
           (m-bottom (list-ref margin 2))
           (m-left (list-ref margin 3))
           (origin-x (+ m-left rb))
           (origin-y (+ m-top cb))
           (content-w (+ (* cols cw) (* (- cols 1) gx)))
           (content-h (+ (* rows ch) (* (- rows 1) gy)))
           (width (+ m-left rb content-w m-right))
           (height (+ m-top cb content-h m-bottom)))
      (make-layout
        (config-output cfg)
        width height
        (canvas-background canvas)
        (map (lambda (c)
               (list (cell-image c)
                     (+ origin-x (* (cell-col c) (+ cw gx)))
                     (+ origin-y (* (cell-row c) (+ ch gy)))
                     cw ch
                     (cell-scale c)
                     (cell-align-h c)
                     (cell-align-v c)
                     (cell-exact-w c)
                     (cell-exact-h c)))
             (config-cells cfg))
        (row-labels->list rl rows ch gy origin-y m-left origin-x)
        (column-labels->list cl cols cw gx origin-x m-top origin-y)))))
