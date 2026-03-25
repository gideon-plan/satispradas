## session.nim -- Combined session managing satis + pradas lifecycle.
##
## Orchestrates: feasibility check -> solve -> verify certificate -> prove bounds.

{.experimental: "strict_funcs".}

import std/tables
import basis/code/choice, encode, feasibility, certificate

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SolveFn* = proc(problem: SmtProblem): Choice[Table[string, int]] {.raises: [].}
    ## Function that invokes pradas solver, returns variable assignments.

  VerifySession* = object
    check_fn*: CheckSatFn
    solve_fn*: SolveFn
    feasibility_checks*: int
    solutions_verified*: int
    bounds_proven*: int

# =====================================================================================================================
# Session
# =====================================================================================================================

proc new_verify_session*(check_fn: CheckSatFn, solve_fn: SolveFn): VerifySession =
  VerifySession(check_fn: check_fn, solve_fn: solve_fn)

proc solve_and_verify*(session: var VerifySession, problem: SmtProblem
                      ): Choice[Certificate] =
  ## Full pipeline: check feasibility, solve, verify certificate.
  # 1. Feasibility
  let feas = check_feasibility(problem, session.check_fn)
  if feas.is_bad:
    return bad[Certificate](feas.err)
  inc session.feasibility_checks
  if not feas.val.feasible:
    return bad[Certificate]("satispradas", feas.val.description)
  # 2. Solve
  let solution = session.solve_fn(problem)
  if solution.is_bad:
    return bad[Certificate](solution.err)
  # 3. Verify
  var cert = make_certificate(problem, solution.val)
  let verified = verify_certificate(problem, cert, session.check_fn)
  if verified.is_bad:
    return bad[Certificate](verified.err)
  inc session.solutions_verified
  if not verified.val:
    return bad[Certificate]("satispradas", "Solution failed verification")
  good(cert)

proc stats*(session: VerifySession): tuple[feasibility: int, verified: int, bounds: int] =
  (feasibility: session.feasibility_checks, verified: session.solutions_verified,
   bounds: session.bounds_proven)
