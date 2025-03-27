use aiken/dict
use aiken/list
use aiken/transaction.{Input, Mint, OutputReference, ScriptContext, Transaction}
use aiken/transaction/value
use yamfore/constants as c
use yamfore/tokens

// FOR TESTING PURPOSES ONLY

pub type Usd2Red {
  Usd2Mint
  Usd2Burn
}

validator(params: OutputReference) {
  pub fn two(red: Usd2Red, ctx: ScriptContext) {
    let ScriptContext { transaction, purpose } = ctx
    trace @"2Args: purpose is mint only"
    expect Mint(own_pid) = purpose
    let Transaction { inputs, mint, .. } = transaction
    expect [Pair(usd_name, usd_amt)] =
      dict.to_pairs(value.tokens(value.from_minted_value(mint), own_pid))
    when red is {
      Usd2Mint -> {
        trace @"**Usd2Mint**:"
        trace @"1. `UsdParams` is spent"
        expect list.any(inputs, fn(i) { i.output_reference == params })
        trace @"2. Own mint is `[(usd, usd_total)]`"
        expect tokens.usd() == usd_name
        expect c.total_usd() == usd_amt
        True
      }
      Usd2Burn -> {
        trace @"**Usd2Burn**:"
        trace @"1. Own mint has only negative quantities"
        usd_amt < 0
      }
    }
  }
}
