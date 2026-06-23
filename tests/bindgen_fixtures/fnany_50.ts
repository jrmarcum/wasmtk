// bindgen fixture — functions-as-`any` (#14 final item). `getDoubler` returns a dynrt function value
// (built from strings via the `Function(params, body)` producer); bindgen wraps it as a callable JS
// proxy on the host (pinned, calls back via dynApply).
type i32 = number;
type f64 = number;

export function getDoubler(): any {
  return Function("x", "return x * 2;");
}
