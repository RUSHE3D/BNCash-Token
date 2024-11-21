// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

contract Token {
    mapping(address => uint) public balances;
    mapping(address => mapping(address => uint)) public allowance;
    uint public totalSupply = 20000000 * 10 ** 18; // Suministro total actualizado
    string public name = "BNCash";
    string public symbol = "BSH";
    uint public decimals = 18;
    
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);

    constructor() {
        balances[msg.sender] = totalSupply; // El propietario recibe el suministro total
    }
    
    // Devuelve el balance de la dirección del propietario
    function balanceOf(address owner) public view returns(uint) {
        return balances[owner];
    }
    
    // Transferir tokens a otra dirección
    function transfer(address to, uint value) public returns(bool) {
        require(to != address(0), "Transfer to the zero address is not allowed");
        require(balanceOf(msg.sender) >= value, "Insufficient balance");

        balances[to] += value;
        balances[msg.sender] -= value;
        
        emit Transfer(msg.sender, to, value);
        return true;
    }
    
    // Transferir tokens desde una dirección aprobada
    function transferFrom(address from, address to, uint value) public returns(bool) {
        require(from != address(0), "Transfer from the zero address is not allowed");
        require(to != address(0), "Transfer to the zero address is not allowed");
        require(balanceOf(from) >= value, "Insufficient balance");
        require(allowance[from][msg.sender] >= value, "Allowance too low");

        balances[to] += value;
        balances[from] -= value;
        allowance[from][msg.sender] -= value;

        emit Transfer(from, to, value);
        return true;
    }
    
    // Aprobar que una dirección pueda gastar tokens en nombre del propietario
    function approve(address spender, uint value) public returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;   
    }

    // Aumentar el allowance (permitir un aumento en la cantidad que un spender puede gastar)
    function increaseAllowance(address spender, uint addedValue) public returns (bool) {
        allowance[msg.sender][spender] += addedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }

    // Reducir el allowance (permitir una disminución en la cantidad que un spender puede gastar)
    function decreaseAllowance(address spender, uint subtractedValue) public returns (bool) {
        uint currentAllowance = allowance[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "Decreased allowance below zero");
        allowance[msg.sender][spender] = currentAllowance - subtractedValue;
        emit Approval(msg.sender, spender, allowance[msg.sender][spender]);
        return true;
    }
}
