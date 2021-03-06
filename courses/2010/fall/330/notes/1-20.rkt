#lang plai
(halt-on-errors #t)

(define-type VBCFAE
  [num (n number?)]
  [binop (op procedure?)
         (lhs VBCFAE?)
         (rhs VBCFAE?)]
  [id (name symbol?)]
  [fun (param symbol?)
       (body VBCFAE?)]
  [refun (param symbol?)
       (body VBCFAE?)]
  [app (fun-expr VBCFAE?)
       (arg-expr VBCFAE?)]
  [if0 (test-expr VBCFAE?)
       (true-expr VBCFAE?)
       (false-expr VBCFAE?)]
  [newbox (init-expr VBCFAE?)]
  [openbox (box-expr VBCFAE?)]
  [setbox (box-expr VBCFAE?)
          (val-expr VBCFAE?)]
  [seqn (first-expr VBCFAE?)
        (second-expr VBCFAE?)]
  [setvar (var symbol?)
          (val-expr VBCFAE?)])

(define (with name named-expr body-expr)
  (app (fun name body-expr) named-expr))

; <VBCFAE> :== <number>
;      |   (+ <VBCFAE> <VBCFAE>)
;      |   (- <VBCFAE> <VBCFAE>)
;      |   <id>
;      |   (with [<id> <VBCFAE>] <VBCFAE>)
;      |   (fun (<id>) <VBCFAE>)
;      |   (refun (<id>) <VBCFAE>)
;      |   (<VBCFAE> <VBCFAE>)
;      |   (if0 <VBCFAE> <VBCFAE> <VBCFAE>)
;      |   (newbox <VBCFAE>)
;      |   (openbox <VBCFAE>)
;      |   (setbox <VBCFAE> <VBCFAE>)
;      |   (seqn <VBCFAE> <VBCFAE>)
;      |   (setvar <id> <VBCFAE>)
; where <id> is symbol

; parse: Sexpr -> VBCFAE
; Purpose: Parse an Sexpr into an VBCFAE
(define parse
  (match-lambda
    [(? number? n) (num n)]
    [(? symbol? name) (id name)]
    [`(openbox ,e) (openbox (parse e))]
    [`(newbox ,e) (newbox (parse e))]
    [`(setbox ,b ,e) (setbox (parse b) (parse e))]
    [`(setvar ,(? symbol? id) ,e) (setvar id (parse e))]
    [`(seqn ,b ,e) (seqn (parse b) (parse e))]
    [`(with [,(? symbol? name) ,named-expr] ,body-expr)
     (with name (parse named-expr) (parse body-expr))]
    [`(+ ,lhs ,rhs) (binop + (parse lhs) (parse rhs))]
    [`(- ,lhs ,rhs) (binop - (parse lhs) (parse rhs))]
    [`(* ,lhs ,rhs) (binop * (parse lhs) (parse rhs))]
    [`(/ ,lhs ,rhs) (binop (λ (x y) 
                             (if (zero? y) (error 'interp "Divide by zero")
                                 (/ x y)))
                           (parse lhs) (parse rhs))]
    [`(fun (,(? symbol? param)) ,body) (fun param (parse body))]
    [`(refun (,(? symbol? param)) ,body) (refun param (parse body))]
    [`(if0 ,test ,true ,false) (if0 (parse test) (parse true) (parse false))]
    [`(,fun ,arg) (app (parse fun) (parse arg))]))

(test (parse '(if0 0 1 2))
      (if0 (num 0) (num 1) (num 2)))

(test (parse '(f 1))
      (app (id 'f) (num 1)))
(test (parse '(fun (x) x))
      (fun 'x (id 'x)))

(test (parse '(+ 1 1))
      (binop + (num 1) (num 1)))
(test (parse '(- 1 2))
      (binop - (num 1) (num 2)))
(test (parse '(with [x 5] (+ x x)))
      (app (fun 'x (binop + (id 'x) (id 'x)))
           (num 5)))

(define-type VBCFAE-Value
  [numV (n number?)]
  [closureV (param symbol?)
            (body VBCFAE?)
            (env Env?)]
  [reclosureV (param symbol?)
              (body VBCFAE?)
              (env Env?)]
  [boxV (addr number?)])

; An env is a mapping from symbol to addresses
(define-type Env
  [mtEnv] ; mt is "em" "tee"
  [anEnv (name symbol?)
         (addr number?)
         (rest Env?)])

; A store is a mapping from address/numbers to value
(define-type Store
  [mtStore] ; mt is "em" "tee"
  [aStore (addr number?)
          (value VBCFAE-Value?)
          (rest Store?)])

(define env-ex0
  (mtEnv))
(define env-ex1
  (anEnv 'x 1
         (mtEnv)))
(define env-ex2
  (anEnv 'y 2
         env-ex1))

; lookup-Env : symbol Env -> number/#f
(define (lookup-Env name env)
  (type-case Env env
    [mtEnv ()
           #f]
    [anEnv (some-name some-addr rest-env)
           (if (symbol=? name
                         some-name)
               some-addr
               (lookup-Env name rest-env))]))

(test (lookup-Env 'x (mtEnv)) #f)
(test (lookup-Env 'x 
                  (anEnv 'x 1
                         (mtEnv))) 
      1)
(test (lookup-Env 'x 
                  (anEnv 'y 2
                         (anEnv 'x 1
                                (mtEnv)))) 
      1)
(test (lookup-Env 'x 
                  (anEnv 'x 2
                         (anEnv 'x 1
                                (mtEnv)))) 
      2)

; lookup-Store : addr Store -> number/#f
(define (lookup-Store addr store)
  (type-case Store store
    [mtStore ()
           #f]
    [aStore (some-addr some-value rest-store)
           (if (= addr some-addr)
               some-value
               (lookup-Store addr rest-store))]))

(test (lookup-Store 1 (mtStore)) #f)
(test (lookup-Store 1
                    (aStore 1 (numV 1)
                            (mtStore))) 
      (numV 1))
(test (lookup-Store 1
                    (aStore 2 (numV 2)
                            (aStore 1 (numV 1)
                                    (mtStore)))) 
      (numV 1))
(test (lookup-Store 2 
                    (aStore 2 (numV 2)
                            (aStore 1 (numV 1)
                                    (mtStore)))) 
      (numV 2))

; max-addr : Store -> addr
(define (max-addr st)
  (type-case Store st
    [mtStore () -1]
    [aStore (some-addr some-val some-st)
            (max some-addr (max-addr some-st))]))
; malloc : Store -> addr
(define (malloc st)
  (add1 (max-addr st)))

; interp : VBCFAE Env Store -> VBCFAE-Value Store
; Purpose: To compute the number represented by the VBCFAE
(define (interp e env store)
  (type-case VBCFAE e
    [num (n) 
         (values (numV n) store)]
    [binop (op lhs rhs) 
           (local [(define-values (lhs-bv lhs-store)
                     (interp lhs env store))]
             (type-case VBCFAE-Value lhs-bv
               [numV (lhs-v)
                     (local [(define-values (rhs-bv rhs-store)
                               (interp rhs env lhs-store))]
                       (type-case VBCFAE-Value rhs-bv
                         [numV (rhs-v)
                               (values (numV (op lhs-v rhs-v)) rhs-store)]
                         [else
                          (error 'interp "Not a number [rhs]")]))]
               [else
                (error 'interp "Not a number [lhs]")]))]
    [if0 (test-e true-e false-e)
         (local [(define-values (test-bv test-store)
                   (interp test-e env store))]
           (type-case VBCFAE-Value test-bv
             [numV (test-v)
                   (if (zero? test-v)
                       (interp true-e env store)
                       (interp false-e env store))]
             [else 
              (error 'interp "Not a number")]))]
    [id (name)
        (local [(define names-addr (lookup-Env name env))]
          (if names-addr
              (local [(define names-value (lookup-Store names-addr store))]
                (if names-value
                    (values names-value store)
                    (error 'interp "SEGFAULT ~e" names-addr)))
              (error 'interp "Unbound identifier: ~e" name)))]
    [fun (param body)
         (values (closureV param body env) store)]
    [refun (param body)
           (values (reclosureV param body env) store)]
    [app (fun-expr arg-expr)
         (local [(define-values (the-fundef fun-store) 
                   (interp fun-expr env store))]
           (type-case VBCFAE-Value the-fundef
             [closureV (param-name body-expr funs-env)
                       (local [(define-values (arg-v arg-store)
                                 (interp arg-expr env fun-store))
                               (define param-addr (malloc arg-store))]
                         (interp body-expr
                                 (anEnv param-name
                                        param-addr
                                        funs-env)
                                 (aStore param-addr
                                         arg-v
                                         arg-store)))]
             [reclosureV (param-name body-expr funs-env)
                         (type-case VBCFAE arg-expr
                           [id (arg-name)
                               (local [(define arg-addr 
                                         (lookup-Env arg-name env))]
                                 (interp body-expr
                                         (anEnv param-name
                                                arg-addr
                                                funs-env)
                                         fun-store))]
                           [else
                            (error 'interp "Not an lvalue: ~e" arg-expr)])]
             [else
              (error 'interp "Not a function")]))]
    [newbox (initial-expr)
            (local [(define-values (initial-val after-initial-store)
                      (interp initial-expr env store))
                    (define new-addr (malloc after-initial-store))]
              (values (boxV new-addr)
                      (aStore new-addr initial-val
                              after-initial-store)))]
    [openbox (box-expr)
             (local [(define-values (box-v box-store)
                       (interp box-expr env store))]
               (type-case VBCFAE-Value box-v
                 [boxV (addr)
                       (values (lookup-Store addr box-store)
                               box-store)]
                 [else
                  (error 'interp "Not a box")]))]
    [setbox (box-expr val-expr)
            (local [(define-values (box-v box-store)
                      (interp box-expr env store))]
              (type-case VBCFAE-Value box-v
                [boxV (addr)
                      (local [(define-values (val-v val-store)
                                (interp val-expr env box-store))]
                        (values val-v
                                (aStore addr val-v
                                        val-store)))]
                [else
                 (error 'interp "Not a box")]))]
    [seqn (1st-expr 2nd-expr)
          (local [(define-values (1st-v 1st-store)
                    (interp 1st-expr env store))]
            (interp 2nd-expr env 1st-store))]
    [setvar (lvalue val-expr)
            (local [(define lvalue-addr (lookup-Env lvalue env))]
              (if lvalue-addr
                  (local [(define-values (val-v val-store)
                            (interp val-expr env store))]
                    (values val-v
                            (aStore lvalue-addr val-v
                                    val-store)))
                  (error 'interp "Unbound identifier: ~e" lvalue)))]))

; calc : VBCFAE -> number
(define (calc e)
  (define-values (v final-store) (interp e (mtEnv) (mtStore)))
  (type-case VBCFAE-Value v
    [numV (n)
          n]
    [else
     v]))

(test/exn (calc (parse 'x))
          "Unbound identifier")
(test (calc (parse '0))
      0)
(test (calc (parse '(+ 1 1)))
      2)
(test (calc (parse '(- 2 1)))
      1)
(test (calc (parse (list '- 2 1)))
      1)
(test (calc (parse (list '- 2 (list '- 2 1))))
      1)
(test (calc (parse '(- (+ 1 2) (- 8 9))))
      4)
(test (calc (parse '(with [x 5] (+ x x))))
      10)
(test (calc (parse '(with [x (+ 5 6)] (+ x x))))
      22)

(test (calc (parse '(with [x (+ 5 6)] (+ x x))))
      (calc (parse '(with [x 11] (+ x x)))))
(test (calc (parse '(with [x (+ 5 6)] (+ x x))))
      (calc (parse '(+ (+ 5 6)
                       (+ 5 6)))))
(test (calc (parse '(with [x (+ 5 6)] (+ x x))))
      (calc (parse '(+ 11 11))))

(test (calc (parse '(with [x (+ 5 6)]
                      (with [y (+ x 1)]
                        (+ x y)))))
      23)
(test (calc (parse '(with [x (+ 5 6)]
                      (with [x (+ x 1)]
                        (+ x x)))))
      24)

(test/exn (calc (parse '(double 5)))
          "Unbound identifier")
(test/exn (calc (parse '(with (double 1)
                          (double 5))))
          "Not a function")
(test (calc (parse '(with (double 
                           (fun (x)
                                (+ x x)))
                      (double 5))))
      10)
(test (calc (parse '((fun (x) (+ x x)) 5)))
      10)

(test (calc (parse '(with (x 1)
                      (with (y 2)
                        (with (z 3)
                          (+ x (+ y z)))))))
      6)

(test (calc (parse '(with [x 1]
                      (with [f (fun (y)
                                    (+ x y))]
                        (f 10)))))
      ; Sam
      11
      ; Joseph says with can't find fun defs
      #;"Unbound identifier")
(test/exn (calc (parse '(with [f (fun (y)
                                      (+ x y))]
                          (with [x 1]
                            (f 10)))))
          "Unbound identifier")

(test (calc (parse '(with [x 10]
                      (with [add10
                             (fun (y)
                                  (+ x y))]
                        (add10 5)))))
      15)
(test (calc (parse '(with [add10
                           (with [x 10]
                             (fun (y)
                                  (+ x y)))]
                      (add10 5))))
      15)
(test (calc (parse '((with [x 4] (fun (y) (+ x y))) 5)))
      9)
(test (calc (parse '(with [make-adder
                           (fun (x)
                                (fun (y)
                                     (+ x y)))]
                      (with [add10
                             (make-adder 10)]
                        (add10 5)))))
      15)
(test (calc (parse '(with [make-adder
                           (fun (x)
                                (fun (y)
                                     (+ x y)))]
                      (with [add10
                             (make-adder 10)]
                        (+ (add10 5)
                           (add10 6))))))
      31)
(test (calc (parse '(with [fake-adder
                           (fun (x)
                                (fun (y)
                                     (+ x x)))]
                      (with [add10
                             (fake-adder 10)]
                        (add10 5)))))
      20)
(test (calc (parse '(with [fake-adder
                           (fun (x)
                                (fun (y)
                                     (+ y y)))]
                      (with [add10
                             (fake-adder 10)]
                        (add10 5)))))
      10)

(test (calc (parse '(if0 0 1 2)))
      1)
(test (calc (parse '(if0 1 1 2)))
      2)
(test (calc (parse '(with [x 0]
                      (if0 x 1 2))))
      1)

(test/exn (calc (parse '(with [x (0 1)]
                          42)))
          ; If we are eager...
          "Not a function"
          ; If we are lazy...
          #;42)

(test (calc (parse '(with [x 5] x)))
      5)

(test (calc (parse '(with [double (fun (x) (+ x x))]
                      (with [not-double/jk double]
                        (not-double/jk 5)))))
      10)
(test (calc (parse '(with [x 5]
                      (with [y x]
                        (+ y y)))))
      10)

(test/exn (calc (parse '(with [add-fac
                               (fun (x)
                                    (if0 x
                                         x
                                         (+ x (add-fac (- x 1)))))]
                          (add-fac 7))))
          "Unbound identifier")

; MakeEnv 'with 'bound-expr env = env
; MakeEnv 'with 'bound-body env = (anEnv bound-id bound-value env)

(test (calc (parse '(with [x 1] x)))
      1)

(test (calc (parse '(with [y 1]
                      (with [x y]
                        x))))
      1)

(test (calc (parse '(with [x 1]
                      (with [x x]
                        x))))
      1)

#;(test (calc (parse '(with [omega (fun (x) (x x))]
                        (with [Omega (omega omega)]
                          42))))
        51)


; λf. (λx. f (λy. x x y)) (λx. f (λy. x x y))
 
(test (calc (parse '(with [Y 
                           (fun (f)
                                ((fun (x) (f (fun (y) ((x x) y))))
                                 (fun (x) (f (fun (y) ((x x) y))))))]
                      (with [make-add-fac
                             (fun (add-fac)
                                  (fun (x)
                                       (if0 x
                                            x
                                            (+ x (add-fac (- x 1))))))]
                        (with [add-fac (Y make-add-fac)
                               #;(make-add-fac add-fac)]
                          (add-fac 7))))))
      (+ 7 6 5 4 3 2 1 0))


;;-----

#| Is windowing/gui programming inherently stateful?

; show-the-window : (event -> void) -> doesnt' return 
(show-the-window on-click-function)

; show-the-window : initial-state (state event -> state)
(show-the-window 0 +)

(define (show-the-window initial f)
  (define event (get-the-next-event))
  (show-the-window (f initial event) f))
|#

; Box examples

(test (calc (parse '(openbox (newbox 42))))
      42)
(test (calc (parse '(with [x (newbox 42)]
                      (openbox x))))
      42)
(test (calc (parse '(with [x (newbox 42)]
                      (+ (openbox x)
                         (openbox x)))))
      84)
(test (calc (parse '(with [x (newbox 42)]
                      (setbox x 43))))
      43)
(test (calc (parse '(with [x (newbox 42)]
                      (seqn (setbox x 43)
                            (openbox x)))))
      43)
; We're not like C, evaluate the left first
(test (calc (parse '(with [x (newbox 42)]
                      (+ (openbox x)
                         (seqn (setbox x 43)
                               (openbox x))))))
      (+ 42 43))
(test (calc (parse '(with [x (newbox 42)]
                      (+ (seqn (setbox x 43)
                               (openbox x))
                         (openbox x)))))
      (+ 43 43))
(test (calc (parse '(with [x (newbox 42)]
                      (with [f (fun (y) (openbox x))]
                        (f 1)))))
      42)
; Closures do not "close" or "capture" the values of boxes
(test (calc (parse '(with [x (newbox 42)]
                      (with [f (fun (y) (openbox x))]
                        (seqn (setbox x 43)
                              (f 1))))))
      43)
(test (calc (parse '(with [x (newbox 42)]
                      (with [z (newbox 1)]
                        (with [f (fun (y) (openbox z))]
                          (seqn (setbox z x)
                                (openbox (f 1))))))))
      42)
(test/exn (calc (parse '(openbox 42)))
          "Not a box")
(test/exn (calc (parse '(setbox 42 43)))
          "Not a box")
(test (calc (parse '(seqn 1 2)))
      2)

(test (calc (parse '(with [b (newbox 1)]
                      (with [c (newbox (seqn (setbox b 2)
                                             3))]
                        (openbox b)))))
      2)
(test (calc (parse '(with [b (newbox 1)]
                      (openbox (seqn (setbox b 2) b)))))
      2)

; x = 0
; f(++x, ++x)
; ->
; f(2, 1)
; NOT
; f(1, 2)

(test/exn (calc (parse '(setvar x 1)))
          "Unbound identifier")

(test (calc (parse '(with [x 0]
                      (setvar x 1))))
      1)
(test (calc (parse '(with [x 0]
                      (seqn (setvar x 1)
                            x))))
      1)
(test (calc (parse '(with [x 0]
                      (+ (with [x 0]
                           (seqn (setvar x 1)
                                 x))
                         x))))
      1)
(test (calc (parse '(with [f (fun (x)
                                  (+ x (seqn (setvar x 2)
                                             x)))]
                      (f 5))))
      7)
(test (calc (parse '(with [global 0]
                      (with [f (fun (x)
                                    (seqn (setvar global (+ global x))
                                          (+ x (seqn (setvar x 2)
                                                     x))))]
                        (seqn 
                         (seqn (f 5)
                               (f 10))
                         global)))))
      15)
(test (calc (parse '(with [outside 0]
                      (with [f (fun (inside)
                                    (seqn (setvar inside 25)
                                          42))]
                        (seqn (f outside)
                              outside)))))
      ; Votes... should / will
      0 ; 6 / 1 - f couldn't change outside
      #;25 ; 0 / 3 - f could
      )

(test (calc (parse '(with [outside 0]
                      (with [f (refun (inside)
                                      (seqn (setvar inside 25)
                                            42))]
                        (seqn (f outside)
                              outside)))))
      ; Votes... should / will
      #;0 ; 6 / 1 - f couldn't change outside
      25 ; 0 / 3 - f could
      )

(test/exn (calc (parse '((refun (x) x) 5)))
          "Not an lvalue")

(test (calc (parse '(with [swap
                           (refun (fst)
                                  (refun (snd)
                                         (with [tmp fst]
                                           (seqn (setvar fst snd)
                                                 (setvar snd tmp)))))]
                      (with [x 0]
                        (with [y 1]
                          (seqn ((swap x) y)
                                (/ y x)))))))
      0)
(test/exn (calc (parse '(with [swap
                               (fun (fst)
                                    (fun (snd)
                                         (with [tmp fst]
                                           (seqn (setvar fst snd)
                                                 (setvar snd tmp)))))]
                          (with [x 0]
                            (with [y 1]
                              (seqn ((swap x) y)
                                    (/ y x)))))))
          "Divide by zero")

(local [(define x 0)
        (define f +)]
  (test x 0)
  (set! x 1)
  (test x 1)
  
  (test (f 2 3) 5)
  (set! f *)
  (test (f 2 3) 6))
