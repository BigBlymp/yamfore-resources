pub fn as_usd(
  c_num: Int,
  c_denom: Int,
  u_num: Int,
  u_denom: Int,
  ada: Int,
  cblp: Int,
) -> Int {
  ( ada * c_denom + cblp * c_num ) * u_denom / ( u_num * c_denom )
}

pub fn sufficient_collateral(
  u_num: Int,
  u_denom: Int,
  borrowed: Int,
  collateral: Int,
) -> Bool {
  collateral * u_denom >= 2 * u_num * borrowed
}

pub fn sufficient_fee(
  c_num: Int,
  c_denom: Int,
  f_num: Int,
  f_denom: Int,
  collateral: Int,
  fee: Int,
) -> Bool {
  fee * c_num * f_denom >= f_num * collateral * c_denom
}

pub fn sufficient_repay(
  i_num: Int,
  i_denom: Int,
  borrowed: Int,
  duration: Int,
  repay: Int,
) -> Bool {
  repay * i_denom >= ( i_denom + i_num * duration ) * borrowed
}
