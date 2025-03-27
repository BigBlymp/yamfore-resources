use aiken/fuzz
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, ScriptContext, Spend,
}
use aiken/transaction/credential.{
  Address, ScriptCredential, VerificationKeyCredential,
}
use aiken/transaction/value
use balm/dummy
use balm/tx.{add_input, add_input_red, add_mint_red, complete, insert_output}
use gov.{three, two}
use yamfore/tokens
use yamfore/types as t

test test_init(x via fuzz.int()) {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(0)
  let base = dummy.transaction(x + 3)
  let red = t.Gov2Init
  two(
    seed,
    red,
    ScriptContext(
      base
        |> add_input(Input(seed, dummy.output(x + 12)))
        |> add_mint_red(own_hash, twin_tokens(), red)
        |> insert_output(0, state(own_hash, a_datum(x + 785)))
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_init_without_seed(x via fuzz.int()) fail {
  let seed = dummy.output_reference(x + 999)
  let own_hash = dummy.hash28(0)
  let base = dummy.transaction(x + 3)
  let red = t.Gov2Init
  two(
    seed,
    red,
    ScriptContext(
      base // |> add_input( Input(seed, dummy.output(x)))
        |> add_mint_red(own_hash, twin_tokens(), red)
        |> insert_output(0, state(own_hash, a_datum(x + 785)))
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_init_without_cont(x via fuzz.int()) fail {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(0)
  let base = dummy.transaction(x + 3)
  let red = t.Gov2Init
  two(
    seed,
    red,
    ScriptContext(
      base
        |> add_input(Input(seed, dummy.output(x + 12)))
        |> add_mint_red(own_hash, twin_tokens(), red) // |> insert_output(0, state(own_hash, t.GovDat((1, 1), (1, 1), (1, 1))))
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_update(x via fuzz.int()) {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(x + 847)
  let own_oref = dummy.output_reference(x + 3)
  let base = dummy.transaction(x + 5)
  let dat = a_datum(x + 645)
  let red = t.Gov3Update(0, 1)
  three(
    seed,
    dat,
    red,
    ScriptContext(
      base
        |> add_input(Input(dummy.output_reference(x + 123), auth_output(own_hash)))
        |> add_input_red(Input(own_oref, state(own_hash, dat)), red)
        |> insert_output(0, auth_output(own_hash))
        |> insert_output(1, state(own_hash, a_datum(x + 785)))
        |> complete(dummy.address(x)),
      Spend(own_oref),
    ),
  )
}

test test_fail_update_without_auth(x via fuzz.int()) fail {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(x + 847)
  let own_oref = dummy.output_reference(x + 3)
  let base = dummy.transaction(x + 5)
  let dat = a_datum(x + 645)
  let red = t.Gov3Update(0, 1)
  three(
    seed,
    dat,
    red,
    ScriptContext(
      base // |> add_input(Input(dummy.output_reference(x + 123), auth_output(own_hash)))
        |> add_input_red(Input(own_oref, state(own_hash, dat)), red) // |> insert_output(0, auth_output(own_hash))
        |> insert_output(1, state(own_hash, a_datum(x + 785)))
        |> complete(dummy.address(x)),
      Spend(own_oref),
    ),
  )
}

test test_fail_update_without_cont(x via fuzz.int()) fail {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(x + 847)
  let own_oref = dummy.output_reference(x + 3)
  let base = dummy.transaction(x + 5)
  let dat = a_datum(x + 645)
  let red = t.Gov3Update(0, 1)
  three(
    seed,
    dat,
    red,
    ScriptContext(
      base
        |> add_input(Input(dummy.output_reference(x + 123), auth_output(own_hash)))
        |> add_input_red(Input(own_oref, state(own_hash, dat)), red)
        |> insert_output(0, auth_output(own_hash)) // |> insert_output(1, state(own_hash, t.GovDat((1, 1), (1, 1), (1, 1))))
        |> complete(dummy.address(x)),
      Spend(own_oref),
    ),
  )
}

test test_end(x via fuzz.int()) {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(x + 847)
  let own_oref = dummy.output_reference(x + 3)
  let base = dummy.transaction(x + 5)
  let dat = a_datum(x + 645)
  let red2 = t.Gov2Burn
  let red3 = t.Gov3Close
  let tx =
    base
      |> add_input(Input(dummy.output_reference(x + 123), auth_output(own_hash)))
      |> add_input_red(Input(own_oref, state(own_hash, dat)), red3)
      |> add_mint_red(own_hash, twin_tokens_negative(), red2)
      |> complete(dummy.address(x))

  and {
    three(seed, dat, red3, ScriptContext(tx, Spend(own_oref))),
    two(seed, red2, ScriptContext(tx, Mint(own_hash))),
  }
}

test test_fail_end_without_burn(x via fuzz.int()) fail {
  let seed = dummy.output_reference(x)
  let own_hash = dummy.hash28(x + 847)
  let own_oref = dummy.output_reference(x + 3)
  let base = dummy.transaction(x + 5)
  let dat = a_datum(x + 645)
  let red2 = t.Gov2Burn
  let red3 = t.Gov3Close
  let tx =
    base
      |> add_input(Input(dummy.output_reference(x + 123), auth_output(own_hash)))
      |> add_input_red(Input(own_oref, state(own_hash, dat)), red3) // |> add_mint_red(own_hash, twin_tokens_negative(), red2)
      |> complete(dummy.address(x))

  and {
    three(seed, dat, red3, ScriptContext(tx, Spend(own_oref))),
    two(seed, red2, ScriptContext(tx, Mint(own_hash))),
  }
}

fn a_datum(x: Int) {
  t.GovDat((x, 3), (x, 5), (x, 1))
}

fn twin_tokens_negative() {
  [Pair(tokens.gov_auth(), -1), Pair(tokens.gov_validity(), -1)]
}

fn twin_tokens() {
  [Pair(tokens.gov_auth(), 1), Pair(tokens.gov_validity(), 1)]
}

fn state(own_hash, dat: t.GovDat) {
  Output(
    Address(ScriptCredential(own_hash), None),
    value.from_asset_list(
      [
        Pair("", [Pair("", 1)]),
        Pair(own_hash, [Pair(tokens.gov_validity(), 1)]),
      ],
    ),
    InlineDatum(dat),
    None,
  )
}

fn auth_output(own_hash) {
  Output(
    Address(VerificationKeyCredential(own_hash), None),
    value.from_asset_list(
      [Pair("", [Pair("", 1)]), Pair(own_hash, [Pair(tokens.gov_auth(), 1)])],
    ),
    NoDatum,
    None,
  )
}
