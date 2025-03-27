use aiken/bytearray
use aiken/cbor
use aiken/list
use aiken/math
use aiken/pairs
use aiken/transaction.{
  Input, Mint, NoDatum, Output, Spend, Transaction, ValidityRange, WithdrawFrom,
}
use aiken/transaction/credential.{Address, ScriptCredential, StakeCredential}
use aiken/transaction/value.{MintedValue, Value}
use balm/dummy

fn insert(l: List<a>, n: Int, a: a) {
  if n < 1 {
    [a, ..l]
  } else {
    when l is {
      [] ->
        [a]
      [l0, ..rest] ->
        [l0, ..insert(rest, n - 1, a)]
    }
  }
}

pub fn set_validity_range(
  tx: Transaction,
  validity_range: ValidityRange,
) -> Transaction {
  Transaction { ..tx, validity_range: validity_range }
}

pub fn add_withdrawal(
  tx: Transaction,
  credential: StakeCredential,
  amount: Int,
) -> Transaction {
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, amount), ..tx.withdrawals],
  }
}

pub fn add_withdrawal_red(
  tx: Transaction,
  credential: StakeCredential,
  amount: Int,
  red: Data,
) -> Transaction {
  Transaction {
    ..tx,
    withdrawals: [Pair(credential, amount), ..tx.withdrawals],
    redeemers: [Pair(WithdrawFrom(credential), red), ..tx.redeemers],
  }
}

pub fn add_input(tx: Transaction, input: Input) -> Transaction {
  Transaction { ..tx, inputs: [input, ..tx.inputs] }
}

pub fn add_reference_input(tx: Transaction, input: Input) -> Transaction {
  Transaction { ..tx, reference_inputs: [input, ..tx.reference_inputs] }
}

pub fn add_input_red(tx: Transaction, input: Input, red: Data) -> Transaction {
  Transaction {
    ..tx,
    inputs: [input, ..tx.inputs],
    redeemers: [Pair(Spend(input.output_reference), red), ..tx.redeemers],
  }
}

pub fn add_output(tx: Transaction, output: Output) -> Transaction {
  Transaction { ..tx, outputs: tx.outputs |> list.concat([output]) }
}

pub fn insert_output(tx: Transaction, idx: Int, output: Output) -> Transaction {
  Transaction { ..tx, outputs: tx.outputs |> insert(idx, output) }
}

pub fn add_mint(tx: Transaction, val: Value) -> Transaction {
  Transaction {
    ..tx,
    mint: tx.mint
      |> value.from_minted_value()
      |> value.merge(val)
      |> value.to_minted_value(),
  }
}

pub fn add_mint_red(
  tx: Transaction,
  hash: ByteArray,
  tokens: Pairs<ByteArray, Int>,
  red: Data,
) -> Transaction {
  Transaction {
    ..tx,
    mint: tx.mint
      |> value.from_minted_value()
      |> value.merge([Pair(hash, tokens)] |> value.from_asset_list)
      |> value.to_minted_value(),
    redeemers: [Pair(Mint(hash), red), ..tx.redeemers],
  }
}

/// Make transactions more realistic 
pub fn complete_input(input: Input) {
  Input { ..input, output: complete_output(input.output) }
}

pub fn is_non_neg(v: Value) -> Bool {
  v |> value.flatten |> list.all(fn(tup) { tup.3rd > 0 })
}

pub fn complete_output(output: Output) {
  expect output.value |> value.without_lovelace |> is_non_neg
  output |> with_min_ada
}

/// FIXME 
pub fn calc_min_ada(_output: Output) {
  2_000_000
}

pub fn with_min_ada(output: Output) {
  let min_ada = calc_min_ada(output)
  let curr = output.value |> value.lovelace_of()
  if curr >= min_ada {
    output
  } else {
    let nxt = math.max(curr, min_ada)
    Output {
      ..output,
      value: output.value |> value.without_lovelace |> value.add("", "", nxt),
    }
  }
}

pub fn difference(
  inputs: List<Input>,
  mint: MintedValue,
  outputs: List<Output>,
  withdrawals: Pairs<StakeCredential, Int>,
) {
  let in_value =
    inputs
      |> list.foldl(
          value.zero(),
          fn(curr: Input, prev) { prev |> value.merge(curr.output.value) },
        )
  let out_value =
    outputs
      |> list.foldl(
          value.zero(),
          fn(curr: Output, prev) { prev |> value.merge(curr.value) },
        )
  let diff_value =
    in_value
      |> value.merge(mint |> value.from_minted_value)
      |> value.add(
          "",
          "",
          withdrawals |> pairs.values |> list.foldl(0, fn(x, y) { x + y }),
        )
      |> value.merge(out_value |> value.negate)
  diff_value
}

pub fn get_scripts(inputs: List<Input>, mint: MintedValue) {
  let in_scripts =
    inputs
      |> list.filter_map(
          fn(i) {
            when i.output.address.payment_credential is {
              ScriptCredential(h) -> Some(h)
              _ -> None
            }
          },
        )
  let mint_scripts = mint |> value.from_minted_value |> value.policies
  in_scripts |> list.concat(mint_scripts) |> list.unique()
}

// WARNING : This is incomplete and does not follow spec.
// It is simply an attempt to make slightly more realistic test data
pub fn complete(tx: Transaction, change_address: Address) -> Transaction {
  let Transaction { inputs, outputs, mint, reference_inputs, withdrawals, .. } =
    tx
  let reference_inputs = reference_inputs |> list.map(complete_input)
  let inputs = inputs |> list.map(complete_input)
  let outputs = outputs |> list.map(complete_output)
  let diff_value = difference(inputs, mint, outputs, withdrawals)
  expect diff_value |> value.without_lovelace |> is_non_neg

  let diff_rest = diff_value |> value.without_lovelace
  let outputs =
    if diff_rest != value.zero() {
      outputs
        |> list.concat(
            [Output(change_address, diff_value, NoDatum, None) |> with_min_ada],
          )
    } else {
      outputs
    }

  let diff_value = difference(inputs, mint, outputs, withdrawals)
  expect diff_value |> value.without_lovelace |> value.is_zero
  let diff_lvl = diff_value |> value.lovelace_of

  let inputs =
    if diff_lvl >= 0 {
      inputs
    } else {
      [
        Input(
          dummy.output_reference(3),
          Output(dummy.address(4), diff_value, NoDatum, None),
        )
          |> complete_input,
        ..inputs
      ]
    }
  let inputs = inputs |> sort_inputs
  let reference_inputs = reference_inputs |> sort_inputs
  Transaction {
    ..tx,
    inputs: inputs,
    outputs: outputs,
    reference_inputs: reference_inputs,
  }
}

fn sort_inputs(inputs: List<Input>) {
  inputs
    |> list.sort(
        fn(l, r) {
          bytearray.compare(
            l.output_reference |> cbor.serialise,
            r.output_reference |> cbor.serialise,
          )
        },
      )
}
