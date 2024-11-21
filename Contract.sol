// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

// Importación de la librería ReentrancyGuard de OpenZeppelin
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// Declaración del contrato
contract TokenWithPriority is ReentrancyGuard {
    // Mapeo para almacenar los saldos de cada dirección
    mapping(address => uint) public balances;

    // Mapeo para almacenar las aprobaciones de transferencias entre direcciones
    mapping(address => mapping(address => uint)) public allowance;

    // Variables del token
    uint public totalSupply = 20_000_000 * 10 ** 18; // Suministro total de tokens (20,000,000 tokens con 18 decimales)
    string public name = "FortisToken"; // Nombre del token
    string public symbol = "FTK"; // Símbolo del token
    uint public decimals = 18; // Decimales del token

    // Dirección del destinatario de las tarifas
    address public feeRecipient = 0xb42209C970e123080958Edd8a24580b2E61cC905;

    // Dirección del propietario del contrato
    address public owner;

    // Control de habilitación de transferencias
    bool public transferEnabled = false; // Inicialmente las transferencias están deshabilitadas

    // Protección antibot: Evita transferencias muy rápidas de la misma dirección
    mapping(address => uint) public lastTransferTime;
    uint public minTimeBetweenTransfers = 1 minutes; // Tiempo mínimo entre transferencias (1 minuto por defecto)

    // Protección anti-whale: Limita el monto máximo que una dirección puede transferir o recibir
    uint public maxTransferAmount = 500 * 10 ** 18; // Límite máximo por transferencia (500 tokens)
    uint public maxWalletBalance = 2000 * 10 ** 18; // Límite máximo por saldo en una dirección (2000 tokens)
    
    // Control de habilitación de límites de saldo
    bool public maxWalletBalanceEnabled = false; // Inicialmente el control de saldo máximo está deshabilitado

    // Eventos del contrato
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
    event TransferEnabled(bool enabled);
    event MaxWalletBalanceEnabled(bool enabled);
    event MaxWalletBalanceUpdated(uint newMaxWalletBalance);
    event FeeUpdated(uint newFee); // Evento para cuando se actualiza la tarifa
    event FeeRecipientUpdated(address newFeeRecipient); // Evento para actualizar el destinatario de la tarifa
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner); // Evento para transferencia de propiedad

    // Variables para ajustar el fee en función de la red
    uint public feePercentage = 1; // Por defecto es 0.1% (1 / 1000)
    uint public fixedFee = 10 * 10 ** 18; // Tarifa fija de 10 tokens
    uint public baseGasPrice = 20 * 10 ** 9; // Valor base del gas (en wei) para Ethereum Mainnet (20 Gwei)

    // Constructor del contrato
    constructor() {
        owner = msg.sender; // La dirección que despliega el contrato es el propietario
        balances[msg.sender] = totalSupply; // El propietario recibe todo el suministro de tokens
    }

    // Modificador para asegurarse de que solo el propietario pueda ejecutar una función
    modifier onlyOwner() {
        require(msg.sender == owner, "Solo el propietario puede ejecutar esta funcion");
        _;
    }

    // Función para calcular la tarifa de la transferencia
    function calculateFee(uint value) public view returns (uint) {
        // Si el valor es menor o igual a 500 tokens, cobramos una tarifa fija
        if (value <= 500 * 10 ** 18) {
            return fixedFee;
        }
        // Si el valor es mayor a 500 tokens, cobramos un porcentaje
        return (value * feePercentage) / 1000; // La tarifa es un % configurable de la cantidad de tokens transferidos
    }

    // Función para habilitar o deshabilitar las transferencias (solo el propietario)
    function setTransferEnabled(bool enabled) external onlyOwner {
        transferEnabled = enabled;
        emit TransferEnabled(enabled); // Emitir un evento cuando se habiliten o deshabiliten las transferencias
    }

    // Función para habilitar o deshabilitar el límite máximo de saldo (solo el propietario)
    function setMaxWalletBalanceEnabled(bool enabled) external onlyOwner {
        maxWalletBalanceEnabled = enabled;
        emit MaxWalletBalanceEnabled(enabled); // Emitir un evento cuando se habilite o deshabilite el límite de saldo máximo
    }

    // Función para cambiar el límite de saldo máximo por dirección (solo propietario, si habilitado)
    function setMaxWalletBalance(uint _maxWalletBalance) external onlyOwner {
        require(maxWalletBalanceEnabled, "La actualizacion del limite de saldo esta deshabilitada");
        maxWalletBalance = _maxWalletBalance;
        emit MaxWalletBalanceUpdated(_maxWalletBalance); // Emitir un evento cuando se cambie el límite
    }

    // Función para cambiar el porcentaje de la tarifa (solo propietario)
    function setFeePercentage(uint _feePercentage) external onlyOwner {
        require(_feePercentage <= 100, "La tarifa no puede ser mayor al 10%");
        feePercentage = _feePercentage;
        emit FeeUpdated(_feePercentage); // Emitir un evento cuando se cambie la tarifa
    }

    // Función para ajustar la tarifa basada en la red
    function adjustFeeBasedOnGas() public onlyOwner {
        uint currentGasPrice = tx.gasprice; // Obtenemos el precio actual del gas (en wei)

        // Ajustamos la tarifa en función del gas actual
        if (currentGasPrice > baseGasPrice) {
            feePercentage = 2; // Aumentamos el fee al 0.2% si el gas es más alto
        } else {
            feePercentage = 1; // De lo contrario, la tarifa es el 0.1%
        }

        emit FeeUpdated(feePercentage); // Emitir un evento de actualización de tarifa
    }

    // Función para realizar una transferencia de tokens (con protección Reentrancy)
    function transfer(address to, uint value) public nonReentrant returns (bool) {
        require(transferEnabled, "Las transferencias estan deshabilitadas"); // Verifica que las transferencias estén habilitadas
        
        uint fee = calculateFee(value); // Calcula la tarifa a cobrar (ajustada por la red)
        uint totalAmount = value + fee; // La cantidad total a transferir (valor + tarifa)

        require(balances[msg.sender] >= totalAmount, "Fondos insuficientes"); // Verifica que el remitente tenga suficiente saldo
        require(to != address(0), "Destino invalido"); // Verifica que la dirección de destino sea válida

        // Protección antibot: Evita transferencias demasiado rápidas desde la misma dirección
        require(block.timestamp >= lastTransferTime[msg.sender] + minTimeBetweenTransfers, "Tiempo insuficiente entre transferencias");

        // Verifica que la transferencia no exceda el límite máximo permitido
        require(value <= maxTransferAmount, "Excede el limite de transferencia por transaccion");

        // Verifica que el saldo de la dirección de destino no exceda el límite máximo permitido
        if (maxWalletBalanceEnabled) {
            require(balances[to] + value <= maxWalletBalance, "Destino excede el saldo maximo permitido");
        }

        // Actualiza el tiempo de la última transferencia
        lastTransferTime[msg.sender] = block.timestamp;

        // Realiza la transferencia, cobrando la tarifa al destinatario de las tarifas
        balances[msg.sender] -= totalAmount; // Resta la cantidad total del remitente
        balances[to] += value; // Suma la cantidad de tokens al destinatario
        balances[feeRecipient] += fee; // Suma la tarifa al destinatario de las tarifas

        emit Transfer(msg.sender, to, value); // Emitir evento de transferencia
        return true;
    }

    // Función para aprobar que otra dirección gaste en nombre del propietario
    function approve(address spender, uint value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value); // Emitir evento de aprobación
        return true;
    }

    // Función para permitir a una dirección transferir propiedad del contrato
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Direccion invalida");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    // Función para retirar Ether del contrato
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    // Función para permitir que el contrato reciba Ether
    receive() external payable {}
}
