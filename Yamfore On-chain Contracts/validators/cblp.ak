use aiken/dict
use aiken/list
use aiken/transaction.{Input, Mint, OutputReference, ScriptContext, Transaction}
use aiken/transaction/value
use yamfore/constants as c
use yamfore/tokens

// FOR TESTING PURPOSES ONLY

pub type Cblp2Red {
  Cblp2Mint
  Cblp2Burn
}

validator(params: OutputReference) {
  pub fn two(red: Cblp2Red, ctx: ScriptContext) {
    let ScriptContext { transaction, purpose } = ctx
    trace @"2Args: purpose is mint only"
    expect Mint(own_pid) = purpose
    let Transaction { inputs, mint, .. } = transaction
    expect [Pair(cblp_asset_name, cblp_amt)] =
      dict.to_pairs(value.tokens(value.from_minted_value(mint), own_pid))
    when red is {
      Cblp2Mint -> {
        trace @"**Cblp2Mint**:"
        trace @"1. `CblpParams` is spent"
        expect list.any(inputs, fn(i) { i.output_reference == params })
        trace @"2. Own mint is `[(cblp, TOTAL_cblp)]`"
        expect tokens.cblp() == cblp_asset_name
        expect c.total_cblp() == cblp_amt
        True
      }
      Cblp2Burn -> {
        trace @"**Cblp2Burn**:"
        trace @"1. Own mint has only negative quantities"
        cblp_amt < 0
      }
    }
  }
}
