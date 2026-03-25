## bounds.nim -- Prove upper/lower bounds on objective function via Z3.
##
## Given an SMT problem and a candidate solution score, prove that the
## score is optimal or within a proven bound.

{.experimental: "strict_funcs".}

import std/strutils
import basis/code/choice, encode

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  BoundKind* = enum
    bkLower   ## Proven lower bound (minimum possible)
    bkUpper   ## Proven upper bound (maximum possible)

  BoundProof* = object
    kind*: BoundKind
    value*: int
    proven*: bool         ## Whether the bound was proven (sat/unsat)
    description*: string

  CheckBoundFn* = proc(smtlib: string): Choice[bool] {.raises: [].}
    ## Function that checks an SMT-LIB assertion. Returns true if SAT.

# =====================================================================================================================
# Bound checking
# =====================================================================================================================

proc make_lower_bound_query*(problem: SmtProblem, bound: int): string =
  ## Generate SMT-LIB query: "Is there a solution with objective < bound?"
  ## If UNSAT, then `bound` is a proven lower bound.
  var lines: seq[string]
  lines.add("(set-logic QF_LIA)")
  for v in problem.variables:
    lines.add("(declare-const " & v.name & " Int)")
    lines.add("(assert (>= " & v.name & " 0))")
    lines.add("(assert (< " & v.name & " " & $v.domain_size & "))")
  for c in problem.constraints:
    lines.add("(assert " & c.assertion & ")")
  if problem.objective.len > 0:
    lines.add("(assert (< " & problem.objective & " " & $bound & "))")
  lines.add("(check-sat)")
  lines.join("\n")

proc make_upper_bound_query*(problem: SmtProblem, bound: int): string =
  ## Generate SMT-LIB query: "Is there a solution with objective > bound?"
  ## If UNSAT, then `bound` is a proven upper bound.
  var lines: seq[string]
  lines.add("(set-logic QF_LIA)")
  for v in problem.variables:
    lines.add("(declare-const " & v.name & " Int)")
    lines.add("(assert (>= " & v.name & " 0))")
    lines.add("(assert (< " & v.name & " " & $v.domain_size & "))")
  for c in problem.constraints:
    lines.add("(assert " & c.assertion & ")")
  if problem.objective.len > 0:
    lines.add("(assert (> " & problem.objective & " " & $bound & "))")
  lines.add("(check-sat)")
  lines.join("\n")

proc check_lower_bound*(problem: SmtProblem, bound: int,
                        check_fn: CheckBoundFn): Choice[BoundProof] =
  ## Check if `bound` is a proven lower bound.
  ## If no solution exists with objective < bound, the bound is proven.
  let query = make_lower_bound_query(problem, bound)
  let sat = check_fn(query)
  if sat.is_bad:
    return bad[BoundProof](sat.err)
  let proven = not sat.val  # UNSAT means bound is proven
  good(
    BoundProof(kind: bkLower, value: bound, proven: proven,
               description: if proven: "Proven: no solution below " & $bound
                            else: "Not proven: solution exists below " & $bound))

proc check_upper_bound*(problem: SmtProblem, bound: int,
                        check_fn: CheckBoundFn): Choice[BoundProof] =
  ## Check if `bound` is a proven upper bound.
  let query = make_upper_bound_query(problem, bound)
  let sat = check_fn(query)
  if sat.is_bad:
    return bad[BoundProof](sat.err)
  let proven = not sat.val
  good(
    BoundProof(kind: bkUpper, value: bound, proven: proven,
               description: if proven: "Proven: no solution above " & $bound
                            else: "Not proven: solution exists above " & $bound))
