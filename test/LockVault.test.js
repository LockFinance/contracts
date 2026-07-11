const { expect } = require("chai");
const { ethers } = require("hardhat");
const { loadFixture, time } = require("@nomicfoundation/hardhat-toolbox/network-helpers");

const ETH = ethers.ZeroAddress;
const DAY = 24 * 60 * 60;
const YEAR = 365 * DAY;

describe("LockVault", function () {
  async function deployFixture() {
    const [owner, feeRecipient, alice, bob, carol] = await ethers.getSigners();

    const LockVault = await ethers.getContractFactory("LockVault");
    // 50 bps = 0.5% fee
    const vault = await LockVault.deploy(owner.address, feeRecipient.address, 50);

    const MockERC20 = await ethers.getContractFactory("MockERC20");
    const token = await MockERC20.deploy("Test Token", "TT", 18);
    await token.mint(alice.address, ethers.parseEther("1000000"));
    await token.connect(alice).approve(vault.target, ethers.MaxUint256);

    return { vault, token, owner, feeRecipient, alice, bob, carol };
  }

  async function lockedFixture() {
    const ctx = await deployFixture();
    const now = await time.latest();
    const unlockAt = now + 30 * DAY;
    const amount = ethers.parseEther("1000");
    await ctx.vault.connect(ctx.alice).lock(ctx.token.target, amount, unlockAt, ctx.alice.address);
    return { ...ctx, id: 1n, unlockAt, amount, net: (amount * 9950n) / 10000n };
  }

  describe("deployment", function () {
    it("rejects fee above the hard cap", async function () {
      const [owner, feeRecipient] = await ethers.getSigners();
      const LockVault = await ethers.getContractFactory("LockVault");
      await expect(LockVault.deploy(owner.address, feeRecipient.address, 101))
        .to.be.revertedWithCustomError(LockVault, "FeeTooHigh");
    });

    it("rejects zero fee recipient", async function () {
      const [owner] = await ethers.getSigners();
      const LockVault = await ethers.getContractFactory("LockVault");
      await expect(LockVault.deploy(owner.address, ethers.ZeroAddress, 0))
        .to.be.revertedWithCustomError(LockVault, "ZeroAddress");
    });
  });

  describe("lock (time-lock)", function () {
    it("locks ERC-20, mints NFT, takes fee, records position", async function () {
      const { vault, token, feeRecipient, alice, bob } = await loadFixture(deployFixture);
      const now = await time.latest();
      const unlockAt = now + 30 * DAY;
      const amount = ethers.parseEther("1000");
      const fee = (amount * 50n) / 10000n;
      const net = amount - fee;

      await expect(vault.connect(alice).lock(token.target, amount, unlockAt, bob.address))
        .to.emit(vault, "Locked")
        .withArgs(1n, token.target, bob.address, alice.address, net, fee, unlockAt, unlockAt, unlockAt);

      expect(await vault.ownerOf(1)).to.equal(bob.address);
      expect(await token.balanceOf(vault.target)).to.equal(net);
      expect(await token.balanceOf(feeRecipient.address)).to.equal(fee);
      expect(await vault.totalLocked(token.target)).to.equal(net);

      const p = await vault.getPosition(1);
      expect(p.token).to.equal(token.target);
      expect(p.amount).to.equal(net);
      expect(p.claimed).to.equal(0n);
      expect(p.start).to.equal(unlockAt);
      expect(p.cliff).to.equal(unlockAt);
      expect(p.end).to.equal(unlockAt);
    });

    it("locks native ETH with exact msg.value", async function () {
      const { vault, alice, bob } = await loadFixture(deployFixture);
      const now = await time.latest();
      const amount = ethers.parseEther("5");

      await vault.connect(alice).lock(ETH, amount, now + DAY, bob.address, { value: amount });
      expect(await ethers.provider.getBalance(vault.target)).to.equal((amount * 9950n) / 10000n);

      await expect(
        vault.connect(alice).lock(ETH, amount, now + DAY, bob.address, { value: amount - 1n })
      ).to.be.revertedWithCustomError(vault, "WrongMsgValue");
      await expect(
        vault.connect(alice).lock(ETH, amount, now + DAY, bob.address, { value: amount + 1n })
      ).to.be.revertedWithCustomError(vault, "WrongMsgValue");
    });

    it("rejects sending ETH alongside an ERC-20 lock", async function () {
      const { vault, token, alice } = await loadFixture(deployFixture);
      const now = await time.latest();
      await expect(
        vault.connect(alice).lock(token.target, 1000n, now + DAY, alice.address, { value: 1n })
      ).to.be.revertedWithCustomError(vault, "WrongMsgValue");
    });

    it("validates inputs", async function () {
      const { vault, token, alice } = await loadFixture(deployFixture);
      const now = await time.latest();

      await expect(vault.connect(alice).lock(token.target, 0, now + DAY, alice.address))
        .to.be.revertedWithCustomError(vault, "ZeroAmount");
      await expect(vault.connect(alice).lock(token.target, 1000n, now + DAY, ethers.ZeroAddress))
        .to.be.revertedWithCustomError(vault, "ZeroAddress");
      await expect(vault.connect(alice).lock(token.target, 1000n, now - 1, alice.address))
        .to.be.revertedWithCustomError(vault, "InvalidSchedule");
    });

    it("caps the lock duration", async function () {
      const { vault, token, alice } = await loadFixture(deployFixture);
      const now = await time.latest();
      await expect(
        vault.connect(alice).lock(token.target, 1000n, now + 101 * YEAR, alice.address)
      ).to.be.revertedWithCustomError(vault, "DurationTooLong");
      // 99 years is fine
      await vault.connect(alice).lock(token.target, 1000n, now + 99 * YEAR, alice.address);
    });

    it("records net received for fee-on-transfer tokens", async function () {
      const { vault, alice } = await loadFixture(deployFixture);
      const FeeToken = await ethers.getContractFactory("MockFeeOnTransferToken");
      const feeToken = await FeeToken.deploy(200); // 2% burn on transfer
      await feeToken.mint(alice.address, ethers.parseEther("1000"));
      await feeToken.connect(alice).approve(vault.target, ethers.MaxUint256);

      const now = await time.latest();
      const amount = ethers.parseEther("100");
      await vault.connect(alice).lock(feeToken.target, amount, now + DAY, alice.address);

      const received = (amount * 9800n) / 10000n; // after transfer burn
      const net = received - (received * 50n) / 10000n; // after protocol fee
      const p = await vault.getPosition(1);
      expect(p.amount).to.equal(net);
      // vault really holds enough to pay the position (fee transfer burned a bit
      // of the fee recipient's share, not the vault's)
      expect(await feeToken.balanceOf(vault.target)).to.be.gte(p.amount);
    });
  });

  describe("claiming", function () {
    it("cannot claim before unlock, claims all after", async function () {
      const { vault, token, alice, id, unlockAt, net } = await loadFixture(lockedFixture);

      expect(await vault.claimable(id)).to.equal(0n);
      await expect(vault.connect(alice).claim(id)).to.be.revertedWithCustomError(vault, "NothingToClaim");

      await time.increaseTo(unlockAt);
      expect(await vault.claimable(id)).to.equal(net);

      const before = await token.balanceOf(alice.address);
      await expect(vault.connect(alice).claim(id))
        .to.emit(vault, "Claimed")
        .withArgs(id, token.target, alice.address, net);
      expect((await token.balanceOf(alice.address)) - before).to.equal(net);
      expect(await vault.totalLocked(token.target)).to.equal(0n);

      // fully claimed position is burned
      await expect(vault.ownerOf(id)).to.be.revertedWithCustomError(vault, "ERC721NonexistentToken");
    });

    it("only the position owner (or approved) can trigger a claim, funds go to owner", async function () {
      const { vault, token, alice, bob, carol, id, unlockAt, net } = await loadFixture(lockedFixture);
      await time.increaseTo(unlockAt);

      await expect(vault.connect(bob).claim(id)).to.be.revertedWithCustomError(vault, "NotPositionOwner");

      // approved operator can trigger, but funds go to the NFT owner
      await vault.connect(alice).approve(carol.address, id);
      const before = await token.balanceOf(alice.address);
      await vault.connect(carol).claim(id);
      expect((await token.balanceOf(alice.address)) - before).to.equal(net);
      expect(await token.balanceOf(carol.address)).to.equal(0n);
    });

    it("transferring the NFT transfers the claim", async function () {
      const { vault, token, alice, bob, id, unlockAt, net } = await loadFixture(lockedFixture);
      await vault.connect(alice).transferFrom(alice.address, bob.address, id);
      await time.increaseTo(unlockAt);

      await vault.connect(bob).claim(id);
      expect(await token.balanceOf(bob.address)).to.equal(net);
    });

    it("pays out native ETH claims", async function () {
      const { vault, alice, bob } = await loadFixture(deployFixture);
      const now = await time.latest();
      const amount = ethers.parseEther("10");
      await vault.connect(alice).lock(ETH, amount, now + DAY, bob.address, { value: amount });

      await time.increase(DAY + 1);
      const net = (amount * 9950n) / 10000n;
      await expect(vault.connect(bob).claim(1)).to.changeEtherBalance(bob, net);
    });
  });

  describe("vesting", function () {
    it("vests linearly with a cliff", async function () {
      const { vault, token, alice } = await loadFixture(deployFixture);
      const now = await time.latest();
      const start = now + 10;
      const cliff = start + 100 * DAY;
      const end = start + 400 * DAY;
      const amount = ethers.parseEther("400");

      await vault.connect(alice).lockVesting(token.target, amount, start, cliff, end, alice.address);
      const net = (amount * 9950n) / 10000n;

      // before cliff: nothing, even though 25% of time has passed
      await time.increaseTo(cliff - 10);
      expect(await vault.claimable(1)).to.equal(0n);

      // at halfway: ~50% vested
      await time.increaseTo(start + 200 * DAY);
      const half = net / 2n;
      const claimableAtHalf = await vault.claimable(1);
      expect(claimableAtHalf).to.be.closeTo(half, ethers.parseEther("0.001"));

      // partial claim, then remainder after end
      await vault.connect(alice).claim(1);
      const p = await vault.getPosition(1);
      expect(p.claimed).to.be.gt(0n);

      await time.increaseTo(end);
      const rest = await vault.claimable(1);
      expect(rest + p.claimed).to.equal(net);
      await vault.connect(alice).claim(1);
      expect(await token.balanceOf(vault.target)).to.equal(0n);
    });

    it("rejects malformed schedules", async function () {
      const { vault, token, alice } = await loadFixture(deployFixture);
      const now = await time.latest();
      // cliff before start
      await expect(
        vault.connect(alice).lockVesting(token.target, 1000n, now + 100, now + 50, now + 200, alice.address)
      ).to.be.revertedWithCustomError(vault, "InvalidSchedule");
      // end before cliff
      await expect(
        vault.connect(alice).lockVesting(token.target, 1000n, now, now + 300, now + 200, alice.address)
      ).to.be.revertedWithCustomError(vault, "InvalidSchedule");
    });
  });

  describe("topUp", function () {
    it("adds to an existing position with fee applied", async function () {
      const { vault, token, alice, bob, id, net } = await loadFixture(lockedFixture);
      const add = ethers.parseEther("100");
      await token.mint(bob.address, add);
      await token.connect(bob).approve(vault.target, add);

      const addNet = (add * 9950n) / 10000n;
      await expect(vault.connect(bob).topUp(id, add))
        .to.emit(vault, "ToppedUp")
        .withArgs(id, bob.address, addNet, add - addNet);

      const p = await vault.getPosition(id);
      expect(p.amount).to.equal(net + addNet);
    });

    it("requires exact msg.value for ETH positions", async function () {
      const { vault, alice } = await loadFixture(deployFixture);
      const now = await time.latest();
      await vault.connect(alice).lock(ETH, 1000n, now + DAY, alice.address, { value: 1000n });
      await expect(vault.connect(alice).topUp(1, 1000n, { value: 500n }))
        .to.be.revertedWithCustomError(vault, "WrongMsgValue");
      await vault.connect(alice).topUp(1, 1000n, { value: 1000n });
    });
  });

  describe("extend", function () {
    it("moves a time-lock forward, keeping its shape", async function () {
      const { vault, alice, id, unlockAt } = await loadFixture(lockedFixture);
      const newEnd = unlockAt + 30 * DAY;

      await expect(vault.connect(alice).extend(id, newEnd))
        .to.emit(vault, "Extended")
        .withArgs(id, unlockAt, newEnd);

      const p = await vault.getPosition(id);
      expect(p.start).to.equal(newEnd);
      expect(p.cliff).to.equal(newEnd);
      expect(p.end).to.equal(newEnd);
    });

    it("only owner may extend and only to a later date", async function () {
      const { vault, bob, alice, id, unlockAt } = await loadFixture(lockedFixture);
      await expect(vault.connect(bob).extend(id, unlockAt + DAY))
        .to.be.revertedWithCustomError(vault, "NotPositionOwner");
      await expect(vault.connect(alice).extend(id, unlockAt))
        .to.be.revertedWithCustomError(vault, "InvalidSchedule");
      await expect(vault.connect(alice).extend(id, unlockAt - DAY))
        .to.be.revertedWithCustomError(vault, "InvalidSchedule");
    });
  });

  describe("split", function () {
    it("splits a position and conserves total claims", async function () {
      const { vault, token, alice, bob, id, unlockAt, net } = await loadFixture(lockedFixture);
      const slice = net / 4n;

      await expect(vault.connect(alice).split(id, slice, bob.address))
        .to.emit(vault, "Split")
        .withArgs(id, 2n, slice);

      expect(await vault.ownerOf(2)).to.equal(bob.address);

      await time.increaseTo(unlockAt);
      await vault.connect(alice).claim(id);
      await vault.connect(bob).claim(2);

      expect(await token.balanceOf(bob.address)).to.equal(slice);
      expect(await vault.totalLocked(token.target)).to.equal(0n);
      expect(await token.balanceOf(vault.target)).to.equal(0n);
    });

    it("handles splitting after a partial vesting claim", async function () {
      const { vault, token, alice, bob } = await loadFixture(deployFixture);
      const now = await time.latest();
      const start = now + 10;
      const end = start + 100 * DAY;
      const amount = ethers.parseEther("100");
      await vault.connect(alice).lockVesting(token.target, amount, start, start, end, alice.address);
      const net = (amount * 9950n) / 10000n;

      // claim half-way, then split
      await time.increaseTo(start + 50 * DAY);
      await vault.connect(alice).claim(1);
      await vault.connect(alice).split(1, net / 2n, bob.address);

      // both positions remain claimable and everything is paid out by the end
      await time.increaseTo(end);
      await vault.connect(alice).claim(1);
      await vault.connect(bob).claim(2);
      const aliceBal = await token.balanceOf(alice.address);
      const bobBal = await token.balanceOf(bob.address);
      expect(aliceBal + bobBal).to.equal(ethers.parseEther("1000000") - amount + net);
      expect(await token.balanceOf(vault.target)).to.equal(0n);
    });

    it("rejects invalid split amounts", async function () {
      const { vault, alice, bob, id, net } = await loadFixture(lockedFixture);
      await expect(vault.connect(alice).split(id, 0, bob.address))
        .to.be.revertedWithCustomError(vault, "SplitAmountInvalid");
      await expect(vault.connect(alice).split(id, net, bob.address))
        .to.be.revertedWithCustomError(vault, "SplitAmountInvalid");
      await expect(vault.connect(bob).split(id, 1n, bob.address))
        .to.be.revertedWithCustomError(vault, "NotPositionOwner");
    });
  });

  describe("permit and batch", function () {
    it("locks with an EIP-2612 permit in one transaction", async function () {
      const { vault, token, alice, bob } = await loadFixture(deployFixture);
      // fresh signer with no pre-approval
      await token.connect(alice).approve(vault.target, 0);

      const amount = ethers.parseEther("50");
      const now = await time.latest();
      const deadline = now + 3600;

      const domain = {
        name: "Test Token",
        version: "1",
        chainId: (await ethers.provider.getNetwork()).chainId,
        verifyingContract: token.target,
      };
      const types = {
        Permit: [
          { name: "owner", type: "address" },
          { name: "spender", type: "address" },
          { name: "value", type: "uint256" },
          { name: "nonce", type: "uint256" },
          { name: "deadline", type: "uint256" },
        ],
      };
      const message = {
        owner: alice.address,
        spender: vault.target,
        value: amount,
        nonce: await token.nonces(alice.address),
        deadline,
      };
      const sig = ethers.Signature.from(await alice.signTypedData(domain, types, message));

      await vault.connect(alice).lockWithPermit(
        {
          token: token.target,
          amount,
          start: now + DAY,
          cliff: now + DAY,
          end: now + DAY,
          beneficiary: bob.address,
        },
        amount,
        deadline,
        sig.v,
        sig.r,
        sig.s
      );
      expect(await vault.ownerOf(1)).to.equal(bob.address);
    });

    it("creates several locks in one batch, including ETH", async function () {
      const { vault, token, alice, bob, carol } = await loadFixture(deployFixture);
      const now = await time.latest();
      const t = (amount, beneficiary, tok) => ({
        token: tok,
        amount,
        start: now + DAY,
        cliff: now + DAY,
        end: now + DAY,
        beneficiary,
      });

      const ids = await vault.connect(alice).batchLock.staticCall(
        [t(1000n, bob.address, token.target), t(500n, carol.address, ETH)],
        { value: 500n }
      );
      expect(ids).to.deep.equal([1n, 2n]);

      await vault.connect(alice).batchLock(
        [t(1000n, bob.address, token.target), t(500n, carol.address, ETH)],
        { value: 500n }
      );
      expect(await vault.ownerOf(2)).to.equal(carol.address);

      // wrong ETH total reverts
      await expect(
        vault.connect(alice).batchLock([t(500n, carol.address, ETH)], { value: 600n })
      ).to.be.revertedWithCustomError(vault, "WrongMsgValue");
    });
  });

  describe("admin and safety", function () {
    it("pause blocks new locks and top-ups but never claims", async function () {
      const { vault, token, owner, alice, id, unlockAt } = await loadFixture(lockedFixture);
      await vault.connect(owner).pause();

      const now = await time.latest();
      await expect(
        vault.connect(alice).lock(token.target, 1000n, now + DAY, alice.address)
      ).to.be.revertedWithCustomError(vault, "EnforcedPause");
      await expect(vault.connect(alice).topUp(id, 1000n))
        .to.be.revertedWithCustomError(vault, "EnforcedPause");

      await time.increaseTo(unlockAt);
      await vault.connect(alice).claim(id); // claims work while paused
    });

    it("enforces the fee cap forever", async function () {
      const { vault, owner } = await loadFixture(deployFixture);
      await expect(vault.connect(owner).setFee(101)).to.be.revertedWithCustomError(vault, "FeeTooHigh");
      await vault.connect(owner).setFee(100);
      expect(await vault.feeBps()).to.equal(100n);
    });

    it("only owner can call admin functions", async function () {
      const { vault, alice } = await loadFixture(deployFixture);
      await expect(vault.connect(alice).setFee(0)).to.be.revertedWithCustomError(
        vault,
        "OwnableUnauthorizedAccount"
      );
      await expect(vault.connect(alice).pause()).to.be.revertedWithCustomError(
        vault,
        "OwnableUnauthorizedAccount"
      );
      await expect(vault.connect(alice).setFeeRecipient(alice.address)).to.be.revertedWithCustomError(
        vault,
        "OwnableUnauthorizedAccount"
      );
    });

    it("sweep recovers surplus but can never touch locked funds", async function () {
      const { vault, token, feeRecipient, alice, net } = await loadFixture(lockedFixture);

      // nothing to sweep initially
      await expect(vault.sweep(token.target)).to.be.revertedWithCustomError(vault, "ZeroAmount");

      // someone transfers tokens directly to the vault by mistake
      const stray = ethers.parseEther("42");
      await token.connect(alice).transfer(vault.target, stray);

      const before = await token.balanceOf(feeRecipient.address);
      await expect(vault.sweep(token.target)).to.emit(vault, "Swept");
      expect((await token.balanceOf(feeRecipient.address)) - before).to.equal(stray);

      // locked funds untouched
      expect(await token.balanceOf(vault.target)).to.equal(net);
    });

    it("rejects stray ETH transfers", async function () {
      const { vault, alice } = await loadFixture(deployFixture);
      await expect(alice.sendTransaction({ to: vault.target, value: 1n }))
        .to.be.revertedWithCustomError(vault, "WrongMsgValue");
    });
  });

  describe("views and metadata", function () {
    it("enumerates positions per owner", async function () {
      const { vault, token, alice, bob } = await loadFixture(deployFixture);
      const now = await time.latest();
      await vault.connect(alice).lock(token.target, 1000n, now + DAY, alice.address);
      await vault.connect(alice).lock(token.target, 2000n, now + DAY, bob.address);
      await vault.connect(alice).lock(token.target, 3000n, now + DAY, alice.address);

      expect(await vault.positionsOf(alice.address)).to.deep.equal([1n, 3n]);
      expect(await vault.positionsOf(bob.address)).to.deep.equal([2n]);
    });

    it("returns fully on-chain tokenURI metadata", async function () {
      const { vault, id } = await loadFixture(lockedFixture);
      const uri = await vault.tokenURI(id);
      expect(uri).to.match(/^data:application\/json;base64,/);
      const json = JSON.parse(Buffer.from(uri.split(",")[1], "base64").toString());
      expect(json.name).to.contain("Lock #1");
      expect(json.image).to.match(/^data:image\/svg\+xml;base64,/);
      const svg = Buffer.from(json.image.split(",")[1], "base64").toString();
      expect(svg).to.contain("LOCKVAULT");
      expect(svg).to.contain("TT");
    });
  });
});
