async function main() {
  const vaultAddress = '0x220EF595e18465410C5b5C9CeD6DD88a44F14289';
  const strategyAddress = '0xbB907e1E5f5FadaaE2E1A81fA064700897C8B8DB';

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
