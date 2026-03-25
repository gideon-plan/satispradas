## certificate.nim -- Extract Z3 model as proof certificate for pradas solution.
##
## After pradas finds a solution, generate a certificate that Z3 can verify.

{.experimental: "strict_funcs".}

import std/[strutils, tables]
import basis/code/choice, encode

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  Certificate* = object
    variables*: Table[string, int]  ## Variable -> assigned value
    constraints_satisfied*: int
    total_constraints*: int
    verified*: bool
    description*: string

  VerifyCertFn* = proc(smtlib: string): Choice[bool] {.raises: [].}
    ## Returns true if the certificate is valid (all assertions SAT).

# =====================================================================================================================
# Certificate generation
# =====================================================================================================================

proc make_certificate*(problem: SmtProblem,
                       assignments: Table[string, int]): Certificate =
  ## Create a certificate from a pradas solution.
  Certificate(variables: assignments,
              constraints_satisfied: 0,
              total_constraints: problem.constraints.len,
              verified: false,
              description: "Unverified certificate")

proc to_verification_query*(problem: SmtProblem, cert: Certificate): string =
  ## Generate SMT-LIB query that asserts the solution and checks all constraints.
  var lines: seq[string]
  lines.add("(set-logic QF_LIA)")
  for v in problem.variables:
    lines.add("(declare-const " & v.name & " Int)")
  # Fix variables to certificate values
  for name, value in cert.variables:
    lines.add("(assert (= " & name & " " & $value & "))")
  # Assert all constraints
  for c in problem.constraints:
    lines.add("(assert " & c.assertion & ")")
  lines.add("(check-sat)")
  lines.join("\n")

proc verify_certificate*(problem: SmtProblem, cert: var Certificate,
                         verify_fn: VerifyCertFn): Choice[bool] =
  ## Verify a certificate against the problem constraints.
  let query = to_verification_query(problem, cert)
  let sat = verify_fn(query)
  if sat.is_bad:
    return bad[bool](sat.err)
  cert.verified = sat.val
  cert.constraints_satisfied = if sat.val: cert.total_constraints else: 0
  cert.description = if sat.val: "Certificate verified: all constraints satisfied"
                     else: "Certificate invalid: constraints violated"
  good(sat.val)

proc format_certificate*(cert: Certificate): string =
  ## Human-readable certificate.
  var lines: seq[string]
  lines.add("Certificate: " & (if cert.verified: "VERIFIED" else: "UNVERIFIED"))
  lines.add("Constraints: " & $cert.constraints_satisfied & "/" & $cert.total_constraints)
  for name, value in cert.variables:
    lines.add("  " & name & " = " & $value)
  lines.join("\n")
