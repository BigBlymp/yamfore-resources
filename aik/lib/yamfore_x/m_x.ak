use aiken/fuzz
use aiken/list
use yamfore/functions.{as_usd}
use yamfore/types as t
use yamfore_x/gov_x
use yamfore_x/pf_x

// It's a WIP and trying to navigate the limitation of aiken fuzzing 
// (namely that it is very very slow). 

//
/// This module aims to provide fuzzers to usefully test the main contract. 
pub type BorrowScenario {
  gov_dat: t.GovDat,
  pf_red: t.Pf2Red,
  vaults_in: List<Int>,
  borrow_amount: Int,
}

pub type BorrowTestVec {
  gov_dat: t.GovDat,
  pf_red: t.Pf2Red,
  vaults_in: List<Int>,
  borrow_amount: Int,
  vault_out: Int,
  collateral_amount: Int,
  fee_amount: Int,
}

const bil = 1_000_000_000

pub fn fuzz_borrow() -> Fuzzer<Pair<Int, BorrowTestVec>> {
  fuzz.list_between(fuzz.int_between(1 * bil, 50 * bil), 1, 10)
    |> fuzz.and_then(
        fn(vaults_in) {
          let total = vaults_in |> list.foldl(0, fn(x, y) { x + y })
          fuzz.map4(
            fuzz.int(),
            gov_x.gov_dat(),
            pf_x.pf2red(),
            fuzz.int_between(total - total / list.length(vaults_in) + 1, total),
            fn(x, a, b, c) {
              Pair(x,
              BorrowScenario(a, b, vaults_in, c) |> complete_borrow_scenario)
            },
          )
        },
      )
}

pub fn complete_borrow_scenario(x: BorrowScenario) -> BorrowTestVec {
  let collateral_amount =
    2 * x.borrow_amount * x.pf_red.u_num / x.pf_red.u_denom + 1
  let fee_amount =
    collateral_amount * x.gov_dat.cblp_fee.1st * x.pf_red.c_denom / (
      x.gov_dat.cblp_fee.2nd * x.pf_red.c_num
    ) + 1
  BorrowTestVec {
    gov_dat: x.gov_dat,
    pf_red: x.pf_red,
    vaults_in: x.vaults_in,
    borrow_amount: x.borrow_amount,
    vault_out: x.vaults_in |> list.foldl(-x.borrow_amount, fn(x, y) { x + y }),
    collateral_amount,
    fee_amount,
  }
}

pub fn borrow_test_vector() {
  BorrowScenario(
    t.GovDat((1, 25 * 356 * 24 * 60 * 60 * 1000), (19, 100), (21, 20)),
    t.Pf2Red(5629, 250000, 7, 3),
    [7_000_000_000, 6_000_000_000],
    10_000_000_000,
  )
    |> complete_borrow_scenario
}

test test_complete_borrow_scenario() {
  // EXAMPLE A
  let v =
    BorrowScenario(
      t.GovDat((1, 25 * 356 * 24 * 60 * 60 * 1000), (19, 100), (21, 20)),
      t.Pf2Red(5629, 250000, 7, 3),
      [7_000_000_000, 6_000_000_000],
      10_000_000_000,
    )
      |> complete_borrow_scenario()
  and {
    (v.vault_out == 3_000_000_000)?,
    (v.fee_amount == 393_794_042_758)?,
  }
}

pub type CblpExchangeScenario {
  gov_dat: t.GovDat,
  pf_red: t.Pf2Red,
  vaults_in: List<Int>,
  exchange_amount: Int,
}

pub type CblpExchangeTestVec {
  gov_dat: t.GovDat,
  pf_red: t.Pf2Red,
  vaults_in: List<Int>,
  exchange_amount: Int,
  cblp_out: Int,
  usd_out: Int,
}

pub fn fuzz_exchange() -> Fuzzer<Pair<Int, CblpExchangeTestVec>> {
  fuzz.list_between(fuzz.int_between(1 * bil, 50 * bil), 1, 10)
    |> fuzz.and_then(
        fn(vaults_in) {
          let total = vaults_in |> list.foldl(0, fn(x, y) { x + y })
          fuzz.map4(
            fuzz.int(),
            gov_x.gov_dat(),
            pf_x.pf2red(),
            fuzz.int_between(total - total / list.length(vaults_in) + 1, total),
            fn(x, a, b, c) {
              Pair(x,
              CblpExchangeScenario(a, b, vaults_in, c)
                |> complete_exchange_scenario)
            },
          )
        },
      )
}

pub fn complete_exchange_scenario(
  x: CblpExchangeScenario,
) -> CblpExchangeTestVec {
  let CblpExchangeScenario { gov_dat, pf_red, vaults_in, exchange_amount } = x
  let t.Pf2Red { c_num, c_denom, u_num, u_denom } = pf_red
  let t.GovDat { exchange_reward: (r_num, r_denom), .. } = gov_dat
  let cblp_out = vaults_in |> list.foldl(-exchange_amount, fn(x, y) { x + y })
  let usd_out =
    c_num * r_denom * u_denom * exchange_amount / ( c_denom * r_num * u_num )
  CblpExchangeTestVec {
    gov_dat,
    pf_red,
    vaults_in,
    exchange_amount,
    cblp_out,
    usd_out,
  }
}
