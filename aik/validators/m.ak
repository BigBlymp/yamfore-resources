use aiken/dict
use aiken/interval.{Finite}
use aiken/list
use aiken/pairs
use aiken/transaction.{
  InlineDatum, Input, Mint, Output, Publish, ScriptContext, ScriptPurpose, Spend,
  Transaction, WithdrawFrom,
}
use aiken/transaction/certificate
use aiken/transaction/credential.{Address, Inline, Pointer, ScriptCredential, VerificationKeyCredential}
use aiken/transaction/value
use yamfore/constants as c
use yamfore/functions as f
use yamfore/tokens
use yamfore/types as t
use aiken/cbor
use aiken/bytearray

fn get_gov_dat(gov_hash: ByteArray, reference_inputs: List<Input>) -> t.GovDat {
  expect Some(input) =
    reference_inputs
      |> list.find(
          fn(i) {
            (
              i.output.value
                |> value.quantity_of(gov_hash, tokens.gov_validity())
            ) == 1
          },
        )
  expect InlineDatum(dat) = input.output.datum
  expect pdat: t.GovDat = dat
  pdat
}

fn get_pf_red(
  pfp_hash: ByteArray,
  reference_inputs: List<Input>,
  redeemers: Pairs<ScriptPurpose, Data>,
) -> t.Pf2Red {
  expect Some(input) =
    reference_inputs
      |> list.find(
          fn(i) {
            (
              i.output.value
                |> value.quantity_of(pfp_hash, tokens.pfp_validity())
            ) == 1
          },
        )
  expect InlineDatum(dat) = input.output.datum
  expect pf_hash: t.PfpDat = dat
  expect Some(pf_red) =
    redeemers |> pairs.get_first(WithdrawFrom(Inline(pf_hash)))
  expect ppf_red: t.Pf2Red = pf_red
  ppf_red
}

validator(params: t.MParams) {
  pub fn three(dat: t.MDat, red: t.M3Red, ctx: ScriptContext) {
    trace @"Three args:"
    let ScriptContext { transaction, purpose } = ctx
    expect Spend(own_oref) = purpose
    trace @"1. Withdraws includes own credential "
    let Transaction {
      inputs,
      mint,
      reference_inputs,
      redeemers,
      validity_range,
      outputs,
      ..
    } = transaction
    expect Some(own_input) =
      list.find(inputs, fn(i) { i.output_reference == own_oref })
    let Output { address: own_address, value: own_value, .. } = own_input.output
    let own_cred = own_address.payment_credential
    expect ScriptCredential(own_hash) = own_cred
    let own_mint =
      dict.to_pairs(value.tokens(value.from_minted_value(mint), own_hash))
    when red is {
      t.Borrow -> {
        trace @"1. When own redeemer is `Borrow`"
        trace @"    1. Own mint value is `[(_, 1), (_, 1)]`"
        expect [Pair(_, 1), Pair(_, 1)] = own_mint
        True
      }
      t.Repay(n_vaults) -> {
        trace @"2. When own redeemer is `Repay(n_vaults)`"
        let t.MParams { usd_hash, .. } = params
        trace @"    1. Own datum is `Position({created_at, borrow_amt, interest_rate})`"
        expect t.Position(t.PositionP {
          created_at,
          borrow_amt,
          interest_rate: (i_num, i_denom),
        }) = dat
        trace @"    2. No other inputs with own payment credential."
        expect
          1 == (
            inputs
              |> list.count(
                  fn(i: Input) {
                    i.output.address.payment_credential == own_cred
                  },
                )
          )
        trace @"    3. Validity has lower bound as `ub`"
        expect Finite(ub) = validity_range.upper_bound.bound_type
        trace @"    4. Calculate duration `duration = ub - created_at`"
        let duration = ub - created_at
        trace @"    5. 0th output is repayment output"
        expect [usd_output, ..rest_outputs] = outputs
        expect Output {
          address: usd_address,
          value: usd_value,
          datum: InlineDatum(usd_idat),
          reference_script: None,
        } = usd_output
        trace @"        1. Address is own address"
        expect usd_address == own_address
        trace @"        2. Value is ada and `repay_amt` of usd"
        expect [_, (usd_hash_, usd_name, repay_amt)] =
          usd_value |> value.flatten()
        expect and {
            usd_hash_ == usd_hash,
            usd_name == tokens.usd(),
          }
        trace @"        3. Datum is `UsdVault`"
        expect usd_dat: t.MDat = usd_idat
        expect t.UsdVault == usd_dat
        trace @"    6. The next `n_vaults - 1` outputs are identical"
        expect
          rest_outputs
            |> list.take(n_vaults - 1)
            |> list.all(fn(o) { o == usd_output })
        trace @"    7. If `n_vaults < max_n_vaults`, then `amt < max_usd_vault_amt`"
        expect
          if n_vaults < c.max_vault_outputs() {
            repay_amt < c.max_usd_vault_amt()
          } else {
            repay_amt >= c.max_usd_vault_amt()
          }
        trace @"    8. `total_repay_amt = n_vaults * repay_amt`"
        let total_repay_amt = n_vaults * repay_amt
        trace @"    9. Verify sufficient repay amount"
        expect
          f.sufficient_repay(
            i_num,
            i_denom,
            borrow_amt,
            duration,
            total_repay_amt,
          )
        trace @"    10. Get own tag `tag`"
        expect [Pair(val_tn, 1)] =
          dict.to_pairs(value.tokens(own_value, own_hash))
        let tag = tokens.get_tag(val_tn)
        trace @"    11. Own mint value is `[(user_auth_<tag>, -1), (user_validity_<tag>, -1)]`"
        expect [Pair(auth_tn, -1), Pair(val_tn_, -1)] = own_mint
        and {
          val_tn == val_tn_,
          auth_tn == tokens.user_auth(tag),
        }
      }
      t.Exchange -> {
        trace @"1. All own spends are `Exchange`, implied by own mint value is empty"
        expect [] = own_mint
        trace @"2. Defer all validation to 0th own spend"
        let own_inputs =
          inputs
            |> list.filter(
                fn(i) { i.output.address.payment_credential == own_cred },
              )
        expect Some(head_input) = own_inputs |> list.at(0)
        if own_oref != head_input.output_reference {
          True
        } else {
          trace @"3. Get gov params from ref inputs via gov token"
          let t.MParams { gov_hash, pfp_hash, usd_hash, cblp_hash, .. } = params
          let t.GovDat { exchange_reward: (r_num, r_denom), .. } =
            get_gov_dat(gov_hash, reference_inputs)
          let own_address = Address(own_cred, Some(Inline(own_cred)))
          trace @"4. Get price feed data"
          let t.Pf2Red { c_num, c_denom, u_num, u_denom } =
            get_pf_red(pfp_hash, reference_inputs, redeemers)
          trace @"5. 0th output is usd vault output"
          expect [usd_output, ..rest_outputs] = outputs
          expect Output {
            address: usd_address,
            value: usd_value,
            datum: InlineDatum(usd_idat),
            reference_script: None,
          } = usd_output
          trace @"    1. Address is own address"
          expect usd_address == own_address
          trace @"    2. Value is ada and `usd_out` "
          expect [_, (usd_hash_, usd_name, usd_out)] =
            usd_value |> value.flatten()
          expect and {
              usd_hash_ == usd_hash,
              usd_name == tokens.usd(),
            }
          trace @"    3. Datum is `UsdVault`"
          expect usd_dat: t.MDat = usd_idat
          expect t.UsdVault == usd_dat
          when dat is {
            t.CblpVault(_) -> {
              trace @"6. If own datum is `CblpVault(_)` then "
              trace @"    1. Validity range has lower bound `lb`"
              expect Finite(lb) = validity_range.lower_bound.bound_type
              trace @"    2. Reduce `own_inputs` to `(total, max)`"
              let (total, count) =
                own_inputs
                  |> list.foldl(
                      (0, 0),
                      fn(i, acc) {
                        expect Output {
                          value: val,
                          datum: InlineDatum(idat),
                          ..
                        } = i.output
                        trace @"        1. All `own_inputs` have datum `CblpVault(from)`"
                        expect t.CblpVault(from): t.MDat = idat
                        trace @"            2. Either `from <= lb`, or admin token is spent"
                        expect or {
                            from <= lb,
                            inputs
                              |> list.any(
                                  fn(i) {
                                    (
                                      i.output.value
                                        |> value.quantity_of(
                                            own_hash,
                                            tokens.admin(),
                                          )
                                    ) == 1
                                  },
                                ),
                          }
                        trace @"        3. All value is ada and `cblp`"
                        expect [_, (cblp_hash_, cblp_name, amt)] =
                          val |> value.flatten()
                        expect and {
                            cblp_hash_ == cblp_hash,
                            cblp_name == tokens.cblp(),
                          }
                        let (acc_0, acc_1) = acc
                        (acc_0 + amt, acc_1 + 1)
                      },
                    )
              trace @"    3. Calculate expected leftover amount `o_expect`"
              let o_expect =
                total - c_denom * r_num * u_num * usd_out / (
                  c_num * r_denom * u_denom
                )
              trace @"    4. If `o_expect <= epsilon`, then return true, else 1st output is leftover output"
              if o_expect <= c.epsilon() {
                True
              } else {
                expect [leftover_output, ..] = rest_outputs
                expect Output {
                  address: leftover_address,
                  value: leftover_value,
                  datum: InlineDatum(leftover_idat),
                  reference_script: None,
                } = leftover_output
                trace @"        1. Address is own address"
                expect leftover_address == own_address
                trace @"        2. Value is at least `o_expect` cblp"
                expect [_, (cblp_hash_, cblp_name, o_actual)] =
                  leftover_value |> value.flatten()
                expect and {
                    (cblp_hash_ == cblp_hash)?,
                    (cblp_name == tokens.cblp())?,
                    (o_actual >= o_expect)?,
                    (o_actual <= total / count)?,
                  }
                trace @"        3. Datum is `CblpVault(0)`"
                expect t.CblpVault(from): t.MDat = leftover_idat
                from == 0
              }
            }
            t.AdaVault -> {
              trace @"7. Else own datum is `AdaVault`"
              trace @"    1. Reduce `own_inputs` to `(total, max)`"
              let (total, count) =
                own_inputs
                  |> list.foldl(
                      (0, 0),
                      fn(i, acc) {
                        expect Output {
                          value: val,
                          datum: InlineDatum(idat),
                          ..
                        } = i.output
                        trace @"        1. All `own_inputs` have datum `AdaVault`"
                        expect t.AdaVault: t.MDat = idat
                        trace @"        2. All value is only ada"
                        expect [(_, _, amt)] = val |> value.flatten()
                        let (acc_0, acc_1) = acc
                        (acc_0 + amt, acc_1 + 1)
                      },
                    )
              trace @"    2. Calculate expected leftover amount `o_expect`"
              let o_expect =
                total - r_num * u_num * usd_out / ( r_denom * u_denom )
              trace @"    3. If `o_expect <= epsilon`, then return true, else 1st output is leftover output"
              if o_expect <= c.epsilon() {
                True
              } else {
                expect [leftover_output, ..] = rest_outputs
                expect Output {
                  address: leftover_address,
                  value: leftover_value,
                  datum: InlineDatum(leftover_idat),
                  reference_script: None,
                } = leftover_output
                trace @"        1. Address is own address"
                expect leftover_address == own_address
                trace @"        2. Value is at least `o_expect` ada"
                expect [(_, _, o_actual)] = leftover_value |> value.flatten()
                expect and {
                    (o_actual >= o_expect)?,
                    (o_actual <= total / count)?,
                  }
                trace @"        3. Datum is `AdaVault`"
                expect t.AdaVault: t.MDat = leftover_idat
                True
              }
            }
            _ -> fail @"bad datum"
          }
        }
      }
    }
  }

  pub fn two(red: t.M2Red, ctx: ScriptContext) {
    let ScriptContext { transaction, purpose } = ctx
    when purpose is {
      Mint(own_hash) -> {
        trace @"Two args, Mint purpose"
        let Transaction {
          inputs,
          mint,
          reference_inputs,
          redeemers,
          validity_range,
          outputs,
          ..
        } = transaction
        let own_tokens =
          dict.to_pairs(value.tokens(value.from_minted_value(mint), own_hash))
        let own_address =
          Address(
            ScriptCredential(own_hash),
            Some(Inline(ScriptCredential(own_hash))),
          )
        when red is {
          t.Mint(seed) -> {
            trace @"1. When own redeemer is `Mint(seed)`"
            let t.MParams { gov_hash, pfp_hash, usd_hash, cblp_hash, .. } =
              params
            trace @"    1. Get gov params from ref inputs via gov token."
            let t.GovDat { cblp_fee: (f_num, f_denom), interest_rate, .. } =
              get_gov_dat(gov_hash, reference_inputs)
            trace @"    2. Get price feed data"
            let t.Pf2Red { u_num, u_denom, c_num, c_denom } =
              get_pf_red(pfp_hash, reference_inputs, redeemers)
            trace @"    3. `seed` is spent"
            expect inputs |> list.any(fn(i) { i.output_reference == seed })
            trace @"    4. Make tag `tag` from `seed`"
            let tag = tokens.mk_tag(seed)
            trace @"    5. Fold over inputs"
            let own_cred = ScriptCredential(own_hash)
            let (count, usd_input_amt) =
              inputs
                |> list.foldl(
                    (0, 0),
                    fn(i, acc) {
                      if i.output.address.payment_credential == own_cred {
                        trace @"        1. Filter own payment credential"
                        let Output { value: val, datum: dat, .. } = i.output
                        trace @"        2. Expect only `UsdVault` datums"
                        expect InlineDatum(dat) = dat
                        expect dat: t.MDat = dat
                        expect dat == t.UsdVault
                        trace @"        3. Aggregate `(count, usd_input_amt)`"
                        let qty = value.quantity_of(val, usd_hash, tokens.usd())
                        (acc.1st + 1, acc.2nd + qty)
                      } else {
                        acc
                      }
                    },
                  )
            trace @"    6. Validity range has lower bound `lb`"
            expect Finite(lb) = validity_range.lower_bound.bound_type
            expect [position_output, fee_output, ..rest_outputs] = outputs
            trace @"    7. 0th output is position "
            expect Output {
              address: position_address,
              value: position_value,
              datum: InlineDatum(position_idat),
              reference_script: None,
            } = position_output
            trace @"        1. Address is own address  "
            expect position_address == own_address
            trace @"        2. Value is `collateral` ada and validity token with tag `tag`"
            expect [(_, _, collateral), (own_hash_, user_validity_, 1)] =
              value.flatten(position_value)
            expect and {
                own_hash_ == own_hash,
                user_validity_ == tokens.user_validity(tag),
              }
            trace @"        3. Datum is `Position({ created_at : lb, interest_rate : gov_dat.interest_rate, borrow_amt })` "
            expect position_dat: t.MDat = position_idat
            expect t.Position(t.PositionP {
              created_at,
              borrow_amt,
              interest_rate: interest_rate_,
            }) = position_dat
            expect interest_rate_ == interest_rate
            expect created_at == lb
            trace @"        4. Verify sufficient collateral"
            expect
              f.sufficient_collateral(u_num, u_denom, borrow_amt, collateral)
            trace @"    8. 1st output is fee output "
            expect Output {
              address: fee_address,
              value: fee_value,
              datum: InlineDatum(fee_idat),
              reference_script: None,
            } = fee_output
            trace @"        1. Address is own address"
            expect fee_address == own_address
            trace @"        2. Value is ada and `fee_amt` cblp"
            expect [_, (cblp_hash_, cblp_name, fee_amt)] =
              value.flatten(fee_value)
            expect and {
                cblp_hash_ == cblp_hash,
                cblp_name == tokens.cblp(),
              }
            trace @"        3. Datum is `CblpVault(lb)`"
            expect fee_dat: t.MDat = fee_idat
            expect t.CblpVault(available_from) = fee_dat
            expect available_from == created_at
            trace @"        4. Verify sufficient fee"
            expect
              f.sufficient_fee(
                c_num,
                c_denom,
                f_num,
                f_denom,
                collateral,
                fee_amt,
              )
            trace @"    9. If `usd_input_amt > borrow_amt` then, next output is usd vault output"
            expect
              if usd_input_amt <= borrow_amt {
                True
              } else {
                expect [usd_output, ..] = rest_outputs
                expect Output {
                  address: usd_address,
                  value: usd_value,
                  datum: InlineDatum(usd_idat),
                  reference_script: None,
                } = usd_output
                trace @"        1. Address is own address"
                expect usd_address == own_address
                trace @"        2. Value is ada and `usd_output_amt` usd. "
                expect [_, (usd_hash_, usd_name_, usd_output_amt)] =
                  value.flatten(usd_value)
                expect and {
                    usd_hash_ == usd_hash,
                    usd_name_ == tokens.usd(),
                    usd_output_amt >= usd_input_amt - borrow_amt,
                  }
                trace @"        3. Datum is `UsdVault`"
                expect usd_dat: t.MDat = usd_idat
                expect t.UsdVault == usd_dat
                trace @"        4. No redundant inputs `usd_output_amt <= usd_input_amt / count`"
                usd_output_amt <= usd_input_amt / count
              }
            trace @"    10. Own mint value is `[(user_auth_<tag>, 1), (user_validity_<tag>, 1)]`"
            expect [Pair(user_auth_, 1), Pair(user_validity_, 1)] = own_tokens
            and {
              user_auth_ == tokens.user_auth(tag),
              user_validity_ == tokens.user_validity(tag),
            }
          }
          t.Burn -> {
            trace @"2. When own redeemer is `Burn`:"
            trace @"    1. Own mint value is of the form `[(user_auth_<tag>, -1), (user_validity_<tag>, -1)]`"
            expect [Pair(user_auth, -1), Pair(user_validity, -1)] = own_tokens
            let user_tag = tokens.get_tag(user_auth)
            let val_tag = tokens.get_validity_tag(user_validity)
            user_tag == val_tag
          }
          t.AdminMint -> {
            trace @"3. When own redeemer is `AdminMint`"
            trace @"    1. `params.admin_seed` is spent"
            expect
              inputs
                |> list.any(fn(i) { i.output_reference == params.admin_seed })
            trace @"    2. Own mint value is `[(admin, 1)]`"
            expect [Pair(admin_auth, 1)] = own_tokens
            admin_auth == tokens.admin()
          }
          t.AdminBurn -> {
            trace @"4. When own redeemer is `AdminBurn`"
            trace @"    1. Own mint value is `[(admin, -1)]`"
            expect [Pair(admin_auth, -1)] = own_tokens
            admin_auth == tokens.admin()
          }
          _ -> {
            trace @"5. Otherwise fail"
            False
          }
        }
      }
      WithdrawFrom(own_stake) -> {
        trace @"Two Args - Withdraw purpose "
        let Transaction { outputs, withdrawals, .. } = transaction
        expect Inline(ScriptCredential(own_hash)) = own_stake
        let own_address = Address(ScriptCredential(own_hash), Some(own_stake))
        trace @"1. Redeemer is `Withdraw` (else fail)"
        expect t.Withdraw == red
        trace @"2. Own withdraw amount is `amt` "
        expect Some(amt) = withdrawals |> pairs.get_first(own_stake)
        expect [vault_output, ..] = outputs
        trace @"3. 0th output is ada vault output"
        expect Output {
          address: vault_address,
          value: vault_value,
          datum: InlineDatum(vault_idat),
          reference_script: None,
        } = vault_output
        trace @"    1. Address is own address"
        expect vault_address == own_address
        trace @"    2. Value is ada of at least `amt`"
        expect [(_, _, vault_amt)] = vault_value |> value.flatten()
        expect vault_amt >= amt
        trace @"    3. Datum is `AdaVault`"
        expect vault_dat: t.MDat = vault_idat
        expect t.AdaVault = vault_dat
        True
      }
      Publish(pub_inner) -> {
        trace @"Two Args - Publish purpose"
        expect Inline(ScriptCredential(own_hash)) =
          when pub_inner is {
            certificate.CredentialRegistration(delegator) -> {
              trace @"reg"
              delegator
            }
            certificate.CredentialDeregistration(delegator) -> { 
              trace @"dereg"
              delegator
            }
            certificate.CredentialDelegation { delegator, .. } -> {
              trace @"deleg"
              let true = when delegator is {
                Inline(VerificationKeyCredential(_hash)) -> {
                  fail @"vkey"
                }
                Pointer(_,_,_) -> {
                  fail @"pointer"
                }
                Inline(ScriptCredential(_hash)) -> {
                  trace @"script"
                  True
                }
              }
              expect true == True
              delegator
            } 
            _ -> {
              fail @"Bad cred"
              }
          }
        trace @"1. Redeemer is `Publish` (else fail)"
        expect t.Publish == red
        trace @"2. Input contains own admin token "
        transaction.inputs
          |> list.any(
              fn(i) {
                (
                  i.output.value
                    |> value.quantity_of(own_hash, tokens.admin())
                ) == 1
              },
            )
      }
      _ -> fail @"Bad purpose"
    }
  }
}
