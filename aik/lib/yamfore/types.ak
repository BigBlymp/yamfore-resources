use aiken/transaction.{OutputReference}
use aiken/transaction/credential.{Credential}

// PF : PriceFeed - all of them

pub type Pf2Red {
  c_num: Int,
  c_denom: Int,
  u_num: Int,
  u_denom: Int,
}

// PFP : PriceFeedPointer

pub type PfpParams =
  OutputReference

pub type PfpDat =
  Credential

pub type Pfp3Red {
  Pfp3Update(Int, Int)
  Pfp3Close
}

pub type Pfp2Red {
  Pfp2Init
  Pfp2Burn
}

// GOV : Governance 

pub type GovParams =
  OutputReference

pub type GovDat {
  interest_rate: (Int, Int),
  cblp_fee: (Int, Int),
  exchange_reward: (Int, Int),
}

pub type Gov3Red {
  Gov3Update(Int, Int)
  Gov3Close
}

pub type Gov2Red {
  Gov2Init
  Gov2Burn
}

// M : Main 

pub type MParams {
  admin_seed: OutputReference,
  gov_hash: ByteArray,
  pfp_hash: ByteArray,
  cblp_hash: ByteArray,
  usd_hash: ByteArray,
}

pub type M2Red {
  Mint(OutputReference)
  // Tag seed
  Burn
  AdminMint
  AdminBurn
  Withdraw
  Publish
}

pub type M3Red {
  Borrow
  Repay(Int)
  Exchange
}

pub type MDat {
  UsdVault
  CblpVault(Int)
  AdaVault
  Position(PositionP)
}

pub type PositionP {
  created_at: Int,
  borrow_amt: Int,
  interest_rate: (Int, Int),
}
