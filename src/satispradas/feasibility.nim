## feasibility.nim -- Verify hard constraint satisfiability before solving.
##
## Before invoking pradas (which is heuristic), check with Z3 whether
## the hard constraints are even satisfiable.

{.experimental: "strict_funcs".}

import std/strutils
import basis/code/choice, encode

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  FeasibilityResult* = object
    feasible*: bool
    description*: string

  CheckSatFn* = proc(smtlib: string): Choice[bool] {.raises: [].}
    ## Returns true if the SMT-LIB problem is satisfiable.

# =====================================================================================================================
# Feasibility check
# =====================================================================================================================

proc check_feasibility*(problem: SmtProblem,
                        check_fn: CheckSatFn): Choice[FeasibilityResult] =
  ## Check if the hard constraints are satisfiable.
  let smtlib = to_smtlib(problem)
  let sat = check_fn(smtlib)
  if sat.is_bad:
    return bad[FeasibilityResult](sat.err)
  if sat.val:
    good(
      FeasibilityResult(feasible: true,
                        description: "Hard constraints are satisfiable"))
  else:
    good(
      FeasibilityResult(feasible: false,
                        description: "Hard constraints are unsatisfiable -- no solution exists"))

proc check_feasibility_with_extra*(problem: SmtProblem, extra_assertion: string,
                                   check_fn: CheckSatFn
                                  ): Choice[FeasibilityResult] =
  ## Check feasibility with an additional constraint (e.g. "what if we also require X?").
  var lines: seq[string]
  lines.add(to_smtlib(problem))
  # Insert extra assertion before check-sat
  let parts = lines[0].split("(check-sat)")
  if parts.len >= 2:
    let modified = parts[0] & "(assert " & extra_assertion & ")\n(check-sat)" & parts[1]
    let sat = check_fn(modified)
    if sat.is_bad:
      return bad[FeasibilityResult](sat.err)
    good(
      FeasibilityResult(feasible: sat.val,
                        description: if sat.val: "Feasible with extra constraint"
                                     else: "Infeasible with extra constraint"))
  else:
    bad[FeasibilityResult]("satispradas", "Failed to inject extra assertion")
