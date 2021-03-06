#lang plai
(print-only-errors #t)

(define-type Binding
  [binding (name symbol?) (named-expr AE?)])

(define-type AE
  [num (n number?)]
  [binop (op procedure?)
         (lhs AE?)
         (rhs AE?)]
  [id (sym symbol?)]
  [if0 (cond-e AE?)
       (true-e AE?)
       (false-e AE?)]
  [app (fun AE?)
       (args (listof AE?))]
  [fun (params (listof symbol?))
       (body AE?)])

;; (define (with name named-thing body)
;;   (app (fun name body) named-thing))

(define (with lob body)
  (app (fun (map binding-name lob) body)
       (map binding-named-expr lob)))

;; (with ([x 5] [y 7])
;;       (+ x y))
;; =>
;; ((fun (x y)
;;       (+ x y))
;;  5
;;  7)

(define (add lhs rhs)
  (binop + lhs rhs))
(define (sub lhs rhs)
  (binop - lhs rhs))

;; <AE> := <real Racket number>
;;       | (+ <AE> <AE>)
;;       | (- <AE> <AE>)
;;       | (* <AE> <AE>)
;;       | (/ <AE> <AE>)
;;       | (if0 <AE> <AE> <AE>)
;;       | <id>
;;       | (with ([<id> <AE>] ...) <AE>)
;;       | (<AE> <AE> ...)
;;       | (fun (<id> ...) <AE>)

;; where <id> is any Racket symbol, except +, -, *, /, fun, if0, and with

(define (parse-binding se)
  (cond
    [(and (list? se)
          (= 2 (length se))
          (symbol? (first se)))
     (binding (first se)
              (parse (second se)))]
    [else
     (error 'parse "Invalid syntax, dude")]))

(define (safe-/ x y)
  (if (zero? y)
    (error 'calc "division by zero")
    (/ x y)))

;; parse :: s-expression -> AE
(define (parse se)
  (cond
    [(and (list? se)
          (= 3 (length se))
          (equal? 'fun (first se))
          (list? (second se))
          (andmap symbol? (second se)))
     (fun (second se)
          (parse (third se)))]
    [(and (list? se)
          (= 3 (length se))
          (equal? 'with (first se))
          (list? (second se)))
     (with (map parse-binding (second se))
           (parse (third se)))]
    [(symbol? se)
     (id se)]
    [(number? se)
     (num se)]
    [(and (list? se)
          (= 4 (length se))
          (equal? 'if0 (first se)))
     (if0 (parse (second se))
          (parse (third se))
          (parse (fourth se)))]
    [(and (list? se)
          (= 3 (length se))
          (equal? '+ (first se)))
     (add (parse (second se))
          (parse (third se)))]
    [(and (list? se)
          (= 3 (length se))
          (equal? '* (first se)))
     (binop *
            (parse (second se))
            (parse (third se)))]
    [(and (list? se)
          (= 3 (length se))
          (equal? '/ (first se)))
     (binop safe-/
            (parse (second se))
            (parse (third se)))]
    [(and (list? se)
          (= 3 (length se))
          (equal? '- (first se)))
     (sub (parse (second se))
          (parse (third se)))]
    [(and (list? se)
          (<= 1 (length se)))
     (app (parse (first se))
          (map parse (rest se)))]
    [else
     (error 'parse "Invalid syntax, dude: ~e" se)]))

(test (parse '1)
      (num 1))
(test (parse '(+ 1 1))
      (add (num 1) (num 1)))
(test (parse '(- 1 1))
      (sub (num 1) (num 1)))
(test (parse 'x)
      (id 'x))
(test (parse '(with ([x 27]) x))
      (with (list (binding 'x (num 27))) (id 'x)))
(test (parse '(double 5))
      (app (id 'double) (list (num 5))))
(test (parse '(fun (x) (+ x x)))
      (fun '(x) (add (id 'x) (id 'x))))

(test/exn (parse "1")
          "Invalid syntax")

(define-type Env
  [mtEnv]
  [consEnv
   (name symbol?)
   (named-value AEV?)
   (rest Env?)])

(define-type AEV
  [numV
   (n number?)]
  [closureV
   (params (listof symbol?))
   (body AE?)
   (env Env?)])

(define (lookup-id $ sym)
  (type-case
   Env $
   [mtEnv 
    ()
    (error 'calc "You has a bad identifier, bro: ~e" sym)]
   [consEnv
    (name named-value rest)
    (if (symbol=? name sym)
      named-value
      (lookup-id rest sym))]))

(define (foldr2 replace-cons replace-empty
                list1 list2)
  (cond
    [(and (empty? list1)
          (empty? list2))
     replace-empty]
    [(or (empty? list1)
         (empty? list2))
     (error 'calc "Mismatching")]
    [else
     (replace-cons
      (first list1)
      (first list2)
      (foldr2 replace-cons replace-empty
              (rest list1) (rest list2)))]))

(define (conssEnv names vals base-env)
  ;; (foldr2 consEnv
  ;;        base-env
  ;;        names
  ;;        vals)

  (foldr (λ (name*val base-env)
           (consEnv (first name*val)
                    (second name*val)
                    base-env))
         base-env
         (map list names vals))
)

;; (foldr f e (map g l ...))
;; =
;; (foldr (λ (x ... a) (f (g x ...) a)) e l ...)

;; (map mult8 (map add7 array))
;; =>
;; (map mult8&add7 array)

;; CUBLAS
;; C++ templates

;; for i = 0 ... 10 ; do
;;  array[i] += 7
;; done
;; .... nothing looks at array[0]
;; for j = 0 ... 10 ; do
;;  array[j] *= 8
;; done

;; ====> loop fusion ===>

;; for i = 0 ... 10 ; do
;;  array[i] += 7
;;  array[i] *= 8
;; done

;; ===> simplification ===>

;; for i = 0 ... 10 ; do
;;  array[i] = (array[i] + 7) * 8
;; done

;; ===>

;; for i = 0 ... 10 ; do // hand wave
;;  array[i+0] = (array[i+0] + 7) * 8
;;  array[i+1] = (array[i+1] + 7) * 8
;;  array[i+2] = (array[i+2] + 7) * 8
;;  array[i+3] = (array[i+3] + 7) * 8


;; calc : AE? Env? -> AEV?
;; compute the meaning of the AE
(define (calc ae $)
  (type-case
   AE ae
   [if0
    (cond-e true-e false-e)
    (if (zero? (numV-n* (calc cond-e $)))
      (calc true-e $)
      (calc false-e $))]
   [fun
    (param body)
    (closureV param body $)]
   [app
    (fun args)
    (type-case
     AEV (calc fun $)
     [closureV
      (arg-names fun-body fun-$)
      (calc fun-body 
            (conssEnv
             arg-names
             (map (λ (....) (calc .... $)) args)
             fun-$))]
     [else
      (error 'calc "Not a function, man")])]
   [id
    (sym)
    (lookup-id $ sym)]   
   [num
    (n)
    (numV n)]
   [binop
    (op lhs rhs)
    (numV
     (lift-numV
      op
      (calc lhs $)
      (calc rhs $)))]))

(define (lift-numV f . args)
  (apply f (map numV-n* args)))

(define (numV-n* a)
  (if (numV? a)
    (numV-n a)
    (error 'calc "Not a number: ~e" a)))

;; calc* : sexpr -> number?
(define (calc* se)
  (define res (calc (parse se) (mtEnv)))
  (type-case 
   AEV res
   [numV (n) n]
   [else res]))

(test (calc* '1)
      1)
(test (calc* '(+ 1 1))
      2)
(test (calc* '(- 0 1))
      -1)

(test (calc* '(with ([x (+ 5 5)])
                    (+ x x)))
      20)
(test (calc* '(with ([y 7])
                    (with ([x y])
                          (+ x x))))
      14)
(test (calc* '(with 
               ([x (+ 5 5)])
               (with ([x 7])
                     (+ x x))))
      14)
(test (calc* '(with ([x (+ 5 5)])
                    (+ x (with ([x 7])
                               (+ x x)))))
      24)
(test (calc* '(with ([x (+ 5 5)])
                    (+ (with ([x 7])
                               (+ x x))
                       x)))
      24)
(test (calc* '(with
               ([x (+ 5 5)])
               (+ (with ([x 7])
                        (+ x x))
                  (with ([x 8])
                        (+ x x)))))
      (+ 14 16))
(test (calc* '(with ([x 7])
                    (with ([y (+ 2 x)])
                          (+ y 3))))
      12)
(test (calc* '(with ([y 7])
                    (with ([y (+ y 2)])
                          (+ y 3))))
      12)
(test (calc* '(with ([x (+ 5 5)])
                    7))
      7)

(test (calc* '(with ([x (+ 5 5)])
                    (+ x x)))
      20)
(test (calc* '(with ([x (+ 5 6)])
                    (+ x x)))
      22)

(test (calc* '(with ([x 5])
                     (with ([y 5])
                           (+ (+ x x) y))))
      15)

(test (calc* '(with ([x 5])
                     (with ([x (+ 1 x)])
                           (+ (+ x x) x))))
      18)

(test/exn (calc* '(with ([x 5])
                     (with ([x (+ 1 x)])
                           (+ (+ x x) y))))
          "bro")

(test/exn (calc* '(with ([x x])
                        5))
          "bro")


(test (calc* '(fun (x) (+ x x)))
      (closureV '(x) (add (id 'x) (id 'x)) (mtEnv)))

(test (calc* '(+ 1 (+ 2 3)))
      6)

(test/exn (calc* '(+ 1 (fun (x) x)))
          "Not a number")

(test/exn (calc* '(5 1))
          "Not a function")

(test (calc* '(with ([double (fun (x) (+ x x))])
                    (double 5)))
      10)

(test (calc* '(with ([double (fun (x) (+ x x))])
                    (with ([triple (fun (x) (+ x (double x)))])
                          (triple 5))))
      15)


(test (calc* '(with ([double (fun (x) (+ x x))])
                    (with ([triple (fun (x) (+ x (double x)))])
                          (with ([double (fun (x) (- x 6))])
                                (triple 5)))))
      15)

(test (calc* '(if0 0 1 2))
      1)
(test (calc* '(if0 -1 1 2))
      2)

(test (calc* '(* 1 2))
      2)
(test (calc* '(/ 1 2))
      1/2)
(test/exn (calc* '(/ 1 0))
          "division by zero")
