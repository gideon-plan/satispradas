## encode.nim -- Translate pradas domain/constraints into SMT-LIB assertions.
##
## Maps planning entities, variables, and constraints into Z3-compatible
## SMT-LIB2 format for formal verification.

{.experimental: "strict_funcs".}

import std/strutils
import lattice

# =====================================================================================================================
# Types
# =====================================================================================================================

type
  SmtVariable* = object
    name*: string
    domain_size*: int  ## Number of possible values (0..domain_size-1)

  SmtConstraint* = object
    description*: string
    assertion*: string  ## SMT-LIB2 assertion body

  SmtProblem* = object
    variables*: seq[SmtVariable]
    constraints*: seq[SmtConstraint]
    objective*: string       ## Variable name being optimized
    minimize*: bool          ## true = minimize, false = maximize

# =====================================================================================================================
# Encoding
# =====================================================================================================================

proc encode_variable*(name: string, domain_size: int): SmtVariable =
  SmtVariable(name: name, domain_size: domain_size)

proc encode_constraint*(description, assertion: string): SmtConstraint =
  SmtConstraint(description: description, assertion: assertion)

proc encode_problem*(entities: seq[(string, int)],
                     hard_constraints: seq[(string, string)],
                     objective: string = "", minimize: bool = true
                    ): Result[SmtProblem, BridgeError] =
  ## Encode a pradas-style problem into SMT representation.
  ## entities: (name, domain_size) pairs
  ## hard_constraints: (description, SMT-LIB assertion) pairs
  var vars: seq[SmtVariable]
  for (name, dom) in entities:
    if dom <= 0:
      return Result[SmtProblem, BridgeError].bad(
        BridgeError(msg: "Invalid domain size for " & name & ": " & $dom))
    vars.add(encode_variable(name, dom))
  var constraints: seq[SmtConstraint]
  for (desc, assertion) in hard_constraints:
    constraints.add(encode_constraint(desc, assertion))
  Result[SmtProblem, BridgeError].good(
    SmtProblem(variables: vars, constraints: constraints,
               objective: objective, minimize: minimize))

proc to_smtlib*(problem: SmtProblem): string =
  ## Generate SMT-LIB2 string from encoded problem.
  var lines: seq[string]
  lines.add("(set-logic QF_LIA)")  ## Quantifier-free linear integer arithmetic
  # Declare variables
  for v in problem.variables:
    lines.add("(declare-const " & v.name & " Int)")
    # Domain bounds: 0 <= v < domain_size
    lines.add("(assert (>= " & v.name & " 0))")
    lines.add("(assert (< " & v.name & " " & $v.domain_size & "))")
  # Hard constraints
  for c in problem.constraints:
    lines.add("(assert " & c.assertion & ")  ; " & c.description)
  lines.add("(check-sat)")
  lines.add("(get-model)")
  lines.join("\n")

proc variable_names*(problem: SmtProblem): seq[string] =
  for v in problem.variables:
    result.add(v.name)
