// SPDX-License-Identifier: MIT

// File: @uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol

pragma solidity >=0.5.0;

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

// File: @uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol

pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IMaster {
    function addBytax(uint256 _amount) external;
}

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./libs/IUniswapV2Router02.sol";
pragma solidity ^0.8.9;

contract Squarrel is ERC20, Ownable {
    // Transfer tax rate in basis points. starts 0
    uint16 public transferTaxRate;
    uint16 public sellTax = 400;
    // Max transfer tax rate: 10%.
    uint16 public constant MAXIMUM_TRANSFER_TAX_RATE = 1000;
    // Burn address
    address public constant BURN_ADDRESS =
        0x000000000000000000000000000000000000dEaD;
    address public WETH;
    // Automatic swap and liquify enabled
    bool public swapAndLiquifyEnabled = false;
    // Min amount to liquify.
    uint256 public minAmountToLiquify = 1e18;
    bool public standby;
    bool public enableTrade;
    IUniswapV2Router02 public Router;
    address public POL;
    mapping(address => bool) public extraToMap;
    // The trading pair
    address public SqPair;
    // In swap and liquify
    bool private _inSwapAndLiquify;
    // The operator can only update the transfer tax rate
    address private _operator;
    mapping(address => bool) public whitelist;
    mapping(address => bool) public blacklist;

    // Events
    event OperatorTransferred(
        address indexed previousOperator,
        address indexed newOperator
    );
    event TransferTaxRateUpdated(
        address indexed operator,
        uint256 previousRate,
        uint256 newRate
    );
    event SwapAndLiquifyEnabledUpdated(address indexed operator, bool enabled);
    event MinAmountToLiquifyUpdated(
        address indexed operator,
        uint256 previousAmount,
        uint256 newAmount
    );
    event RouterUpdated(
        address indexed operator,
        address indexed router,
        address indexed pair
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    modifier onlyOperator() {
        require(
            _operator == msg.sender,
            "operator: caller is not the operator"
        );
        _;
    }

    modifier lockTheSwap() {
        _inSwapAndLiquify = true;
        _;
        _inSwapAndLiquify = false;
    }

    modifier transferTaxFree() {
        uint16 _transferTaxRate = transferTaxRate;
        transferTaxRate = 0;
        _;
        transferTaxRate = _transferTaxRate;
    }

    constructor() ERC20("Squarrel", "SQR") {
        _operator = msg.sender;
        whitelist[_operator] = true;
        whitelist[BURN_ADDRESS] = true;
        whitelist[address(this)] = true;
        emit OperatorTransferred(address(0), _operator);
    }

    function initialize(
        address _WETH,
        address _Router,
        address _POL
    ) external onlyOwner {
        WETH = _WETH;
        POL = _POL;
        Router = IUniswapV2Router02(_Router);
        _approve(address(this), address(Router), type(uint256).max);
        SqPair = IUniswapV2Factory(Router.factory()).createPair(
            address(this),
            WETH
        );
        require(SqPair != address(0), "Invalid pair address.");
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner.
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }

    /// @dev overrides transfer function to meet tokenomics
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        // swap and liquify
        if (
            swapAndLiquifyEnabled == true &&
            _inSwapAndLiquify == false &&
            sender != SqPair &&
            whitelist[sender] == false &&
            whitelist[recipient] == false
        ) {
            swapAndLiquify();
        }
        if (blacklist[sender]) {
            amount = 0;
        }
        if (whitelist[recipient] || whitelist[sender] || transferTaxRate == 0) {
            super._transfer(sender, recipient, amount);
        } else {
            uint256 taxAmount = (amount * (transferTaxRate)) / (10000);
            uint256 burnAmount = (amount *
                (extraToMap[recipient] ? sellTax : 0)) / (10000);
            if (burnAmount > 0) {
                super._burn(sender, burnAmount);
            }
            super._transfer(sender, address(this), taxAmount);
            super._transfer(sender, recipient, amount - taxAmount - burnAmount);
        }
        if (standby && !enableTrade && !whitelist[recipient]) {
            //blacklist bots that buys before open
            blacklist[recipient] = true;
        }
    }

    /// @dev Swap and add to bank
    function swapAndLiquify() private lockTheSwap transferTaxFree {
        uint256 contractTokenBalance = balanceOf(address(this));
        if (contractTokenBalance >= minAmountToLiquify) {
            swapTokensForEth(contractTokenBalance);
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WETH;

        Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            POL,
            block.timestamp
        );
    }

    // receive() external payable {}

    /**
     * @dev Update the transfer tax rate.
     * Can only be called by the current operator.
     */

    function setWhitelist(address _target, bool _allow) public onlyOperator {
        whitelist[_target] = _allow;
    }

    function updateTransferTaxRate(uint16 _transferTaxRate)
        public
        onlyOperator
    {
        require(
            _transferTaxRate <= MAXIMUM_TRANSFER_TAX_RATE,
            "UpdateTransferTaxRate: Transfer tax rate must not exceed the maximum rate."
        );
        emit TransferTaxRateUpdated(
            msg.sender,
            transferTaxRate,
            _transferTaxRate
        );
        transferTaxRate = _transferTaxRate;
    }

    function setPOL(address _pol) external onlyOperator {
        POL = _pol;
    }

    function enableTrading() public onlyOperator {
        enableTrade = true; //oneTime operation
    }

    function delistblack(address _user) external onlyOperator {
        blacklist[_user] = false;
    }

    function standbyForliq() external onlyOperator {
        standby = true;
        transferTaxRate = 200;
    }

    function setExtra(uint16 _extra) external onlyOperator {
        require(
            _extra + transferTaxRate <= MAXIMUM_TRANSFER_TAX_RATE,
            "Too high"
        );
        sellTax = _extra;
    }

    function setExtramap(address _contract, bool _extra) external onlyOperator {
        extraToMap[_contract] = _extra;
    }

    /**
     * @dev Update the min amount to liquify.
     * Can only be called by the current operator.
     */
    function updateMinAmountToLiquify(uint256 _minAmount) public onlyOperator {
        emit MinAmountToLiquifyUpdated(
            msg.sender,
            minAmountToLiquify,
            _minAmount
        );
        minAmountToLiquify = _minAmount;
    }

    /**
     * @dev Update the swapAndLiquifyEnabled.
     * Can only be called by the current operator.
     */
    function updateSwapAndLiquifyEnabled(bool _enabled) public onlyOperator {
        emit SwapAndLiquifyEnabledUpdated(msg.sender, _enabled);
        swapAndLiquifyEnabled = _enabled;
    }

    /**
     * @dev Update the swap router.
     * Can only be called by the current operator.
     */
    function updateRouter(address _router) public onlyOperator {
        Router = IUniswapV2Router02(_router);
        SqPair = IUniswapV2Factory(Router.factory()).getPair(
            address(this),
            WETH
        );
        require(SqPair != address(0), "updateRouter: Invalid pair address.");
        emit RouterUpdated(msg.sender, address(Router), SqPair);
    }

    /**
     * @dev Returns the address of the current operator.
     */
    function operator() public view returns (address) {
        return _operator;
    }

    /**
     * @dev Transfers operator of the contract to a new account (`newOperator`).
     * Can only be called by the current operator.
     */
    function transferOperator(address newOperator) public onlyOperator {
        require(
            newOperator != address(0),
            "transferOperator: new operator is the zero address"
        );
        emit OperatorTransferred(_operator, newOperator);
        _operator = newOperator;
    }
}
