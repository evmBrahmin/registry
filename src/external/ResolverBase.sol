// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import { AccessDenied, ZERO_TIMESTAMP, NotFound, ZERO_ADDRESS } from "../Common.sol";
import { AttestationRecord, ModuleRecord } from "../DataTypes.sol";
import { IResolver } from "./IResolver.sol";

/**
 * @title A base resolver contract
 *
 * @author zeroknots.eth
 */
abstract contract ResolverBase is IResolver {
    error InsufficientValue();
    error NotPayable();
    error InvalidRS();

    // The version of the contract.
    string public constant VERSION = "0.1";

    // The global Rhinestone Registry contract.
    address internal immutable _rs;

    /**
     * @dev Creates a new resolver.
     *
     * @param rs The address of the global RS contract.
     */
    constructor(address rs) {
        if (rs == ZERO_ADDRESS) {
            revert InvalidRS();
        }
        _rs = rs;
    }

    /**
     * @dev Ensures that only the RS contract can make this call.
     */
    modifier onlyRS() {
        _onlyRSRegistry();
        _;
    }

    /**
     * @inheritdoc IResolver
     */
    function isPayable() public pure virtual returns (bool) {
        return false;
    }

    /**
     * @dev ETH callback.
     */
    receive() external payable virtual {
        if (!isPayable()) {
            revert NotPayable();
        }
    }

    /**
     * @inheritdoc IResolver
     */
    function attest(AttestationRecord calldata attestation)
        external
        payable
        onlyRS
        returns (bool)
    {
        return onAttest(attestation, msg.value);
    }

    /**
     * @inheritdoc IResolver
     */
    function moduleRegistration(ModuleRecord calldata module)
        external
        payable
        onlyRS
        returns (bool)
    {
        return onModuleRegistration(module, msg.value);
    }

    /**
     * @inheritdoc IResolver
     */

    function multiAttest(
        AttestationRecord[] calldata attestations,
        uint256[] calldata values
    )
        external
        payable
        onlyRS
        returns (bool)
    {
        uint256 length = attestations.length;

        // We are keeping track of the remaining ETH amount that can be sent to resolvers and will keep deducting
        // from it to verify that there isn't any attempt to send too much ETH to resolvers. Please note that unless
        // some ETH was stuck in the contract by accident (which shouldn't happen in normal conditions), it won't be
        // possible to send too much ETH anyway.
        uint256 remainingValue = msg.value;

        for (uint256 i; i < length; ++i) {
            // Ensure that the attester/revoker doesn't try to spend more than available.
            uint256 value = values[i];
            if (value > remainingValue) {
                revert InsufficientValue();
            }

            // Forward the attestation to the underlying resolver and revert in case it isn't approved.
            if (!onAttest(attestations[i], value)) {
                return false;
            }

            unchecked {
                // Subtract the ETH amount, that was provided to this attestation, from the global remaining ETH amount.
                remainingValue -= value;
            }
        }

        return true;
    }

    /**
     * @inheritdoc IResolver
     */
    function revoke(AttestationRecord calldata attestation)
        external
        payable
        onlyRS
        returns (bool)
    {
        return onRevoke(attestation, msg.value);
    }

    /**
     * @inheritdoc IResolver
     */
    function multiRevoke(
        AttestationRecord[] calldata attestations,
        uint256[] calldata values
    )
        external
        payable
        onlyRS
        returns (bool)
    {
        uint256 length = attestations.length;

        // We are keeping track of the remaining ETH amount that can be sent to resolvers and will keep deducting
        // from it to verify that there isn't any attempt to send too much ETH to resolvers. Please note that unless
        // some ETH was stuck in the contract by accident (which shouldn't happen in normal conditions), it won't be
        // possible to send too much ETH anyway.
        uint256 remainingValue = msg.value;

        for (uint256 i; i < length; ++i) {
            // Ensure that the attester/revoker doesn't try to spend more than available.
            uint256 value = values[i];
            if (value > remainingValue) {
                revert InsufficientValue();
            }

            // Forward the revocation to the underlying resolver and revert in case it isn't approved.
            if (!onRevoke(attestations[i], value)) {
                return false;
            }

            unchecked {
                // Subtract the ETH amount, that was provided to this attestation, from the global remaining ETH amount.
                remainingValue -= value;
            }
        }

        return true;
    }

    /**
     * @dev A resolver callback that should be implemented by child contracts.
     *
     * @param attestation The new attestation.
     * @param value An explicit ETH amount that was sent to the resolver. Please note that this value is verified in
     * both attest() and multiAttest() callbacks RS-only callbacks and that in case of multi attestations, it'll
     * usually hold that msg.value != value, since msg.value aggregated the sent ETH amounts for all the attestations
     * in the batch.
     *
     * @return Whether the attestation is valid.
     */
    function onAttest(
        AttestationRecord calldata attestation,
        uint256 value
    )
        internal
        virtual
        returns (bool);

    /**
     * @dev Processes an attestation revocation and verifies if it can be revoked.
     *
     * @param attestation The existing attestation to be revoked.
     * @param value An explicit ETH amount that was sent to the resolver. Please note that this value is verified in
     * both revoke() and multiRevoke() callbacks RS-only callbacks and that in case of multi attestations, it'll
     * usually hold that msg.value != value, since msg.value aggregated the sent ETH amounts for all the attestations
     * in the batch.
     *
     * @return Whether the attestation can be revoked.
     */
    function onRevoke(
        AttestationRecord calldata attestation,
        uint256 value
    )
        internal
        virtual
        returns (bool);

    function onModuleRegistration(
        ModuleRecord calldata module,
        uint256 value
    )
        internal
        virtual
        returns (bool);

    /**
     * @dev Ensures that only the RS contract can make this call.
     */
    function _onlyRSRegistry() private view {
        if (msg.sender != _rs) {
            revert AccessDenied();
        }
    }

    function supportsInterface(bytes4 interfaceID) external pure returns (bool) {
        return interfaceID == this.supportsInterface.selector
            || interfaceID == this.isPayable.selector || interfaceID == this.attest.selector
            || interfaceID == this.moduleRegistration.selector
            || interfaceID == this.multiAttest.selector || interfaceID == this.revoke.selector
            || interfaceID == this.multiRevoke.selector;
    }
}
