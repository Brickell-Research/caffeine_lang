#lang scribble/manual

@(require "common.scrbl")

@title[#:style title-with-css]{Architecture}

@elem[#:style miami-cyan]{
 Caffeine is simple compiler with a three phase architecture:
}

@itemlist[#:style 'ordered
          @cyan-item{(1) Parsing and Static Analysis}
          @cyan-item{(2) Type Checking and Semantic Analysis}
          @cyan-item{(3) Code Generation}
          ]

@cyan-section{Parsing and Static Analysis}

@cyan-section{Type Checking and Semantic Analysis}

@cyan-section{Code Generation}
