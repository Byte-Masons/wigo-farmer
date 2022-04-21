async function main() {
  const vaultAddress = '0xc8c53387774A974211CEBAb068d5dd985Ca1369d';
  const strategyAddress = '0xcE106648e37EC4F46D28D3E2b5a8EFd6ab102E1e';

  const Vault = await ethers.getContractFactory('ReaperVaultv1_4');
  const vault = Vault.attach(vaultAddress);

  await vault.initialize(strategyAddress);
  console.log('Vault initialized');
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
