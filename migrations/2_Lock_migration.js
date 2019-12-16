const Lock = artifacts.require("Lock");

module.exports = function(deployer) {
  deployer.deploy(
      Lock,
      100,
      "0xBF126c7AAb8aeE364d1B74e37DEF83e80d75B303",
      ["0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE"],
      [0]
    );
};
