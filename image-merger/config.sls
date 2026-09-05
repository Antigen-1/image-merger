;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright (c) 2026 Guy Q. Schemer
;; SPDX-License-Identifier: MIT
#!r6rs
;; (image-merger config) — read and validate the s-exp configuration file.
;;
;; The configuration is a single s-expression:
;;
;;   (image-merger
;;     (output "out.png")
;;     (canvas (grid 3 4) (cell-size 160 120) (background "#202020")
;;             (margin 20) (gap 8 4))
;;     (cell (row 0) (column 0) (image "a.png") (scale fit) (align center middle))
;;     ...
;;     (row-labels (band 24) (start 1)
;;                 (style (font "F.ttf") (size 12) (color "#fff") (align right middle)))
;;     (column-labels (band 20)
;;                    (style (font "F.ttf") (size 12) (color "#fff") (align center bottom))
;;                    (texts "A" "B" "C" "D")))
(library (image-merger config)
  (export
    ;; config
    make-config config? config-output config-canvas config-cells
    config-row-labels config-column-labels
    ;; canvas
    make-canvas canvas? canvas-rows canvas-cols
    canvas-cell-width canvas-cell-height canvas-gap-x canvas-gap-y
    canvas-margin canvas-background
    ;; cell
    make-cell cell? cell-row cell-col cell-image
    cell-scale cell-align-h cell-align-v cell-exact-w cell-exact-h
    ;; labels
    make-labels labels? labels-band labels-start labels-texts labels-style
    ;; style
    make-style style? style-font style-size style-color style-align-h style-align-v
    ;; parsing
    parse-config read-config)
  (import (chezscheme))

  ;; ------------------------------------------------------------------
  ;; Records
  ;; ------------------------------------------------------------------
  (define-record-type config
    (fields output canvas cells row-labels column-labels))

  (define-record-type canvas
    (fields rows cols cell-width cell-height gap-x gap-y margin background))

  (define-record-type cell
    (fields row col image scale align-h align-v exact-w exact-h))

  (define-record-type labels
    (fields band start texts style))

  (define-record-type style
    (fields font size color align-h align-v))

  ;; ------------------------------------------------------------------
  ;; Small helpers
  ;; ------------------------------------------------------------------
  (define (fail who expected got)
    (errorf 'image-merger-config "~a: expected ~a, got ~s" who expected got))

  (define (nonneg? x) (and (integer? x) (exact? x) (>= x 0)))
  (define (pos? x) (and (integer? x) (exact? x) (>= x 1)))

  ;; (clause '(grid 3 4) 'grid) => '(3 4)  ; (clause ... other) => #f
  (define (clause form key)
    (let ((e (assq key (cdr form))))
      (and e (cdr e))))

  (define (require-clause form key who)
    (or (clause form key)
        (fail who (format "a (~a ...) clause" key) form)))

  ;; ------------------------------------------------------------------
  ;; Defaults
  ;; ------------------------------------------------------------------
  (define default-style
    (make-style #f 12 "#000000" 'center 'middle))

  ;; ------------------------------------------------------------------
  ;; Parsers
  ;; ------------------------------------------------------------------
  (define (parse-canvas form)
    (unless (and (list? form) (eq? (car form) 'canvas))
      (fail 'canvas "a (canvas ...) clause" form))
    (let* ((grid (require-clause form 'grid 'canvas))
           (cs (require-clause form 'cell-size 'canvas)))
      (unless (and (= (length grid) 2) (pos? (car grid)) (pos? (cadr grid)))
        (fail 'grid "(grid <rows>=1> <cols>=1>)" grid))
      (unless (and (= (length cs) 2) (pos? (car cs)) (pos? (cadr cs)))
        (fail 'cell-size "(cell-size <w>=1> <h>=1>)" cs))
      (let* ((gap (or (clause form 'gap) '(0)))
             (margin (or (clause form 'margin) '(0)))
             (background (or (clause form 'background) '("#ffffff"))))
        (unless (and (or (= (length gap) 1) (= (length gap) 2))
                     (andmap nonneg? gap))
          (fail 'gap "(gap <n>) or (gap <x> <y>)" gap))
        (unless (and (or (= (length margin) 1) (= (length margin) 4))
                     (andmap nonneg? margin))
          (fail 'margin "(margin <n>) or (margin <top> <right> <bottom> <left>)" margin))
        (unless (and (= (length background) 1) (string? (car background)))
          (fail 'background "(background <string>)" background))
        (make-canvas
          (car grid) (cadr grid)
          (car cs) (cadr cs)
          (if (= (length gap) 2) (car gap) (car gap))
          (if (= (length gap) 2) (cadr gap) (car gap))
          (if (= (length margin) 4)
              margin
              (make-list 4 (car margin)))
          (car background)))))

  (define valid-h-aligns '(left center right))
  (define valid-v-aligns '(top middle bottom))
  (define valid-scales '(fit fill stretch none exact))

  (define (parse-align form who)
    ;; form is the cdr of an (align ...) clause, e.g. (center middle)
    (unless (and (= (length form) 2)
                 (memq (car form) valid-h-aligns)
                 (memq (cadr form) valid-v-aligns))
      (fail 'align "(align <left|center|right> <top|middle|bottom>)" (cons 'align form)))
    (values (car form) (cadr form)))

  (define (parse-scale form)
    ;; form is the cdr of a (scale ...) clause, e.g. (fit) or ((exact 77 88))
    (cond
      ((and (= (length form) 1) (memq (car form) valid-scales))
       (values (car form) #f #f))
      ((and (= (length form) 1) (pair? (car form)) (eq? (caar form) 'exact))
       (let ((ex (car form)))
         (unless (and (= (length ex) 3) (pos? (cadr ex)) (pos? (caddr ex)))
           (fail 'scale "(scale (exact <w>=1> <h>=1>))" (cons 'scale form)))
         (values 'exact (cadr ex) (caddr ex))))
      (else
       (fail 'scale "(scale fit|fill|stretch|none|(exact <w> <h>))"
             (cons 'scale form)))))

  (define (parse-cell form)
    (unless (and (list? form) (eq? (car form) 'cell))
      (fail 'cell "a (cell ...) clause" form))
    (let* ((row (require-clause form 'row 'cell))
           (col (require-clause form 'column 'cell))
           (img (require-clause form 'image 'cell)))
      (unless (and (= (length row) 1) (nonneg? (car row)))
        (fail 'row "(row <i>=0>)" row))
      (unless (and (= (length col) 1) (nonneg? (car col)))
        (fail 'column "(column <j>=0>)" col))
      (unless (and (= (length img) 1) (string? (car img)))
        (fail 'image "(image <string>)" img))
      (let*-values (((scale ew eh) (parse-scale (or (clause form 'scale) '(fit))))
                    ((ah av) (parse-align (or (clause form 'align) '(center middle)) 'align)))
        (make-cell (car row) (car col) (car img) scale ah av ew eh))))

  (define (style-arg form key default)
    ;; form is a list of (key . args) sublists (the *args* of a style clause)
    (let ((e (assq key form)))
      (if e (cdr e) default)))

  (define (parse-style form)
    ;; form is the cdr of a (style ...) clause, or #f
    (if (not form)
        default-style
        (let* ((font (style-arg form 'font '(#f)))
               (size (style-arg form 'size '(12)))
               (color (style-arg form 'color '("#000000")))
               (align (style-arg form 'align '(center middle))))
          (unless (and (= (length font) 1) (or (string? (car font)) (not (car font))))
            (fail 'style "(font <string-or-#f>)" (cons 'style font)))
          (unless (and (= (length size) 1) (pos? (car size)))
            (fail 'style "(size <n>=1>)" (cons 'style size)))
          (unless (and (= (length color) 1) (string? (car color)))
            (fail 'style "(color <string>)" (cons 'style color)))
          (let-values (((ah av) (parse-align align 'style-align)))
            (make-style (car font) (car size) (car color) ah av)))))

  (define (parse-labels key form)
    ;; form is a (row-labels ...) / (column-labels ...) clause, or #f
    (if (not form)
        #f
        (begin
          (unless (and (pair? form) (eq? (car form) key))
            (fail key (format "a (~a ...) clause" key) form))
          (let* ((band (require-clause form 'band key))
                 (start (or (clause form 'start) '(0)))
                 (texts (clause form 'texts))
                 (style (parse-style (clause form 'style))))
            (unless (and (= (length band) 1) (pos? (car band)))
              (fail 'band "(band <n>=1>)" band))
            (unless (and (= (length start) 1) (nonneg? (car start)))
              (fail 'start "(start <n>=0>)" start))
            (when (and texts (not (andmap string? texts)))
              (fail 'texts "(texts <string> ...)" (cons 'texts texts)))
            (make-labels (car band) (car start) texts style)))))

  (define (parse-config datum)
    (unless (and (list? datum) (eq? (car datum) 'image-merger))
      (fail 'parse-config "an (image-merger ...) form" datum))
    (let* ((output (require-clause datum 'output 'image-merger))
           (canvas (or (assq 'canvas (cdr datum))
                       (fail 'parse-config "a (canvas ...) clause" datum))))
      (unless (and (= (length output) 1) (string? (car output)))
        (fail 'output "(output <string>)" output))
      (make-config
        (car output)
        (parse-canvas canvas)
        (map parse-cell (filter (lambda (x) (and (pair? x) (eq? (car x) 'cell))) (cdr datum)))
        (parse-labels 'row-labels (assq 'row-labels (cdr datum)))
        (parse-labels 'column-labels (assq 'column-labels (cdr datum))))))

  ;; Relative image/output paths are resolved against the directory of the
  ;; config file so that `image-merger examples/demo.cfg` works from any cwd.
  (define (absolute-path? p)
    (and (> (string-length p) 0) (char=? (string-ref p 0) #\/)))

  (define (dirname p)
    (let loop ((i (- (string-length p) 1)))
      (cond ((< i 0) ".")
            ((char=? (string-ref p i) #\/)
             (if (= i 0) "/" (substring p 0 i)))
            (else (loop (- i 1))))))

  (define (resolve-path base p)
    (if (absolute-path? p) p (string-append base "/" p)))

  (define (read-config path)
    (define base (dirname path))
    (define ip (open-input-file path))
    (define datum (read ip))
    (close-input-port ip)
    (let ((cfg (parse-config datum)))
      (make-config
        (resolve-path base (config-output cfg))
        (config-canvas cfg)
        (map (lambda (c)
               (make-cell (cell-row c) (cell-col c)
                          (resolve-path base (cell-image c))
                          (cell-scale c) (cell-align-h c) (cell-align-v c)
                          (cell-exact-w c) (cell-exact-h c)))
             (config-cells cfg))
        (config-row-labels cfg)
        (config-column-labels cfg)))))
