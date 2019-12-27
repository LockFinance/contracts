const Lock = artifacts.require("Lock");

module.exports = function(deployer) {
  deployer.deploy(
      Lock,
      0,
      "0x284F214Df3F85526A910979F52C96e54fB228136",
      ["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"],
      ["25000000000000000"]
    );
};
