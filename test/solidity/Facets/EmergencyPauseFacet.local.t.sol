// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.17;

import { LibAllowList, TestBase, console, LiFiDiamond } from "../utils/TestBase.sol";
import { OnlyContractOwner, InvalidConfig, NotInitialized, InformationMismatch, AlreadyInitialized, UnAuthorized, DiamondIsPaused, FunctionDoesNotExist } from "src/Errors/GenericErrors.sol";
import { EmergencyPauseFacet } from "lifi/Facets/EmergencyPauseFacet.sol";
import { PeripheryRegistryFacet } from "lifi/Facets/PeripheryRegistryFacet.sol";
import { OwnershipFacet } from "lifi/Facets/OwnershipFacet.sol";
import { IStargate, ITokenMessaging } from "lifi/Interfaces/IStargate.sol";
import { FeeCollector } from "lifi/Periphery/FeeCollector.sol";
import { ILiFi } from "lifi/Interfaces/ILiFi.sol";
import { LibSwap } from "lifi/Libraries/LibSwap.sol";
import { IDiamondCut } from "lifi/Interfaces/IDiamondCut.sol";
import { IDiamondLoupe } from "lifi/Interfaces/IDiamondLoupe.sol";
import { DiamondLoupeFacet } from "lifi/Facets/DiamondLoupeFacet.sol";

contract EmergencyPauseFacetLOCALTest is TestBase {
    // EVENTS
    event EmergencyFacetRemoved(address facetAddress, address msgSender);
    event EmergencyPaused(address msgSender);
    event EmergencyUnpaused(address msgSender);

    // STORAGE
    EmergencyPauseFacet internal emergencyPauseFacet;
    address[] internal blacklist = new address[](0);

    function setUp() public {
        // set custom block number for forking
        customBlockNumberForForking = 19979843;

        initTestBase();

        // // no need to add the facet to the diamond, it's already added in DiamondTest.sol
        emergencyPauseFacet = EmergencyPauseFacet(payable(address(diamond)));

        // set facet address in TestBase
        setFacetAddressInTestBase(
            address(emergencyPauseFacet),
            "EmergencyPauseFacet"
        );
    }

    function test_PauserWalletCanPauseDiamond() public {
        vm.startPrank(USER_PAUSER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyPaused(USER_PAUSER);

        // pause the contract
        emergencyPauseFacet.pauseDiamond();

        // try to get a list of all registered facets via DiamondLoupe
        vm.expectRevert(DiamondIsPaused.selector);
        DiamondLoupeFacet(address(diamond)).facets();
    }

    function test_DiamondOwnerCanPauseDiamond() public {
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyPaused(USER_DIAMOND_OWNER);

        // pause the contract
        emergencyPauseFacet.pauseDiamond();

        // try to get a list of all registered facets via DiamondLoupe
        vm.expectRevert(DiamondIsPaused.selector);
        DiamondLoupeFacet(address(diamond)).facets();
    }

    function test_UnauthorizedWalletCannotPauseDiamond() public {
        vm.startPrank(USER_SENDER);
        vm.expectRevert(UnAuthorized.selector);
        // pause the contract
        emergencyPauseFacet.pauseDiamond();

        vm.startPrank(USER_RECEIVER);
        vm.expectRevert(UnAuthorized.selector);
        // pause the contract
        emergencyPauseFacet.pauseDiamond();
    }

    function test_DiamondOwnerCanUnpauseDiamondWithEmptyBlacklist() public {
        // pause diamond first
        test_PauserWalletCanPauseDiamond();

        // unpause diamond as owner
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyUnpaused(USER_DIAMOND_OWNER);

        emergencyPauseFacet.unpauseDiamond(blacklist);

        // make sure diamond works normal again and has all facets reinstated
        IDiamondLoupe.Facet[] memory allFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        assertTrue(allFacets.length == 5);

        // try the same again to make sure commands can be repeatedly executed
        test_PauserWalletCanPauseDiamond();

        // unpause diamond as owner
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyUnpaused(USER_DIAMOND_OWNER);

        emergencyPauseFacet.unpauseDiamond(blacklist);

        // make sure diamond works normal again and has all facets reinstated
        allFacets = DiamondLoupeFacet(address(diamond)).facets();

        assertTrue(allFacets.length == 5);

        // try the same again to make sure commands can be repeatedly executed
        test_PauserWalletCanPauseDiamond();
    }

    function test_CanUnpauseDiamondWithSingleBlacklist() public {
        // pause diamond first
        test_PauserWalletCanPauseDiamond();

        // unpause diamond as owner
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyUnpaused(USER_DIAMOND_OWNER);

        blacklist = new address[](1);
        blacklist[0] = 0xB021CCbe1bd1EF2af8221A79E89dD3145947A082; // OwnershipFacet

        emergencyPauseFacet.unpauseDiamond(blacklist);

        // make sure diamond works normal again and has all facets reinstated
        IDiamondLoupe.Facet[] memory allFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        assertTrue(allFacets.length == 4);

        // make sure ownershipFacet is not available anymore
        vm.expectRevert(FunctionDoesNotExist.selector);
        OwnershipFacet(address(diamond)).owner();
    }

    function test_CanUnpauseDiamondWithMultiBlacklist() public {
        // pause diamond first
        test_PauserWalletCanPauseDiamond();

        // unpause diamond as owner
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyUnpaused(USER_DIAMOND_OWNER);

        blacklist = new address[](2);
        blacklist[0] = 0xB021CCbe1bd1EF2af8221A79E89dD3145947A082; // OwnershipFacet
        blacklist[1] = 0xA412555Fa40F6AA4B67a773dB5a7f85983890341; // PeripheryRegistryFacet

        emergencyPauseFacet.unpauseDiamond(blacklist);

        // make sure diamond works normal again and has all facets reinstated
        IDiamondLoupe.Facet[] memory allFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        assertTrue(allFacets.length == 3);

        // make sure ownershipFacet is not available anymore
        vm.expectRevert(FunctionDoesNotExist.selector);
        OwnershipFacet(address(diamond)).owner();

        // make sure PeripheryRegistryFacet is not available anymore
        vm.expectRevert(FunctionDoesNotExist.selector);
        PeripheryRegistryFacet(address(diamond)).getPeripheryContract(
            "Executor"
        );
    }

    function test_UnauthorizedWalletCannotUnpauseDiamond() public {
        // pause diamond first
        test_PauserWalletCanPauseDiamond();

        // make sure it's paused
        vm.expectRevert(DiamondIsPaused.selector);
        IDiamondLoupe.Facet[] memory allFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        vm.startPrank(USER_PAUSER);
        vm.expectRevert(OnlyContractOwner.selector);
        emergencyPauseFacet.unpauseDiamond(blacklist);

        vm.startPrank(USER_RECEIVER);
        vm.expectRevert(OnlyContractOwner.selector);
        emergencyPauseFacet.unpauseDiamond(blacklist);

        // make sure diamond is still paused
        vm.expectRevert(DiamondIsPaused.selector);
        allFacets = DiamondLoupeFacet(address(diamond)).facets();
    }

    function test_DiamondOwnerCanRemoveFacetAndUnpauseDiamond() public {
        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory initialFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // get PeripheryRegistryFacet address
        address facetAddress = DiamondLoupeFacet(address(diamond))
            .facetAddress(
                PeripheryRegistryFacet(address(diamond))
                    .registerPeripheryContract
                    .selector
            );

        // remove facet
        vm.startPrank(USER_DIAMOND_OWNER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyFacetRemoved(facetAddress, USER_DIAMOND_OWNER);

        emergencyPauseFacet.removeFacet(facetAddress);

        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory finalFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // ensure that one facet less is registered now
        assertTrue(initialFacets.length == finalFacets.length + 1);
        // ensure that PeripheryRegistryFacet function selector is not associated to any facetAddress
        assertTrue(
            DiamondLoupeFacet(address(diamond)).facetAddress(
                PeripheryRegistryFacet(address(diamond))
                    .registerPeripheryContract
                    .selector
            ) == address(0)
        );

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyUnpaused(USER_DIAMOND_OWNER);

        // unpause diamond with empty blacklist
        emergencyPauseFacet.unpauseDiamond(blacklist);

        vm.stopPrank();
    }

    function test_PauserWalletCanRemoveFacet() public {
        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory initialFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // get PeripheryRegistryFacet address
        address facetAddress = DiamondLoupeFacet(address(diamond))
            .facetAddress(
                PeripheryRegistryFacet(address(diamond))
                    .registerPeripheryContract
                    .selector
            );

        // remove facet
        vm.startPrank(USER_PAUSER);

        vm.expectEmit(true, true, true, true, address(emergencyPauseFacet));
        emit EmergencyFacetRemoved(facetAddress, USER_PAUSER);

        emergencyPauseFacet.removeFacet(facetAddress);

        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory finalFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // ensure that one facet less is registered now
        assertTrue(initialFacets.length == finalFacets.length + 1);
        // ensure that PeripheryRegistryFacet function selector is not associated to any facetAddress
        assertTrue(
            DiamondLoupeFacet(address(diamond)).facetAddress(
                PeripheryRegistryFacet(address(diamond))
                    .registerPeripheryContract
                    .selector
            ) == address(0)
        );

        vm.stopPrank();
    }

    function test_UnauthorizedWalletCannotRemoveFacet() public {
        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory initialFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // get PeripheryRegistryFacet address
        address facetAddress = DiamondLoupeFacet(address(diamond))
            .facetAddress(
                PeripheryRegistryFacet(address(diamond))
                    .registerPeripheryContract
                    .selector
            );

        // try to remove facet
        vm.startPrank(USER_SENDER);
        vm.expectRevert(UnAuthorized.selector);
        emergencyPauseFacet.removeFacet(facetAddress);

        vm.startPrank(USER_RECEIVER);
        vm.expectRevert(UnAuthorized.selector);
        emergencyPauseFacet.removeFacet(facetAddress);

        // get a list of all registered facet addresses
        IDiamondLoupe.Facet[] memory finalFacets = DiamondLoupeFacet(
            address(diamond)
        ).facets();

        // ensure that number of facets remains unchanged
        assertTrue(initialFacets.length == finalFacets.length);
    }

    function _getDiamondCutDataForFacetRemoval(
        address facetToBeRemoved
    ) public returns (IDiamondCut.FacetCut memory cut) {}
}