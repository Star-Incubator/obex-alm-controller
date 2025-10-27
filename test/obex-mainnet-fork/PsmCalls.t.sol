// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity >=0.8.0;

import "./ForkTestBase.t.sol";

interface IPSM is IPSMLike {
    function buf() external view returns (uint256);
    function line() external view returns (uint256);
}

contract MainnetControllerSwapUSDSToUSDCFailureTests is ForkTestBase {

    function test_swapUSDSToUSDC_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapUSDSToUSDC(1e6);
    }

    function test_swapUSDSToUSDC_zeroMaxAmount() external {
        vm.startPrank(Ethereum.OBEX_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_TO_USDC(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.swapUSDSToUSDC(1e6);
    }

    function test_swapUSDSToUSDC_rateLimitBoundary() external {
        deal(address(usds), address(almProxy), 10_000_000e18);

        vm.prank(relayer);
        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUSDSToUSDC(5_000_000e6 + 1);

        vm.prank(relayer);
        mainnetController.swapUSDSToUSDC(5_000_000e6);
    }

}

contract MainnetControllerSwapUSDSToUSDCTests is ForkTestBase {

    function test_swapUSDSToUSDC() external {
        vm.prank(relayer);
        mainnetController.mintUSDS(1e18);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY + 1e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);

        vm.prank(relayer);
        mainnetController.swapUSDSToUSDC(1e6);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM + 1e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY + 1e18);

        assertEq(usdc.balanceOf(address(almProxy)),          1e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM - 1e6);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);
    }

    function test_swapUSDSToUSDC_rateLimited() external {
        vm.startPrank(OBEX_PROXY);
        rateLimits.setUnlimitedRateLimitData(mainnetController.LIMIT_USDS_MINT());
        vm.stopPrank();

        bytes32 key = mainnetController.LIMIT_USDS_TO_USDC();
        vm.startPrank(relayer);

        mainnetController.mintUSDS(9_000_000e18);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   9_000_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   0);

        mainnetController.swapUSDSToUSDC(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   8_000_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   1_000_000e6);

        skip(1 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_249_999.9984e6);
        assertEq(usds.balanceOf(address(almProxy)),   8_000_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   1_000_000e6);

        mainnetController.swapUSDSToUSDC(4_249_999.9984e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 0);
        assertEq(usds.balanceOf(address(almProxy)),   3_750_000.0016e18);
        assertEq(usdc.balanceOf(address(almProxy)),   5_249_999.9984e6);

        vm.expectRevert("RateLimits/rate-limit-exceeded");
        mainnetController.swapUSDSToUSDC(1);

        vm.stopPrank();
    }

}

contract MainnetControllerSwapUSDCToUSDSFailureTests is ForkTestBase {

    function test_swapUSDCToUSDS_notRelayer() external {
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            address(this),
            RELAYER
        ));
        mainnetController.swapUSDCToUSDS(1e6);
    }

    function test_swapUSDCToUSDS_zeroMaxAmount() external {
        vm.startPrank(Ethereum.OBEX_PROXY);
        rateLimits.setRateLimitData(mainnetController.LIMIT_USDS_TO_USDC(), 0, 0);
        vm.stopPrank();

        vm.prank(relayer);
        vm.expectRevert("RateLimits/zero-maxAmount");
        mainnetController.swapUSDCToUSDS(1e6);
    }

    function test_swapUSDCToUSDS_incompleteFillBoundary() external {
        // This test verifies the boundary condition where we can fill exactly to the line and drain all DAI from PSM
        // At the obex fork, Art is 2.969B and line is 3.369B
        // Deal USDC to make PSM fillable to the line
        deal(address(usdc), address(POCKET), 3_000_000_000e6);

        uint256 fillAmount = psm.rush();

        // NOTE: Art == dai here because rate is 1 for PSM ilk
        ( uint256 Art,,, uint256 line, ) = dss.vat.ilks(PSM_ILK);

        // Initial Art is 2.969B, after dealing 3B USDC, USDC balance + buffer is 3.4B
        // Since 3.4B > line (3.369B), fill will bring Art to the line
        uint256 expectedFillAmount = line / 1e27 - Art;
        assertEq(fillAmount, expectedFillAmount, "Fill should bring Art to line");
        assertEq(Art + fillAmount, line / 1e27, "Art + fill should equal line");

        // Max amount of DAI that can be swapped = initial DAI balance + fill amount
        uint256 maxSwapAmount = (DAI_BAL_PSM + fillAmount) / 1e12;

        assertEq(maxSwapAmount, 800132258414585, "Max swap amount in USDC");

        deal(address(usdc), address(almProxy), maxSwapAmount + 1);

        vm.startPrank(relayer);
        // Trying to swap more than available should revert
        vm.expectRevert("DssLitePsm/nothing-to-fill");
        mainnetController.swapUSDCToUSDS(maxSwapAmount + 1);

        // Swapping exactly the max amount should work
        mainnetController.swapUSDCToUSDS(maxSwapAmount);

        assertEq(usds.balanceOf(address(almProxy)), maxSwapAmount * 1e12);

        ( Art,,,, ) = dss.vat.ilks(PSM_ILK);

        // Art has now been filled to the debt ceiling and there is no DAI left in the PSM
        assertEq(Art, line / 1e27);
        assertEq(Art, 3369066475936412000000000000, "Art should equal line");

        assertEq(dai.balanceOf(address(PSM)), 0, "PSM should be drained of DAI");
    }

}

contract MainnetControllerSwapUSDCToUSDSTests is ForkTestBase {

    event Fill(uint256 wad);

    function test_swapUSDCToUSDS() external {
        deal(address(usdc), address(almProxy), 1e6);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usdc.balanceOf(address(almProxy)),          1e6);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);

        vm.prank(relayer);
        mainnetController.swapUSDCToUSDS(1e6);

        assertEq(usds.balanceOf(address(almProxy)),          1e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY + 1e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM - 1e18);
        assertEq(dai.totalSupply(),                DAI_SUPPLY - 1e18);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM + 1e6);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);
    }

    function test_swapUSDCToUSDS_exactBalanceNoRefill() external {
        uint256 swapAmount = DAI_BAL_PSM / 1e12;

        deal(address(usdc), address(almProxy), swapAmount);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usdc.balanceOf(address(almProxy)),          swapAmount);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);

        ( uint256 Art1,,,, ) = dss.vat.ilks(PSM_ILK);

        vm.prank(relayer);
        mainnetController.swapUSDCToUSDS(swapAmount);

        ( uint256 Art2,,,, ) = dss.vat.ilks(PSM_ILK);

        assertEq(Art1, Art2);  // Fill was not called on exact amount

        assertEq(usds.balanceOf(address(almProxy)),          DAI_BAL_PSM);  // Drain PSM
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY + DAI_BAL_PSM);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      0);
        assertEq(dai.totalSupply(),                DAI_SUPPLY - DAI_BAL_PSM);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            USDC_BAL_PSM + swapAmount);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);
    }

    function test_swapUSDCToUSDS_partialRefill() external {
        assertEq(DAI_BAL_PSM, 400132258414585000000000000);

        // PSM is not fillable at current fork so need to deal USDC
        uint256 fillAmount = psm.rush();

        assertEq(fillAmount, 0);

        ( uint256 Art,,, uint256 line, ) = dss.vat.ilks(PSM_ILK);

        // Art is less than line, but USDC balance needs to increase to allow minting
        assertEq(usdc.balanceOf(POCKET) * 1e12 + IPSM(PSM).buf(), 2968934218434268000000000000, "USDC balance + buffer");
        assertEq(Art,                                             2969066475936412000000000000, "Art");
        assertEq(line / 1e27,                                     3369066475936412000000000000, "Line");

        // Deal USDC to POCKET to make it fillable - set to 3B to bring USDC balance + buffer to 3.4B
        deal(address(usdc), address(POCKET), 3_000_000_000e6);

        assertEq(usdc.balanceOf(POCKET) * 1e12 + IPSM(PSM).buf(), 3_400_000_000e18);
        assertEq(Art,                                             2969066475936412000000000000, "Art unchanged");
        assertEq(line / 1e27,                                     3369066475936412000000000000, "Line unchanged");

        ( Art,,, line, ) = dss.vat.ilks(PSM_ILK);

        fillAmount = psm.rush();

        // Since USDC balance + buffer (3.4B) > line (3.369B), fill will go to the line
        uint256 expectedFillAmount = line / 1e27 - Art;
        assertEq(fillAmount, expectedFillAmount, "Fill should bring Art to line");
        assertEq(fillAmount, 400000000000000000000000000, "Fill amount ~400M");

        // Swap amount that's less than the total DAI available after fill
        // DAI available after fill = DAI_BAL_PSM + fillAmount = 400.132M + 400M = 800.132M
        // Let's swap 450M which is more than initial balance but less than total after fill
        uint256 swapAmount = 450_000_000e6;
        deal(address(usdc), address(almProxy), swapAmount);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usdc.balanceOf(address(almProxy)),          swapAmount);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            3_000_000_000e6);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);

        vm.prank(relayer);
        vm.expectEmit(PSM);
        emit Fill(fillAmount);
        mainnetController.swapUSDCToUSDS(swapAmount);

        ( Art,,,, ) = dss.vat.ilks(PSM_ILK);

        // Amount minted brings Art to the line
        assertEq(Art, line / 1e27);
        assertEq(Art, 3369066475936412000000000000, "Art should equal line");

        assertEq(usds.balanceOf(address(almProxy)),          450_000_000e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY + 450_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM + fillAmount - 450_000_000e18);
        assertEq(dai.balanceOf(address(PSM)),      350132258414585000000000000, "DAI balance in PSM after partial drain");
        assertEq(dai.totalSupply(),                DAI_SUPPLY + fillAmount - 450_000_000e18);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            3_450_000_000e6);  // 3 billion + 450 million

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);
    }

    function test_swapUSDCToUSDS_multipleRefills() external {
        assertEq(DAI_BAL_PSM, 400132258414585000000000000);

        // PSM is not fillable at current fork so need to deal USDC
        uint256 fillAmount = psm.rush();

        assertEq(fillAmount, 0);

        ( uint256 Art,,, uint256 line, ) = dss.vat.ilks(PSM_ILK);

        // Art is less than line, but USDC balance needs to increase to allow minting
        assertEq(usdc.balanceOf(POCKET) * 1e12 + IPSM(PSM).buf(), 2968934218434268000000000000, "USDC balance + buffer should be 2.968934218434268");
        assertEq(Art,                                             2969066475936412000000000000, "Art should be 2.969066475936412");
        assertEq(line / 1e27,                                     3369066475936412000000000000, "Line should be 3.369066475936412");

        // Deal USDC to POCKET to set up for first fill
        // We want USDC balance + buffer to be between Art and line to trigger partial fill
        // Set it to 3.1 billion so first fill brings Art to 3.1B, then swap triggers second fill to line
        deal(address(usdc), address(POCKET), 2_700_000_000e6);

        uint256 usdcBalancePlusBuf = usdc.balanceOf(POCKET) * 1e12 + IPSM(PSM).buf();
        assertEq(usdcBalancePlusBuf, 3_100_000_000e18, "USDC balance + buffer should be 3.1 billion");

        ( Art,,, line, ) = dss.vat.ilks(PSM_ILK);

        fillAmount = psm.rush();

        // First fill brings Art from current value (2.969B) up to USDC balance + buffer (3.1B)
        uint256 expectedFillAmount1 = 3_100_000_000e18 - Art;
        assertEq(fillAmount, expectedFillAmount1, "Fill amount should equal 3.1B - Art");
        assertEq(fillAmount, 130933524063588000000000000, "Fill amount should be ~130.933M");

        // For the second fill, we need to swap enough USDC to exceed the DAI available after first fill
        // DAI available after first fill = DAI_BAL_PSM + expectedFillAmount1 = 400.132M + 130.933M = 531.065M
        // To trigger a second fill, we need to swap more than 531.065M USDC
        // Let's swap 600M USDC, which will trigger the second fill to the line
        uint256 swapAmount = 600_000_000e6;
        uint256 expectedFillAmount2 = line / 1e27 - 3_100_000_000e18;

        assertEq(expectedFillAmount2, 269066475936412000000000000, "Expected fill amount 2 should be ~269.066M");

        deal(address(usdc), address(almProxy), swapAmount);

        assertEq(usds.balanceOf(address(almProxy)),          0);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM);
        assertEq(dai.totalSupply(),                DAI_SUPPLY);

        assertEq(usdc.balanceOf(address(almProxy)),          swapAmount);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            2_700_000_000e6);

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);

        // Verify that two fills will reach the debt ceiling
        assertEq(Art + expectedFillAmount1 + expectedFillAmount2, line / 1e27);

        vm.prank(relayer);
        vm.expectEmit(PSM);
        emit Fill(expectedFillAmount1);
        emit Fill(expectedFillAmount2);
        mainnetController.swapUSDCToUSDS(swapAmount);

        ( Art,,,, ) = dss.vat.ilks(PSM_ILK);

        // Art has now been filled to the debt ceiling
        assertEq(Art, line / 1e27);
        assertEq(Art, 3369066475936412000000000000, "Art should equal line after fills");

        assertEq(usds.balanceOf(address(almProxy)),          600_000_000e18);
        assertEq(usds.balanceOf(address(mainnetController)), 0);
        assertEq(usds.totalSupply(),                         USDS_SUPPLY + 600_000_000e18);

        assertEq(dai.balanceOf(address(almProxy)), 0);
        assertEq(dai.balanceOf(address(PSM)),      DAI_BAL_PSM + expectedFillAmount1 + expectedFillAmount2 - 600_000_000e18);
        assertEq(dai.balanceOf(address(PSM)),      200132258414585000000000000, "DAI balance in PSM after swap");
        assertEq(dai.totalSupply(),                DAI_SUPPLY + expectedFillAmount1 + expectedFillAmount2 - 600_000_000e18);

        assertEq(usdc.balanceOf(address(almProxy)),          0);
        assertEq(usdc.balanceOf(address(mainnetController)), 0);
        assertEq(usdc.balanceOf(address(POCKET)),            3_300_000_000e6);  // 2.7 billion + 600 million

        assertEq(usds.allowance(address(buffer),   address(vault)), type(uint256).max);
        assertEq(usds.allowance(address(almProxy), DAI_USDS),       0);
        assertEq(dai.allowance(address(almProxy),  PSM),            0);
    }

    function test_swapUSDCToUSDS_rateLimited() external {
        bytes32 key = mainnetController.LIMIT_USDS_TO_USDC();
        vm.startPrank(relayer);

        mainnetController.mintUSDS(5_000_000e18);

        mainnetController.swapUSDSToUSDC(1_000_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_000_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   4_000_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   1_000_000e6);

        mainnetController.swapUSDCToUSDS(400_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 4_400_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   4_400_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   600_000e6);

        skip(4 hours);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   4_400_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   600_000e6);

        mainnetController.swapUSDCToUSDS(600_000e6);

        assertEq(rateLimits.getCurrentRateLimit(key), 5_000_000e6);
        assertEq(usds.balanceOf(address(almProxy)),   5_000_000e18);
        assertEq(usdc.balanceOf(address(almProxy)),   0);

        vm.stopPrank();
    }

    function testFuzz_swapUSDCToUSDS(uint256 swapAmount) external {
        swapAmount = _bound(swapAmount, 1e6, 1_000_000_000e6);

        deal(address(usdc), address(almProxy), swapAmount);

        uint256 usdsBalanceBefore = usds.balanceOf(address(almProxy));

        // NOTE: Doing a low-level call here because if the full amount can't be swapped, it should revert
        vm.prank(relayer);
        ( bool success, ) = address(mainnetController).call(
            abi.encodeWithSignature("swapUSDCToUSDS(uint256)", swapAmount)
        );

        if (success) {
            assertEq(usds.balanceOf(address(almProxy)), usdsBalanceBefore + swapAmount * 1e12);
        }
    }

}

