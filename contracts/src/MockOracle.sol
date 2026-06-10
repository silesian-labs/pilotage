// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract MockOracle {
    address public owner;

    mapping(address token => uint256 priceUSD) private _prices;

    event PriceSet(address indexed token, uint256 priceUSD, string symbol);
    event OwnerTransferred(address indexed previous, address indexed next);

    error NotOwner();
    error ZeroAddress();
    error ZeroPrice();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setPrice(address token, uint256 priceUSD, string calldata symbol) external onlyOwner {
        if (token == address(0)) revert ZeroAddress();
        if (priceUSD == 0) revert ZeroPrice();
        _prices[token] = priceUSD;
        emit PriceSet(token, priceUSD, symbol);
    }

    function setPrices(
        address[] calldata tokens,
        uint256[] calldata pricesUSD,
        string[] calldata symbols
    ) external onlyOwner {
        require(tokens.length == pricesUSD.length && tokens.length == symbols.length, "length mismatch");
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == address(0)) revert ZeroAddress();
            if (pricesUSD[i] == 0) revert ZeroPrice();
            _prices[tokens[i]] = pricesUSD[i];
            emit PriceSet(tokens[i], pricesUSD[i], symbols[i]);
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function getPrice(address token) external view returns (uint256) {
        return _prices[token];
    }

    function getValue(address token, uint256 amount, uint8 tokenDecimals)
        external
        view
        returns (uint256 valueUSD)
    {
        uint256 price = _prices[token];
        if (price == 0 || amount == 0) return 0;
        uint256 normalizedAmount = tokenDecimals < 18
            ? amount * 10 ** (18 - tokenDecimals)
            : amount / 10 ** (tokenDecimals - 18);
        valueUSD = (normalizedAmount * price) / 1e18;
    }

    function getPrices(address[] calldata tokens) external view returns (uint256[] memory prices) {
        prices = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            prices[i] = _prices[tokens[i]];
        }
    }
}
