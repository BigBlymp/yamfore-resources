use aiken/builtin.{serialise_data}
use aiken/bytearray as ba
use aiken/hash.{blake2b_256}
use aiken/transaction.{OutputReference, TransactionId}
use yamfore/constants.{tag_length}

pub fn validity_pref() -> ByteArray {
  #"000de140"
}

pub fn auth_pref() -> ByteArray {
  #"000643b0"
}

pub fn cblp() -> ByteArray {
  "CBLP"
}

pub fn gov_label() -> ByteArray {
  "gov"
}

pub fn gov_validity() {
  ba.concat(validity_pref(), gov_label())
}

pub fn gov_auth() {
  ba.concat(auth_pref(), gov_label())
}

pub fn usd() -> ByteArray {
  "usd"
}

pub fn pfp_label() -> ByteArray {
  "pfp"
}

pub fn pfp_validity() {
  ba.concat(validity_pref(), pfp_label())
}

pub fn pfp_auth() {
  ba.concat(auth_pref(), pfp_label())
}

pub fn admin() -> ByteArray {
  "admin"
}

pub fn user_label() -> ByteArray {
  "yamfore"
}

pub fn user_validity_pref() {
  ba.concat(validity_pref(), user_label())
}

pub fn user_auth_pref() {
  ba.concat(auth_pref(), user_label())
}

pub fn user_pref_len() {
  ba.length(ba.concat(auth_pref(), user_label()))
}

pub fn user_validity(tag: ByteArray) {
  ba.concat(user_validity_pref(), tag)
}

pub fn user_auth(tag: ByteArray) {
  ba.concat(user_auth_pref(), tag)
}

pub fn get_tag(an: ByteArray) {
  ba.drop(an, user_pref_len())
}

pub fn get_validity_tag(an: ByteArray) {
  expect user_validity_pref() == ba.take(an, user_pref_len())
  get_tag(an)
}

/// Note that tn limits the combined length of label and tag.
pub fn mk_tag(oref: OutputReference) -> ByteArray {
  oref
    |> serialise_data()
    |> blake2b_256()
    |> ba.take(tag_length())
}

test test_mk_tag() {
  let oref = OutputReference {
    transaction_id : TransactionId { hash : #"00000000000000000000000000000000000000000000000000000000"},
    output_index: 0,
  }
  let tag = mk_tag(oref)
  tag == #"6921e91f6af4b4eef9d1a9b55ed75c4e09243b3c"
}
