#import "template.typ": notes

#import "typst-cd/typst-cd.typ": node, arr, commutative_diagram

#import "oc.typ": Carrier, Lattice, FL, rel, meet, join, instr, skip, succ, pred, Spec, Func, fw, bw, Const, Id, Vars, Consts, Terms, Ops, Eval, path, Paths, CM, BCM, LCM, SpCM, Insert, Repl, Comp, Transp, Safe, Correct, Available, VeryBusy, Earliest

#show: notes.with(
  title: "Optimizing Compiler Notes",
  authors: (
    "Clemens Koza, 01126573",
  ),
)

= The DFA framework

In the general data flow analysis framework, a DFA problem on an edge-labelled flow graph $G$ is formulated through a lattice with corresponding local semantics and some additional meta-information. The lattice is formed in some _carrier set_, $Carrier$:

$
Spec_G
  &= (Lattice(Carrier), Func(), c_s , d) \

"where"
Lattice(Carrier) &= (Carrier, rel, meet, join, bot, top) \

Func() &: E -> Carrier -> Carrier \

c_s &in Carrier \

d &in {fw, bw}
$

$Func()$ is the DFA functional that returns for each edge a function defining the semantics of that edge. For example, if $instr_e = skip$, then $Func(e: e) = Id_Carrier = lambda c. c$. For other instructions, the semantics will vary by DFA specification. Whether the DFA functional is (for each edge) only monotonic or also distributive determines whether the MaxFP solution will only approximate or even coincide with the MOP solution.

$d$ is the direction of the problem, and $c_s$ is the initial information at the start/end node, depending on the direction.

= Gen/Kill analysis specification

#[
#let pointwise = $italic("pw")$

Gen/kill or bitvector analyses store a single bit of information for each node of the control flow graph, i.e. $Carrier := BB$. The term _bitvector_ analysis reflects that $n$ such analyses (e.g. the availability of $n$ expressions) can be carried out efficiently at the same time by combining boolean values into a bitvector, resulting in $Carrier := BB^n$. When doing so, the relevant connectives (e.g. $lt.eq$, $and$) are adapted to point-wise application (e.g. $lt.eq_pointwise$, $and_pointwise$). These two formulations are ultimately equivalent.
]

Depending on the quantification of the problem, the boolean lattice or its inverse is used:

$
Lattice(BB) :=
  & (BB, and, or, lt.eq, "false", "true")
  &quad& #[for universally quantified problems] \

Lattice(BB_or) :=
  & (BB, or, and, gt.eq, "true", "false")
  && #[for existentially quantified problems]
$

#align(center)[
  #grid(
    columns: 2,
    gutter: 4em,

    figure(
      caption: [Hasse diagram of $Lattice(BB)$],
      numbering: none,
    )[
      #commutative_diagram(
        node_padding: (20pt, 20pt),
        arr_clearance: 0.5em,
        node((0, 0), [$t$]),
        node((1, 0), [$f$]),
        arr((1, 0), (0, 0), []),
      )
    ],
    figure(
      caption: [Hasse diagram of $Lattice(BB_or)$],
      numbering: none,
    )[
      #commutative_diagram(
        node_padding: (20pt, 20pt),
        arr_clearance: 0.5em,
        node((0, 0), [$f$]),
        node((1, 0), [$t$]),
        arr((1, 0), (0, 0), []),
      )
    ],
  )
]

The DFA functional and direction depend on the specific analysis. In the DFA functionals, we will refer to some basic boolean functions:

$
Const_"true"
  &= lambda b. "true" \

Const_"false"
  &= lambda b. "false" \

Id_BB
  &= lambda b. b
$

== Reaching definitions

A defintion of some variable $v$ is an assignment to that variable at a specific edge $accent(e, hat)$. The reach of a definition flows forward in the flow graph, until another definition shadows it.

$
Spec_G
  & = (Lattice(BB_or), Func(), b_s, fw) \

"where" Func(e: e) &= cases(
  Const_"true"
    &quad& #[if $e = accent(e, hat)$, i.e. this is the site of the definition],
  Const_"false"
    && #[if $instr_e$ redefines $v$],
  Id_BB
    && #[otherwise],
)
$

== Available Expressions

An expression becomes available when it is computed and stops being available when a variable appearing in it is redefined. This is again a forward analysis. An expression needs to be available on all paths to be available at a node.

$
Spec_G
  & = (Lattice(BB), Func(), b_s, fw) \

"where" Func(e: e) &= cases(
  Const_"false"
    &quad& #[if $instr_e$ redefines a variable appearing in the expression],
  Const_"true"
    && #[if $instr_e$ computes the expression],
  Id_BB
    && #[otherwise],
)
$

== Live variables

A variable $v$ is live at a node if it is later used on some paths before being redefined. The information flows backwards from the use sites, until a definition site is encountered.

$
Spec_G
  & = (Lattice(BB_or), Func(), b_e, bw) \

"where" Func(e: e) &= cases(
  Const_"true"
    &quad& #[if $instr_e$ reads/uses $v$],
  Const_"false"
    && #[if $instr_e$ redefines $v$],
  Id_BB
    && #[otherwise],
)
$

== Very busy expressions

An expression is very busy at a node if, no matter what path is taken from the node, the expression is always used before any of the variables occurring in it is redefined. The information flows backwards from the use sites, until a definition site of one of the variables in the expression is encountered.

$
Spec_G
  & = (Lattice(BB), Func(), b_e, bw) \

"where" Func(e: e) &= cases(
  Const_"true"
    &quad& #[if $instr_e$ computes/uses the expression],
  Const_"false"
    && #[if $instr_e$ redefines a variable appearing in the expression],
  Id_BB
    && #[otherwise],
)
$

#pagebreak(weak: true)

= Constant propagation

We now want to know whether a variable (or term) has, at some node, a known constant value. Both the variable and term version are undecidable, so we need conservative approximations.

Let's consider a few examples of pseudocode. In each example, we are interested in whether the printed variable is constant:

#align(center)[
  #grid(
    columns: 5,
    gutter: 1.5em,

    block(width: 2.5cm)[
      ```py
      a = 0
      b = a
      print(b)
      ```
    ],

    block(width: 2.5cm)[
      ```py
      a = 0
      b = a + 1
      print(b)
      ```
    ],

    block(width: 2.5cm)[
      ```py
      if p: a = 0
      else: a = 0
      print(a)
      ```
    ],

    block(width: 2.5cm)[
      ```py
      if p: a = 0
      else: return
      print(a)
      ```
    ],

    block(width: 2.5cm)[
      ```py
      b = a * 0
      print(b)
      ```
    ],
  )
]

In the first example, `a` is constant and `b` is assigned this variable's value. Naturally, we want an analysis that recognizes that `b` has the constant value zero. In the second example, we are dealing with an arithmetic expression that contains only constant operands. Again, it is desirable to recognize `b` always has value one.

The third and fourth example demonstrates how joining control flow needs to be considered: as variable `a` is known to be _the same_ constant in both branches of example 3, its value after the conditional is that same value. As one branch _diverges_ in example 4, the other branch(es) determine the value after the conditional.

The last example shows how certain operations can result in constant results with non-constant operands: `a` is not known, yet `b` is known to be zero.

== Data domain & extended domain

To reason about values that variables/terms can take, we first need a data domain $DD$ (for which we require a distinguised element $bot in DD$). While in $Lattice(BB)$ and $Lattice(BB_or)$, the two values $"true"$ and $"false"$ are related through $rel$, for constant propagation, they have no meaning except for being distinct. We therefore work on a _flat lattice_ $FL_DD = (DD', subset.eq.sq, sect.sq, union.sq, bot, top)$, with the extended domain $DD' = DD union {top}$ containing another distinguished element:

#align(center)[
  #grid(
    columns: 2,
    gutter: 4em,

    figure(
      caption: [Hasse diagram of $FL_BB$],
      numbering: none,
    )[
      #commutative_diagram(
        node_padding: (28pt, 28pt),
        arr_clearance: 1em,
        node((0, 1), [$top$]),
        node((1, 0), [$f$]),
        node((1, 2), [$t$]),
        node((2, 1), [$bot$]),
        arr((2, 1), (1, 0), []),
        arr((2, 1), (1, 2), []),
        arr((1, 0), (0, 1), []),
        arr((1, 2), (0, 1), []),
      )
    ],
    figure(
      caption: [Hasse diagram of $FL_ZZ$],
      numbering: none,
    )[
      #let extreme = 2
      #let count = extreme*2 + 1
      #let middle = extreme + 1
      #let right = count + 1

      #commutative_diagram(
        node_padding: (20pt, 28pt),
        // arr_clearance: 0.5em,
        node((0, middle), [$top$]),
        node((1, 0), [$...$]),
        ..range(0, count).map((i) => (
          node((1, i+1), [$#(i - extreme)$]),
          arr((1, i+1), (0, middle), []),
          arr((2, middle), (1, i+1), []),
        )).flatten(),
        node((1, right), [$...$]),
        node((2, middle), [$bot$]),
      )
    ],
  )
]

We can now talk about _states_, which assign a value to each variable (this is why we require $bot in DD$: even variables not defined at some program points need to be covered). A state is thus a function $sigma: Vars -> DD$. We also define DFA states that allow all values of the extended domain: $sigma: Vars -> DD'$ and the sets of all (extended) states:

$
Sigma
  &= { sigma | sigma in Vars -> DD } \

Sigma'
  &= { sigma | sigma in Vars -> DD' }
$

This latter set is significant because we can construct a lattice on it by _pointwise ordering_ according to the ordering of $FL_(DD')$:

$
sigma rel_(Sigma') sigma'
  &quad& #[iff $forall v in Vars: sigma(v) rel_(FL_(DD')) sigma'(v)$]
$

Or in words: two DFA states are related according to the lattice's ordering iff all variable assignments in these states are related. This results in pointwise meet and join operations as well, and two distinguished top and bottom states:

$
sigma meet_(Sigma') sigma'
  &= lambda v. sigma(v) meet_(FL(DD)) sigma'(v) \

sigma join_(Sigma') sigma'
  &= lambda v. sigma(v) join_(FL(DD)) sigma'(v) \

sigma_bot
  &= lambda v. bot \

sigma_top
  &= lambda v. top
$

$
Lattice(Sigma') = (Sigma', subset.eq.sq, sect.sq, union.sq, sigma_bot, sigma_top)
$

Consider some control flow examples again in light of this flat lattice:

#align(center)[
  #grid(
    columns: 3,
    gutter: 2em,

    block(width: 3cm)[
      ```py
      if p: a = true
      else: a = false
      print(a)
      ```
    ],

    block(width: 3cm)[
      ```py
      if p: a = true
      else: a = true
      print(a)
      ```
    ],

    block(width: 3cm)[
      ```py
      if p: a = true
      else: return
      print(a)
      ```
    ],
  )
]

Before exiting the conditional, we have two states $sigma_1$ and $sigma_2$, and right after a state $sigma_3 = sigma_1 meet sigma_2$. According to the lattice, we get

$
"Example 1:"
  &quad& sigma_1(a) &= "true",
  &thick&& sigma_2(a) &= "false"
  &thick&& => sigma_3(a) &= bot \

"Example 2:"
  &quad& sigma_1(a) &= "true",
  &&& sigma_2(a) &= "true"
  &&& => sigma_3(a) &= "true" \

"Example 3:"
  &quad& sigma_1(a) &= "true",
  &&& sigma_2(a) &= top
  &&& => sigma_3(a) &= "true"
$

We can see that $bot$ means the value is unknown (not constant) and $top$ means the value does not exist (due to the divergence of the branch).

Since the $top$ value only represents impossibilities, we define another set $Sigma'_"Init"$ excluding those states that contain $top$ variable assignments:

$
Sigma'_"Init" = {sigma in Sigma' | forall v in Vars. sigma(v) != top}
$

== Variables, terms and operators

It is no longer sufficient (as it was for bitvector analyses) to just look at _what_ variables appear in expressions; to know whether an expression is constant, and if so what contstant it evaluates to, we need to consider _how_ an expression combines variables. We therefore consider the disjoint sets $Vars$ of variables, $Consts$ of constants, $Ops$ of operators, and $Terms$ of terms. The set of terms contains the syntaxtically possible combinations of the other three. On top of these, the semantics can be defined.

== (Extended) interpretation, evaluation function, state transformer

The (extended) interpretation $I_0$ ($I_0'$) describe the semantics of constants and operators; they can be thought of as "overloaded" for these two kinds of parameters:

$
I_0 &: cases(
  Consts -> DD,
  Ops -> (DD^k -> DD) &quad #[for a $k$-ary operator]
) \

I_0' &: cases(
  Consts -> DD',
  Ops -> (DD'^k -> DD') &quad #[for a $k$-ary operator]
)
$

These functions satisfy that

- if some of the operands of an operator are $bot$, the operation's result is $bot$; and
- (for the extended interpretation) otherwise, if some of the operands of an operator are $top$, the operation's result is $top$.

Based on that, the (extended) evaluation function $Eval$ ($Eval'$) is defined:

$
Eval &: Terms -> (Sigma -> DD) \

Eval' &: Terms -> (Sigma' -> DD')
$

Intuitively, these functions recursively apply themselves to parts of the expression, grounding themselves in $I_0$ ($I_0'$) for constants and operators, and in the current state for variables.

The exact form of these functions depends on the kind of constant propagation. For example, the term `a * 0` is not a simple constant, but it is a linear constant.

Likewise, the (extended) state transformer $Theta$ ($Theta'$) transforms an (extended) state into another based on the local semantics of an instruction:

$
Theta &: Sigma -> Sigma \

Theta' &: Sigma' -> Sigma'
$

With this, we can finally formulate a DFA specification for constant propagation:

$
Spec_G
  & = (Lattice(Sigma'), Func(), sigma_s, fw) \

"where"
Func(e: e) &= Theta'_instr_e \

sigma_s &in Sigma'_"Init"
$

The difference between constant propagation specifications lies in how the extended evaluation function $Eval'$ deals with different kinds of terms:

== Simple constants

The simple constant analysis evaluates terms containing constants and constant variables to non-$bot$ values:

$
Eval'(t)(sigma) &= cases(
  sigma(v)
    &quad #[if $t ident v in Vars$],
  I_0'(c)
    &quad #[if $t ident c in Consts$],
  I_0'("op")(Eval'(t_1)(sigma), ..., Eval'(t_k)(sigma))
    &quad #[if $t ident ("op", t_1, ..., t_k)$]
)
$

== Copy constants

The copy constant analysis only deals with terms that are either constants themselves, or are just a variable reference. Other terms are assumed to be not constant. In other words, _copying_ one variable value into another variable is the only kind of constant _propagation_ that is performed:

$
Eval'(t)(sigma) &= cases(
  sigma(v)
    &quad #[if $t ident v in Vars$],
  I_0'(c)
    &quad #[if $t ident c in Consts$],
  bot
    &quad #[otherwise]
)
$

== Linear constants

The linear constants analysis limits itself to linear arithmetic terms: it considers terms of the form $c*v plus.circle d$ (with $c, d in Consts$, $v in Vars$, $plus.circle in {+, -}$) specially (as well as other semantically equivalent forms such as $d eq.est 0*v + d$, $c*v eq.est c*v + 0$, etc.):

$
Eval'(t)(sigma) &= cases(
  sigma(v)
    &quad #[if $t ident v in Vars$],
  Eval_"SC" (t)(sigma)
    &quad #[if $t ident c*v plus.circle d$],
  bot
    &quad #[otherwise]
)
$

where $Eval_"SC"$ is the extended evaluation function for simple constants.

== Q constants (Kam & Ullman)

Q-constants do not use a different evaluation function; instead, the MaxFP algorithm is fixed slightly. Consider these code examples and a simple constant analysis on them:

#align(center)[
  #grid(
    columns: 2,
    gutter: 2em,

    block(width: 3cm)[
      ```py
      if p:
        a = 2
        b = 3
      else:
        a = 2
        b = 3
      c = a + b
      print(c)
      ```
    ],

    block(width: 3cm)[
      ```py
      if p:
        a = 2
        b = 3
      else:
        a = 3
        b = 2
      c = a + b
      print(c)
      ```
    ],
  )
]

In the first example, both `a` and `b` are constants after the conditional, but in the first example they are not; `a + b`, however, is a constant not detected by the simple constant analysis. Recall:

- Before exiting the conditional, we have $sigma_1$ with $a=2, b=3$ and $sigma_2$ with $a=3, b=2$.

- We compute $sigma_3 = sigma_1 meet sigma_2$ and find that in this state, $a=bot, b=bot$.

- We evaluate $Eval'(a+b)(sigma_3) = bot$.

The Q constants approach is now to perform the meet operation later:

- Before exiting the conditional, we have $sigma_1$ with $a=2, b=3$ and $sigma_2$ with $a=3, b=2$.

- We evaluate $Eval'(a+b)(sigma_1) = 5, Eval'(a+b)(sigma_2) = 5$.

- We compute the result $5 meet 5 = 5$ and thus detected the result as a constant.

Taking the meet "lazily" after the evaluation results in more evaluations overall, but improves precision. This approach can be generalized to taking the meet more than one step later.

== Finite constants

In contrast to the CP analyses so far, finite constants are based on _terms_: the problem illustrated for Q constants was that while previous analyses kept track of variable values (e.g. of $a$ and $b$), the value of terms such as $a+b$ was not remembered. If we stored $a+b=5$ as part of the information at the end of both branches, the MaxFP algorithm would naturally preserve and forward that information.

There are infinitely many possible terms, but fortunately, only a finite set of them needs to be considered (why?), leading to the name _finite constants_.

== Conditional constants

In previous example, the predicate variable $p$ was left as an unknown; if however a condition is itself constant, this means we don't need to join control flows and can avoid the lossy meet operation at the end altogether.

To do so, we need to extend our domain to include boolean values: $DD_BB = DD union BB$, and extend our definitions to allow for comparisons and logical operators, so that boolean terms can be formed. On top of this, we use the flat lattice $FL_DD_BB$ and state lattice $Lattice(Sigma')$

== Value graph approach

TODO

#pagebreak(weak: true)

= Partial redundancy elimination

PRE is an optimization that avoids recomputing the same value multiple times. The tool for this is moving computations to one or more earlier points in the flow graph (particularly outside a loop the original computation appeared in). Whenever these stored results are used, none of the variables used in the computation must have changed in the meantime ("correctness"). The three goals which can be traded are

- performance: minimize the number of computations done at runtime
- register pressure: minimize the amount of time a result needs to be held in a register
- code size: minimize the number of instructions in the flow graph

Classically, there is an additional requirement for the code motion: no program path that originally did not compute the value may be made to compute the value after code motion. This is called "safety", because the extra computation could result in a failure even though the branch containing the failing code wasn't taken.

Trading these in different ways leads to a taxonomy of multiple code motion strategies, for example:

- *Busy code motion* (BCM) moves calculations to the earliest opportunity. It is computationally optimal.
- *Lazy code motion* (LCM) moves calculations to the latest opportunity. It is computationally and lifetime optimal.
- *Sparse code motion* (SpCM) moves calculations to the latest position where the resulting program is code size optimal. Computational and lifetime optimality is not achieved, but no program of the same size is better.

== Code motions and admissibility

A code motion transformation ($CM$) of some candidate expression $t in Terms$ on a _node-labelled_ flow graph is defined by

- $Insert_CM (n)$: whether a computation of the form $h := t$, where $h$ is a new variable name, is inserted at the entry of node $n$;
- $Repl_CM (n)$: whether occurrences of $t$ are replaced by references to $h$ at $n$.

Obviously, not all CMs lead to correct code, thus we define admissibility: we want CMs that satisfy the following properties:

- Safety: a computation is only inserted on paths where the original program also computed the term. That means an insertion only happens at a node $n$ where the term is either available (= "up-safe": it has been computed without redefinition in the original program on all paths leading to $n$), or very busy (= "down-safe": it will be used without redefinition on all paths coming from $n$).
- Correctness: whenever $h$ is used, there is a definition of $h$ before that and $h$'s operands have not been redefined since then.

$
forall n in N. &&Insert_CM (n) &=> Safe(n) \

forall n in N. &&Repl_CM (n) &=> Correct_CM (n)
$

$
"where" quad
Safe(n) = &Available(n) or VeryBusy(n) \

Correct_CM (n) =
    &forall path(#$n_1, ..., n_k$) in Paths[s, n]. exists i. \
    &quad Insert_CM (n_i) and Transp^forall (path(#$n_i, ..., n_(k-1)$))
$

Where $Transp(n)$ means that $t$'s operands are not redefined at $n$ and $Transp^forall (p)$ extends that to apply to all nodes on path $p$.

=== Safety example

What follows is a node-labelled flow graph where the up- and down safety of the expression $a+b$ is highlighted in blue and green, respectively. The highlighted nodes are thus the ones where computations of the form $h := a+b$ may be inserted.

#align(center)[
  #let stmt = rect.with(
    width: 5em,
    height: 1.7em,
    stroke: 0.5pt,
  )

  #let nodes = (
    // put something in column 1 so that spacing is correct
    "dummy": ((0, 1), stmt(stroke: none)[]),
    "1": ((0, 4), stmt[]),
    "2": ((1, 3), stmt[$a := c$]),
    "3": ((2, 3), stmt(fill: green)[$x := a+b$]),
    "4": ((2, 5), stmt[]),
    "5": ((3, 4), stmt[]),
    "6": ((4, 3), stmt(fill: green)[]),
    "7": ((4, 5), stmt(fill: green)[]),
    "8": ((5, 2), stmt(fill: green)[]),
    "9": ((5, 4), stmt(fill: green)[]),
    "10": ((6, 0), stmt(fill: green)[$y := a+b$]),
    "11": ((6, 2), stmt(fill: green)[]),
    "12": ((6, 4), stmt(fill: green)[]),
    "13": ((6, 6), stmt(fill: green)[]),
    "14": ((7, 2), stmt(fill: green)[$x := a+b$]),
    "15": ((7, 4), stmt(fill: green)[$y := a+b$]),
    "16": ((8, 3),
      move(dx: 4pt, dy: 4pt,
        stmt(fill: blue, inset: 0pt,
          move(dx: -4pt, dy: -4pt,
            stmt(fill: green)[$z := a+b$]
      )))
    ),
    "17": ((8, 5), stmt(fill: green)[$x := a+b$]),
    "18": ((9, 5), stmt[]),
  )

  #let arrow(a, b, ..args) = arr(
    nodes.at(a).at(0),
    nodes.at(b).at(0),
    ..args,
  )

  #let arrows(body: [], ..names) = {
    names = names.pos()
    range(names.len() - 1).map((i) => {
      arrow(names.at(i), names.at(i+1), body)
    })
  }

  #commutative_diagram(
    node_padding: (-10pt, 20pt),
    arr_clearance: 0.2em,
    ..nodes.values().map(((pos, body)) => node(pos, body)),
    ..arrows("1", "2", "3", "5", "6", "8", "11", "14", "16", "18"),
    ..arrows("1", "4", "5", "7"),
    ..arrows("6", "9", "12", "15", "16"),
    ..arrows("17", "18"),
    arrow("11", "10", curve: 40deg)[],
    arrow("10", "11", curve: 40deg)[],
    arrow("12", "13", curve: -40deg)[],
    arrow("13", "12", curve: -40deg)[],
    arrow("12", "17", curve: 20deg)[],
    arrow("7", "18", curve: 60deg)[],
  )
]

== Busy code motion (BCM)

BCM uses the earliestness principle to decide where to put computations, then eliminates redundant computations (i.e. those that can be replaced by referencing the new variable, e.g. $h$). Earliestness is defined as follows:

$
Earliest(n) = Safe(n) and cases(
  "true"
    &#[if $n$ is the start node],
  limits(or.big)_(m in pred(n)) not Transp(m) or not Safe(m)
    quad
    &#[otherwise],
)
$

The BCM transformation is thus defined by

$
Insert_BCM (n) = Earliest(n) \
Repl_BCM (n) = Comp(n)
$

BCM is computationally optimal, but maximizes register pressure. Code size can grow.

== Lazy code motion (LCM)

LCM is both computationally and lifetime optimal.
