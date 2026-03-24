## lattice.nim -- Minimal result lattice for satispradas.

{.experimental: "strict_funcs".}

type
  Result*[T, E] = object
    case ok*: bool
    of true:  val*: T
    of false: err*: E

  BridgeError* = object of CatchableError

func good*[T, E](R: typedesc[Result[T, E]], val: T): Result[T, E] =
  Result[T, E](ok: true, val: val)

func bad*[T, E](R: typedesc[Result[T, E]], err: E): Result[T, E] =
  Result[T, E](ok: false, err: err)

func is_good*[T, E](r: Result[T, E]): bool = r.ok
func is_bad*[T, E](r: Result[T, E]): bool = not r.ok

func get_or*[T, E](r: Result[T, E], default: T): T =
  if r.ok: r.val else: default
