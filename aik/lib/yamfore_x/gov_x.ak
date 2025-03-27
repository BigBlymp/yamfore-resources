use aiken/fuzz
use aiken/transaction.{OutputReference, TransactionId}
use yamfore/types as t

pub fn ratio() -> Fuzzer<(Int, Int)> {
  fuzz.map2(
    fuzz.int_at_least(1),
    fuzz.int_at_least(1),
    fn(num, denom) { (num, denom) },
  )
}

pub fn output_reference() -> Fuzzer<OutputReference> {
  fuzz.map2(
    fuzz.bytearray_between(64, 64),
    fuzz.int_between(0, 1024),
    fn(x, y) { OutputReference(TransactionId(x), y) },
  )
}

// GovParams = OutputReference

pub fn gov_dat() -> Fuzzer<t.GovDat> {
  fuzz.map3(ratio(), ratio(), ratio(), t.GovDat)
}
