fn not_four(k) {
  if k == 4 {
    fail @"illegal"
  } else {
    True
  }
}

test test_or() {
  let k = 4
  expect or {
      k * k == k + 12,
      not_four(k),
    }
  k == 4
}
