import { BigNumberish, Contract, ethers, TypedDataDomain, Wallet } from "ethers";
import { TypedDataField } from "@ethersproject/abstract-signer";

export const signPermission = async (
  method: string,
  vault: Contract,
  owner: Wallet,
  delegateAddress: string,
  tokenAddress: string,
  amount: BigNumberish,
  vaultNonce: BigNumberish,
  chainId?: BigNumberish,
) => {
  // craft permission
  const domain: TypedDataDomain = {
    name: "UniversalVault",
    version: "1.0.0",
    chainId: chainId,
    verifyingContract: String(vault.address),
  };
  const types = {} as Record<string, TypedDataField[]>;
  types[method] = [
    { name: "delegate", type: "address" },
    { name: "token", type: "address" },
    { name: "amount", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ];
  const value = {
    delegate: delegateAddress,
    token: tokenAddress,
    amount: amount,
    nonce: vaultNonce,
  };
  // sign permission
  // todo: add fallback if wallet does not support eip 712 rpc
  const signedPermission = await owner.signTypedData(domain, types, value);
  // return
  return signedPermission;
};

export const signPermitEIP2612 = async (
  owner: Wallet,
  token: Contract,
  spenderAddress: string,
  value: BigNumberish,
  deadline: BigNumberish,
  nonce?: BigNumberish,
  chainId?: BigNumberish,
) => {
  // get nonce
  nonce = nonce || (await token.nonces(owner.address));
  // get domain
  const domain: TypedDataDomain = {
    name: "Uniswap V2",
    version: "1",
    chainId: chainId,
    verifyingContract: String(token.address),
  };
  // get types
  const types = {} as Record<string, TypedDataField[]>;
  types["Permit"] = [
    { name: "owner", type: "address" },
    { name: "spender", type: "address" },
    { name: "value", type: "uint256" },
    { name: "nonce", type: "uint256" },
    { name: "deadline", type: "uint256" },
  ];
  // get values
  const values = {
    owner: owner.address,
    spender: spenderAddress,
    value: value,
    nonce: nonce,
    deadline: deadline,
  };
  // sign permission
  // todo: add fallback if wallet does not support eip 712 rpc
  const signedPermission = await owner.signTypedData(domain, types, values);

  const sig = ethers.Signature.from(signedPermission);
  // return
  return [values.owner, values.spender, values.value, values.deadline, sig.v, sig.r, sig.s];
};
