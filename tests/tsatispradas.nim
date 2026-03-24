## tsatispradas.nim -- Tests for satispradas bridge.

{.experimental: "strict_funcs".}

import std/[unittest, strutils, tables]
import satispradas

# =====================================================================================================================
# Encode tests
# =====================================================================================================================

suite "encode":
  test "encode simple problem":
    let result = encode_problem(
      @[("x", 5), ("y", 5)],
      @[("different", "(not (= x y))")])
    check result.is_good
    check result.val.variables.len == 2
    check result.val.constraints.len == 1

  test "encode rejects zero domain":
    let result = encode_problem(@[("x", 0)], @[])
    check result.is_bad

  test "to_smtlib generates valid output":
    let problem = encode_problem(@[("x", 3)], @[("positive", "(> x 0)")])
    check problem.is_good
    let smt = to_smtlib(problem.val)
    check smt.contains("declare-const x Int")
    check smt.contains(">= x 0")
    check smt.contains("< x 3")
    check smt.contains("(> x 0)")
    check smt.contains("check-sat")

  test "variable_names":
    let problem = encode_problem(@[("a", 2), ("b", 3)], @[])
    check problem.is_good
    check variable_names(problem.val) == @["a", "b"]

# =====================================================================================================================
# Bounds tests
# =====================================================================================================================

suite "bounds":
  test "lower bound query format":
    let problem = encode_problem(@[("cost", 10)], @[], "cost", true)
    check problem.is_good
    let query = make_lower_bound_query(problem.val, 5)
    check query.contains("< cost 5")

  test "upper bound query format":
    let problem = encode_problem(@[("profit", 10)], @[], "profit", false)
    check problem.is_good
    let query = make_upper_bound_query(problem.val, 8)
    check query.contains("> profit 8")

  test "check lower bound proven (UNSAT)":
    let problem = encode_problem(@[("x", 5)], @[], "x", true)
    check problem.is_good
    let mock_check: CheckBoundFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(false)  # UNSAT -> bound proven
    let result = check_lower_bound(problem.val, 0, mock_check)
    check result.is_good
    check result.val.proven
    check result.val.kind == bkLower

  test "check lower bound not proven (SAT)":
    let problem = encode_problem(@[("x", 5)], @[], "x", true)
    check problem.is_good
    let mock_check: CheckBoundFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(true)  # SAT -> bound not proven
    let result = check_lower_bound(problem.val, 3, mock_check)
    check result.is_good
    check not result.val.proven

# =====================================================================================================================
# Feasibility tests
# =====================================================================================================================

suite "feasibility":
  test "feasible problem":
    let problem = encode_problem(@[("x", 5)], @[("pos", "(> x 0)")])
    check problem.is_good
    let mock_check: CheckSatFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(true)
    let result = check_feasibility(problem.val, mock_check)
    check result.is_good
    check result.val.feasible

  test "infeasible problem":
    let problem = encode_problem(@[("x", 5)], @[("impossible", "(> x 100)")])
    check problem.is_good
    let mock_check: CheckSatFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(false)
    let result = check_feasibility(problem.val, mock_check)
    check result.is_good
    check not result.val.feasible

# =====================================================================================================================
# Certificate tests
# =====================================================================================================================

suite "certificate":
  test "make and verify certificate":
    let problem = encode_problem(@[("x", 5), ("y", 5)],
                                 @[("diff", "(not (= x y))")])
    check problem.is_good
    var assignments: Table[string, int]
    assignments["x"] = 1
    assignments["y"] = 2
    var cert = make_certificate(problem.val, assignments)
    check not cert.verified
    let mock_verify: VerifyCertFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(true)
    let result = verify_certificate(problem.val, cert, mock_verify)
    check result.is_good
    check result.val
    check cert.verified
    check cert.constraints_satisfied == 1

  test "format certificate":
    var assignments: Table[string, int]
    assignments["x"] = 3
    let cert = Certificate(variables: assignments, constraints_satisfied: 1,
                           total_constraints: 1, verified: true,
                           description: "ok")
    let text = format_certificate(cert)
    check text.contains("VERIFIED")
    check text.contains("x = 3")

# =====================================================================================================================
# Session tests
# =====================================================================================================================

suite "session":
  test "solve and verify end-to-end":
    let problem = encode_problem(@[("x", 5)], @[("pos", "(> x 0)")])
    check problem.is_good
    let mock_check: CheckSatFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(true)
    let mock_solve: SolveFn = proc(p: SmtProblem): Result[Table[string, int], BridgeError] {.raises: [].} =
      var a: Table[string, int]
      a["x"] = 3
      Result[Table[string, int], BridgeError].good(a)
    var session = new_verify_session(mock_check, mock_solve)
    let result = session.solve_and_verify(problem.val)
    check result.is_good
    check result.val.verified
    check result.val.variables["x"] == 3
    let (f, v, b) = session.stats()
    check f == 1
    check v == 1

  test "infeasible problem fails early":
    let problem = encode_problem(@[("x", 5)], @[("impossible", "(> x 100)")])
    check problem.is_good
    let mock_check: CheckSatFn = proc(s: string): Result[bool, BridgeError] {.raises: [].} =
      Result[bool, BridgeError].good(false)
    let mock_solve: SolveFn = proc(p: SmtProblem): Result[Table[string, int], BridgeError] {.raises: [].} =
      var a: Table[string, int]
      Result[Table[string, int], BridgeError].good(a)
    var session = new_verify_session(mock_check, mock_solve)
    let result = session.solve_and_verify(problem.val)
    check result.is_bad
