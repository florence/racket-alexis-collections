#lang racket/base

;; This contains the implementation for derived sequence functions that have no need to access the
;; internal representation of the underlying interfaces.

(require
  alexis/collection/collection
  alexis/collection/countable
  alexis/collection/contract
  alexis/util/match
  racket/generic
  racket/contract)

(provide
 (contract-out
  [for-each (->i ([proc (seqs) (and/c (procedure-arity-includes/c (length seqs))
                                      (unconstrained-domain-> any/c))])
                 #:rest [seqs (non-empty-listof sequence?)]
                 [result void?])]
  [last ((and/c sequence? (not/c empty?)) . -> . any)]
  [take (exact-nonnegative-integer? sequence? . -> . sequence?)]
  [drop (exact-nonnegative-integer? sequence? . -> . sequence?)]
  [subsequence (->i ([seq sequence?]
                     [start exact-nonnegative-integer?]
                     [end (start) (and/c exact-nonnegative-integer? (>=/c start))])
                    [result sequence?])]
  [subsequence* (sequence? exact-nonnegative-integer? exact-nonnegative-integer? . -> . sequence?)]
  [sequence->string ((sequenceof char?) . -> . (and/c string? sequence?))]
  [sequence->bytes ((sequenceof byte?) . -> . (and/c bytes? sequence?))]))

; like map, but strict, returns void, and is only for side-effects
(define (for-each proc . seqs)
  (let ([seq (apply map proc seqs)])
    (for ([el (in seq)]) (void))))

; get the end of a finite sequence
(define (last seq)
  (if (and (countable? seq)
           (known-finite? seq))
      (nth seq (sub1 (length seq)))
      (let loop ([seq seq])
        (let ([next (rest seq)])
          (if (empty? next)
              (first seq)
              (loop next))))))

; wrapper for lazy sections of a sequence
(struct bounded-seq (source left)
  #:reflection-name 'lazy-sequence
  #:methods gen:countable
  [(define/match* (length (bounded-seq _ left)) left)
   (define (known-finite seq) #t)]
  #:methods gen:sequence
  [(define/generic -first first)
   (define/generic -rest rest)
   (define/generic -nth nth)
   (define/match* (empty? (bounded-seq _ left))
     (zero? left))
   (define/match* (first (bounded-seq source _))
     (-first source))
   (define/match* (rest (bounded-seq source left))
     (bounded-seq (-rest source) (sub1 left)))
   (define/match* (nth (bounded-seq source _) index)
     (-nth source index))
   ; reversing the sequence can't possibly be lazy, anyway, so just turn it into a list
   (define/match* (reverse seq)
     (extend '() seq))])

; lazily grabs the first n elements of seq
(define (take n seq)
  (when (and (countable? seq)
             (known-finite? seq)
             (> n (length seq)))
    (raise-range-error 'take "sequence" "length " n seq 0 (length seq)))
  (bounded-seq seq n))

; strictly drops the first n elements of seq
(define (drop n seq)
  (when (and (countable? seq)
             (known-finite? seq)
             (> n (length seq)))
    (raise-range-error 'drop "sequence" "length " n seq 0 (length seq)))
  (let loop ([n n]
             [seq seq])
    (if (zero? n)
        seq
        (loop (sub1 n) (rest seq)))))

; utility for composing take and drop
(define (subsequence seq start end)
  (when (and (countable? seq)
             (known-finite? seq))
    (when (> start (length seq))
      (raise-range-error 'subsequence "sequence" "start " start seq 0 (length seq)))
    (when (> end (length seq))
      (raise-range-error 'subsequence "sequence" "end " end seq 0 (length seq))))
  (take (- end start) (drop start seq)))

; like subsequence but specifying a length instead of an end index
(define (subsequence* seq start len)
  (when (and (countable? seq)
             (known-finite? seq))
    (when (> start (length seq))
      (raise-range-error 'subsequence* "sequence" "start " start seq 0 (length seq)))
    (when (> (+ start len) (length seq))
      (raise-range-error 'subsequence* "sequence" "end " (+ start len) seq 0 (length seq))))
  (take len (drop start seq)))

; some conversion functions for non-collections
(define (sequence->string seq)
  (string->immutable-string (list->string (sequence->list seq))))
(define (sequence->bytes seq)
  (bytes->immutable-bytes (list->bytes (sequence->list seq))))