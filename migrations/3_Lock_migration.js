const Lock = artifacts.require("Lock");
const LockToken = artifacts.require("LockToken");

module.exports = function(deployer) {
  deployer.deploy(
      Lock,
      "0x284F214Df3F85526A910979F52C96e54fB228136",
      LockToken.address,
      "1000000000000000000",
      200,
      "10000000000000000"
    );
};
