use aiken/fuzz
use yamfore/types as t

pub fn pf2red() -> Fuzzer<t.Pf2Red> {
  fuzz.map4(
    fuzz.int_at_least(1),
    fuzz.int_at_least(1),
    fuzz.int_at_least(1),
    fuzz.int_at_least(1),
    t.Pf2Red,
  )
}
