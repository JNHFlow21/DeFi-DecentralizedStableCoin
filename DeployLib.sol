// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";

import {KycPassNFT} from "../src/KycPassNFT.sol";
import {VaultToken} from "../src/VaultToken.sol";
import {SimpleRwVault} from "../src/SimpleRwVault.sol";
import {USDCMock} from "../src/mocks/USDCMock.sol";

library DeployLib {
    struct DeployConfig {
        USDCMock usdc;
        VaultToken share;
        KycPassNFT pass;
        SimpleRwVault vault;
    }

    uint8 constant _decimals = 6;

    function deployAll(address admin, string memory svgValid, string memory svgRevoke)
        public
        returns (DeployConfig memory)
    {
        DeployConfig memory config;

        config.usdc = new USDCMock(admin);
        config.share = new VaultToken("Share", "SHR", _decimals, admin);
        config.pass = new KycPassNFT("Pass", "PASS", admin, svgValid, svgRevoke);
        config.vault = new SimpleRwVault(config.usdc, config.share, config.pass, admin, "https://example.com", 0, 0);

        return config;
    }
}
