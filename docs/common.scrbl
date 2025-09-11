#lang scribble/base

@(require scribble/core scribble/html-properties scribble/manual)
@(provide miami-pink miami-cyan miami-cyan-italic logo-style title-with-css footer-style
          cyan-bold cyan-section cyan-item cyan-paragraph)

@(define miami-pink (make-style #f (list (attributes (list (cons 'style "color: #FF1493;"))))))
@(define miami-cyan (make-style #f (list (attributes (list (cons 'style "color: #00CED1;"))))))
@(define miami-cyan-italic (make-style #f (list (attributes (list (cons 'style "color: #00CED1; font-style: italic;"))))))
@(define logo-style (make-style #f (list (attributes (list (cons 'style "float: right; margin: 10px;"))))))
@(define title-with-css (make-style #f (list (attributes (list (cons 'style "color: #FF1493;"))) (make-css-addition "miami.css"))))
@(define footer-style (make-style #f (list (alt-tag "footer") (attributes (list (cons 'style "text-align: center; margin-top: 2rem; color: #00CED1; font-style: italic;"))))))

@; Helper functions for consistent cyan styling
@(define (cyan-bold . content)
   (elem #:style miami-cyan (bold content)))

@(define (cyan-section title)
   (section #:style miami-cyan title))

@(define (cyan-item . content)
   (item (elem #:style miami-cyan (bold content))))

@(define (cyan-paragraph . content)
   (paragraph #:style miami-cyan content))