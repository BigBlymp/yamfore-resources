use aiken/dict
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, ScriptContext, Spend, Transaction,
}
use aiken/transaction/credential.{Address, ScriptCredential}
use aiken/transaction/value
use yamfore/tokens
use yamfore/types as t
use yamfore/utils as u

validator(params: t.PfpParams) {
  fn two(red: t.Pfp2Red, ctx: ScriptContext) {
    let ScriptContext { transaction, purpose } = ctx
    expect Mint(own_hash) = purpose
    trace @"Two Args: Mint Purpose"
    let Transaction { inputs, mint, outputs, .. } = transaction
    let own_tokens =
      dict.to_pairs(value.tokens(value.from_minted_value(mint), own_hash))
    when red is {
      t.Pfp2Init -> {
        trace @"**Pfp2Init**:"
        trace @"1. `PfpParams` is spent"
        expect list.any(inputs, fn(i) { i.output_reference == params })
        trace @"2. Own mint value is"
        trace @"    1. (pfp-auth, 1) "
        trace @"    2. (pfp-validity, 1)"
        expect [Pair(tn_0, qty_0), Pair(tn_1, qty_1)] = own_tokens
        expect and {
            tn_0 == tokens.pfp_auth(),
            qty_0 == 1,
            tn_1 == tokens.pfp_validity(),
            qty_1 == 1,
          }
        when outputs is {
          [o0, ..] -> {
            trace @"3. 0th output is continuing output:"
            let Output {
              address: cont_address,
              value: cont_value,
              datum: cont_datum,
              ..
            } = o0
            trace @"    1. Payment address is own address"
            expect ScriptCredential(own_hash) == cont_address.payment_credential
            trace @"    2. Value is ada and pfp-validity"
            expect [_, (pid, an, _)] = value.flatten(cont_value)
            expect and {
                pid == own_hash,
                an == tokens.pfp_validity(),
              }
            trace @"    3. Datum is `PfpDat`"
            expect InlineDatum(d) = cont_datum
            expect _d: t.PfpDat = d
            True
          }
          [] -> fail @"No outputs"
        }
      }
      t.Pfp2Burn -> {
        trace @"**Pfp2Burn**:"
        trace @"1. Own mint has only negative quantities"
        list.all(own_tokens, fn(kv) { kv.2nd < 0 })
      }
    }
  }

  fn three(_dat: t.PfpDat, red: t.Pfp3Red, ctx: ScriptContext) {
    let ScriptContext { transaction, purpose } = ctx
    expect Spend(own_oref) = purpose
    let Transaction { inputs, mint, outputs, .. } = transaction
    let own_hash = u.get_script_hash(own_oref, inputs)
    when red is {
      t.Pfp3Update(auth_idx, cont_idx) -> {
        trace @"**Pfp3Update(`auth_idx`, `cont_idx`)**: "
        trace @"1. Output `auth_idx` is auth output _ie_ contains pfp-auth"
        expect Some(auth_output) = list.at(outputs, auth_idx)
        expect
          value.quantity_of(auth_output.value, own_hash, tokens.pfp_auth()) == 1
        trace @"2. Output `cont_idx` is continuing output"
        expect Some(cont_output) = list.at(outputs, cont_idx)
        let Output {
          address: cont_address,
          value: cont_value,
          datum: cont_datum,
          ..
        } = cont_output
        trace @"    1. Payment address is own"
        expect ScriptCredential(own_hash) == cont_address.payment_credential
        trace @"    2. Value is ada and pfp-validity"
        expect [_, (pid, an, _)] = value.flatten(cont_value)
        expect and {
            pid == own_hash,
            an == tokens.pfp_validity(),
          }
        trace @"    3. Datum is `PfpDat`"
        expect InlineDatum(d) = cont_datum
        expect _d: t.PfpDat = d
        True
      }
      t.Pfp3Close -> {
        trace @"**Pfp3Close**:"
        trace @"1. Own mint value has length 2"
        list.length(
          dict.to_pairs(value.tokens(value.from_minted_value(mint), own_hash)),
        ) == 2
      }
    }
  }
}
