import { ethers, network, upgrades } from "hardhat";
import { writeFileSync } from "fs";
import * as dotenv from "dotenv";

async function main() {
  const SeverBadge = await ethers.getContractFactory("SeverBadge");
  const severBadge = await upgrades.deployProxy(SeverBadge, [], {
    kind: "uups",
  });
  await severBadge.deployed();

  console.log("proxy deployed to:", severBadge.address, "on", network.name);

  const impl = await upgrades.erc1967.getImplementationAddress(severBadge.address);
  console.log("New implementation address:", impl);

  console.log("running post deploy");
  await severBadge._init();

  writeFileSync(`./.${network.name}.env`, `CONTRACT=${severBadge.address}`, "utf-8");
  dotenv.config({ path: `./.${network.name}.env` });
  console.log(process.env.CONTRACT, "added");
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
