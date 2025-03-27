use aiken/cbor
use aiken/fuzz
use aiken/interval
use aiken/list
use aiken/transaction.{
  InlineDatum, Input, Mint, NoDatum, Output, ScriptContext, Spend,
}
use aiken/transaction/credential.{Address, Credential, Inline, ScriptCredential}
use aiken/transaction/value
use balm/dummy
use balm/tx.{
  add_input, add_input_red, add_mint_red, add_reference_input,
  add_withdrawal_red, complete, insert_output, set_validity_range,
}
use m.{three, two}
use yamfore/tokens
use yamfore/types as t
use yamfore_x/m_x.{borrow_test_vector, fuzz_borrow, fuzz_exchange}

// It uses the fairly new fuzzer. 
// However, shrinking is painfully slow, so we have some substitute in poor-man fuzzing. 
// It is opaque as to what kind of test coverage we are getting here, 
// or how reflective this is of real world inputs.
//
// Currently, the amount of code required to construct the tests
// detracts from the clarity with which we'd like them to communicate.

/// These tests are a WIP. 
fn params(x: Int) {
  t.MParams {
    admin_seed: dummy.output_reference(x + 889),
    gov_hash: dummy.hash28(x + 400),
    pfp_hash: dummy.hash28(x + 410),
    cblp_hash: dummy.hash28(x + 420),
    usd_hash: dummy.hash28(x + 430),
  }
}

test test_admin_mint(x via fuzz.int()) {
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)
  let red = t.AdminMint
  two(
    p,
    red,
    ScriptContext(
      base
        |> add_input(Input(p.admin_seed, dummy.output(x + 12)))
        |> add_mint_red(own_hash, [Pair(tokens.admin(), 1)], red)
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_fail_admin_mint_without_seed(x via fuzz.int()) fail {
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)
  let red = t.AdminMint
  two(
    p,
    red,
    ScriptContext(
      base // |> add_input(Input(p.admin_seed, dummy.output(x+12)))
        |> add_mint_red(own_hash, [Pair(tokens.admin(), 1)], red)
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

fn admin_output(x: Int, own_hash: ByteArray) {
  Output(
    dummy.address(x),
    [Pair(own_hash, [Pair(tokens.admin(), 1)])]
      |> value.from_asset_list,
    NoDatum,
    None,
  )
}

test test_admin_close(x via fuzz.int()) {
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)
  let red = t.AdminBurn
  two(
    p,
    red,
    ScriptContext(
      base
        |> add_input(
            Input(
              dummy.output_reference(x + 232),
              admin_output(x + 77, own_hash),
            ),
          )
        |> add_mint_red(own_hash, [Pair(tokens.admin(), -1)], red)
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_fail_admin_close_mint(x via fuzz.int()) fail {
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)
  let red = t.AdminBurn
  two(
    p,
    red,
    ScriptContext(
      base
        |> add_input(
            Input(
              dummy.output_reference(x + 232),
              admin_output(x + 77, own_hash),
            ),
          )
        |> add_mint_red(own_hash, [Pair(tokens.admin(), 1)], red)
        |> complete(dummy.address(x)),
      Mint(own_hash),
    ),
  )
}

test test_m_borrow(f via fuzz_borrow()) {
  let Pair(x, v) = f
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)

  // GOV
  let gov_script = reference_input_script(x + 123, p.gov_hash)
  let gov_ref =
    Input(dummy.output_reference(x + 88), gov_output(p.gov_hash, v.gov_dat))

  // PF
  let pf_cred = ScriptCredential(dummy.hash28(x + 654))
  let pfp_script = reference_input_script(x + 666, p.pfp_hash)
  let pfp_ref =
    Input(dummy.output_reference(x + 936), pfp_output(p.pfp_hash, pf_cred))

  // USER 
  let seed = dummy.output_reference(x + 7)
  let own_tag = tokens.mk_tag(seed)
  let position_value =
    value.from_lovelace(v.collateral_amount)
      |> value.add(own_hash, tokens.user_validity(own_tag), 1)
  let position_dat =
    t.Position(t.PositionP(0, v.borrow_amount, v.gov_dat.interest_rate))
  let position_output = m_output(own_hash, position_value, position_dat)

  let vaults_in =
    v.vaults_in
      |> list.map(
          fn(amount) {
            Input(
              dummy.output_reference(x + amount),
              usd_vault_output(own_hash, p.usd_hash, amount),
            )
          },
        )

  let vault_output = usd_vault_output(own_hash, p.usd_hash, v.vault_out)

  let fee_output = fee_output(own_hash, p.cblp_hash, v.fee_amount, 0)
  let fee_input = fee_input(x, p.cblp_hash, v.fee_amount)
  let twins =
    [Pair(tokens.user_auth(own_tag), 1), Pair(tokens.user_validity(own_tag), 1)]
  let validity_range = range(0, 10000)
  let tx =
    base
      |> add_input(Input(seed, dummy.output(x + 12)))
      |> add_input(fee_input)
      |> add_reference_input(gov_script)
      |> add_reference_input(gov_ref)
      |> add_reference_input(pfp_script)
      |> add_reference_input(pfp_ref)
      |> add_withdrawal_red(Inline(pf_cred), 0, v.pf_red)
      |> add_mint_red(own_hash, twins, t.Mint(seed))
      |> set_validity_range(validity_range)
      |> insert_output(0, position_output)
      |> insert_output(1, fee_output)
      |> insert_output(2, vault_output)
  let tx =
    vaults_in
      |> list.foldl(tx, fn(vault, tx) { tx |> add_input_red(vault, t.Borrow) })
  let tx = tx |> complete(dummy.address(x))
  and {
    two(p, t.Mint(seed), ScriptContext(tx, Mint(own_hash))),
    vaults_in
      |> list.all(
          fn(vault) {
            three(
              p,
              t.UsdVault,
              t.Borrow,
              ScriptContext(tx, Spend(vault.output_reference)),
            )
          },
        ),
  }
}

test test_m_repay(x via fuzz.int()) {
  let p = params(x + 23)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 3)
  let v = borrow_test_vector()

  let borrow_amount = 10_000_000_000
  let duration = 600 * 24 * 60 * 60 * 1000
  let created_at = 0
  let now = created_at + duration
  let interest_rate = (1, 25 * 356 * 24 * 60 * 60 * 1000)
  let repay_amount =
    ( interest_rate.2nd + duration * interest_rate.1st ) * borrow_amount / interest_rate.2nd + 1
  trace cbor.diagnostic(repay_amount / borrow_amount)

  // USER 
  let seed = dummy.output_reference(x + 7)
  let own_tag = tokens.mk_tag(seed)
  let position_value =
    value.from_lovelace(v.collateral_amount)
      |> value.add(own_hash, tokens.user_validity(own_tag), 1)
  let position_dat =
    t.Position(
      t.PositionP(created_at, v.borrow_amount, v.gov_dat.interest_rate),
    )
  let position_output = m_output(own_hash, position_value, position_dat)
  let position_input = Input(dummy.output_reference(x + 8394), position_output)

  let repay_output =
    usd_vault_output(own_hash, p.usd_hash, repay_amount / 2 + 1)

  let twins =
    [
      Pair(tokens.user_auth(own_tag), -1),
      Pair(tokens.user_validity(own_tag), -1),
    ]
  let validity_range = range(now - 10000, now)
  let tx =
    base
      |> add_mint_red(own_hash, twins, t.Burn)
      |> set_validity_range(validity_range)
      |> add_input(
          Input(
            dummy.output_reference(x + 8374),
            Output(
              dummy.address(x + 654),
              value.from_asset(p.usd_hash, tokens.usd(), repay_amount + 2)
                |> value.add(own_hash, tokens.user_auth(own_tag), 1),
              NoDatum,
              None,
            ),
          ),
        )
      |> add_input(position_input)
      |> insert_output(0, repay_output)
      |> insert_output(1, repay_output)
  let tx = tx |> complete(dummy.address(x))
  and {
    two(p, t.Burn, ScriptContext(tx, Mint(own_hash))),
    three(
      p,
      position_dat,
      t.Repay(2),
      ScriptContext(tx, Spend(position_input.output_reference)),
    ),
  }
}

test test_m_exchange_cblp(f via fuzz_exchange()) {
  let Pair(x, v) = f
  let p = params(x + 99)
  let own_hash = dummy.hash28(x + 345)
  let base = dummy.transaction(x + 13)

  let now = 1_716_193_037_000
  let available_from = 1_716_193_037_000 - 30_000

  // GOV
  let gov_script = reference_input_script(x + 123, p.gov_hash)
  let gov_ref =
    Input(dummy.output_reference(x + 88), gov_output(p.gov_hash, v.gov_dat))

  // PF
  let pf_cred = ScriptCredential(dummy.hash28(x + 654))
  let pfp_script = reference_input_script(x + 666, p.pfp_hash)
  let pfp_ref =
    Input(dummy.output_reference(x + 936), pfp_output(p.pfp_hash, pf_cred))

  // M
  let vaults_in =
    v.vaults_in
      |> list.map(
          fn(amount) {
            Input(
              dummy.output_reference(x + amount),
              cblp_vault_output(own_hash, p.cblp_hash, amount, available_from),
            )
          },
        )

  let cblp_output = cblp_vault_output(own_hash, p.cblp_hash, v.cblp_out, 0)
  let usd_output = usd_vault_output(own_hash, p.usd_hash, v.usd_out + 1)

  // USER 
  let user_input_0 =
    Input(
      dummy.output_reference(x + 8394),
      Output(
        dummy.address(x + 823),
        value.from_asset(p.usd_hash, tokens.usd(), v.usd_out / 2)
          |> value.add("", "", 2_000_000),
        NoDatum,
        None,
      ),
    )
  let user_input_1 =
    Input(
      dummy.output_reference(x + 8794),
      Output(
        dummy.address(x + 823),
        value.from_asset(p.usd_hash, tokens.usd(), v.usd_out / 2 + 1_000_000)
          |> value.add("", "", 2_000_000),
        NoDatum,
        None,
      ),
    )

  let validity_range = range(now, now + 10000)
  let tx =
    base
      |> set_validity_range(validity_range)
      |> add_input(user_input_0)
      |> add_input(user_input_1)
      |> add_reference_input(gov_script)
      |> add_reference_input(gov_ref)
      |> add_reference_input(pfp_script)
      |> add_reference_input(pfp_ref)
      |> add_withdrawal_red(Inline(pf_cred), 0, v.pf_red)
      |> insert_output(0, usd_output)
      |> insert_output(1, cblp_output)
  let tx =
    vaults_in
      |> list.foldl(tx, fn(vault, tx) { tx |> add_input_red(vault, t.Exchange) })
  let tx = tx |> complete(dummy.address(x))
  vaults_in
    |> list.all(
        fn(vault) {
          expect InlineDatum(d) = vault.output.datum
          expect dat: t.MDat = d
          three(
            p,
            dat,
            t.Exchange,
            ScriptContext(tx, Spend(vault.output_reference)),
          )
        },
      )
}

fn fee_input(x: Int, cblp_hash: ByteArray, amount: Int) {
  Input(
    dummy.output_reference(x + 8983),
    Output(
      dummy.address(x + 562),
      value.from_asset(cblp_hash, tokens.cblp(), amount),
      NoDatum,
      None,
    ),
  )
}

fn fee_output(
  m_hash: ByteArray,
  cblp_hash: ByteArray,
  amount: Int,
  created_at: Int,
) {
  m_output(
    m_hash,
    value.from_asset(cblp_hash, tokens.cblp(), amount),
    t.CblpVault(created_at),
  )
}

fn usd_vault_output(m_hash: ByteArray, usd_hash: ByteArray, amount: Int) {
  m_output(m_hash, value.from_asset(usd_hash, tokens.usd(), amount), t.UsdVault)
}

fn cblp_vault_output(
  m_hash: ByteArray,
  cblp_hash: ByteArray,
  amount: Int,
  from: Int,
) {
  m_output(
    m_hash,
    value.from_asset(cblp_hash, tokens.cblp(), amount),
    t.CblpVault(from),
  )
}

fn m_address(m_hash: ByteArray) {
  let cred = ScriptCredential(m_hash)
  Address(cred, Some(Inline(cred)))
}

fn m_output(m_hash: ByteArray, value: value.Value, dat: t.MDat) {
  Output(m_address(m_hash), value, InlineDatum(dat), None)
}

fn range(lb: Int, ub: Int) {
  interval.Interval(
    interval.IntervalBound(interval.Finite(lb), True),
    interval.IntervalBound(interval.Finite(ub), True),
  )
}

fn reference_input_script(x: Int, hash: ByteArray) {
  Input(
    dummy.output_reference(x),
    Output(dummy.address(x + 765), value.zero(), NoDatum, Some(hash)),
  )
}

fn gov_output(gov_hash, gov_dat) {
  Output(
    Address(ScriptCredential(gov_hash), None),
    value.from_asset_list([Pair(gov_hash, [Pair(tokens.gov_validity(), 1)])]),
    InlineDatum(gov_dat),
    None,
  )
}

fn pfp_output(pfp_hash: ByteArray, pf_cred: Credential) {
  Output(
    Address(ScriptCredential(pfp_hash), None),
    value.from_asset_list([Pair(pfp_hash, [Pair(tokens.pfp_validity(), 1)])]),
    InlineDatum(pf_cred),
    None,
  )
}
