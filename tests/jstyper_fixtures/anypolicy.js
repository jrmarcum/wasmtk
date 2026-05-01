// anypolicy.js — fixture for testing --any-policy handling

export function safe(a, b) {
  return a + b;
}

export function hasAnyParam(x, data) {
  return x;
}

export function hasAnyReturn(x) {
  return x;
}
