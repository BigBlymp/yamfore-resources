use aiken/bytearray
use aiken/hash
use aiken/list
use aiken/string
use aiken/transaction.{
  Input, NoDatum, Output, OutputReference, Transaction, TransactionId,
  placeholder,
}
use aiken/transaction/credential.{Address, VerificationKeyCredential}
use aiken/transaction/value

pub fn hash32(x: Int) {
  hash.blake2b_256(x |> string.from_int |> string.to_bytearray)
}

pub fn hash28(x: Int) {
  hash32(x) |> bytearray.take(28)
}

pub fn u16(x: Int) {
  x % 65536
}

pub fn output_reference(x: Int) {
  OutputReference(TransactionId(hash32(x)), u16(x))
}

pub fn address(x: Int) {
  Address(VerificationKeyCredential(hash32(x)), None)
}

pub fn value(x: Int) {
  x |> value.from_lovelace
}

pub fn output(x: Int) {
  Output(address(x), value(x + 1), NoDatum, None)
}

pub fn input(x: Int) {
  Input(output_reference(x), output(x + 3))
}

pub fn inputs(x: Int) {
  [0, 23, 34] |> list.map(fn(y) { input(x + y) })
}

pub fn outputs(x: Int) {
  [0, 23, 34] |> list.map(fn(y) { output(x + y) })
}

pub fn transaction(x: Int) {
  Transaction { ..placeholder(), inputs: inputs(x), outputs: outputs(x + 123) }
}
