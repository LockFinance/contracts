const LockToken = artifacts.require("LockToken");

module.exports = function(deployer) {
  deployer.deploy(
      LockToken
    );
};
