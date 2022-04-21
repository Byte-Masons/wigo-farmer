async function main() {
  const vaultAddress = '0xb8bA5bc5c02Ec8C6a191060F11DFA494f5335e4B';
  const strategyAddress = '0x51CC17E381DafceabA1D532EDe20A30607701db8';

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
