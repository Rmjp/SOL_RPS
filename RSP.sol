
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./CommitReveal.sol";
import "./TimeUnit.sol";

contract RPS{
    uint public numPlayer = 0;
    uint public reward = 0;
    mapping (address => uint) public player_choice; // 0 - Rock, 1 - Paper , 2 - Scissors
    mapping(address => bool) public player_not_played;
    address[] public players;
    uint public  revealNum = 0;
    mapping (address => bool) public player_not_reveal;
    TimeUnit public commitTime = new TimeUnit();
    TimeUnit public revealTime = new TimeUnit();
    uint public constant TIME_TO_COMMIT = 5;
    uint public constant TIME_TO_REVEAL = 5;

    uint public numInput = 0;
    mapping(address => CommitReveal) public cr;

    function addPlayer() public payable onlyAcc {
        require(numPlayer < 2);
        if (numPlayer > 0) {
            require(msg.sender != players[0], "not the same");
        }
        require(msg.value == 1 ether);
        reward += msg.value;
        player_not_played[msg.sender] = true;
        player_not_reveal[msg.sender] = true;
        players.push(msg.sender);
        numPlayer++;
        cr[msg.sender] = new CommitReveal();
        if (numPlayer == 2){
            commitTime.setStartTime();
        }
    }

    function input(bytes32 choice) public  {
        require(numPlayer == 2);
        require(player_not_played[msg.sender]);
        require(commitTime.elapsedMinutes() < TIME_TO_COMMIT, "Commit phase timed out");
        player_not_played[msg.sender] = false;
        numInput++;
        cr[msg.sender].commit(choice);
        if (numInput == 2) {
            revealTime.setStartTime();
        }
    }

    function revealChoice(bytes32 revealData) external {
        require(numInput == 2);
        require(revealTime.elapsedMinutes() < TIME_TO_REVEAL, "Timeout");
        require(player_not_reveal[msg.sender], "Player is revealed");
        cr[msg.sender].reveal(revealData);
        player_choice[msg.sender] = uint8(bytes1(revealData[31]));
        require(player_choice[msg.sender] >= 0 && player_choice[msg.sender] <= 4, "Invalid choice");
        player_not_reveal[msg.sender] = false;
        revealNum ++;
        if (revealNum == 2){
            _checkWinnerAndPay();
        }
    }

    function _checkWinnerAndPay() private {
        uint p0Choice = player_choice[players[0]];
        uint p1Choice = player_choice[players[1]];
        address payable account0 = payable(players[0]);
        address payable account1 = payable(players[1]);
        if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
            // to pay player[1]
            account1.transfer(reward);
        }
        else if (p1Choice == p0Choice) {
            account0.transfer(reward / 2);
            account1.transfer(reward / 2);
        }
        else {
            account0.transfer(reward); 
        }
        _reset();
    }

    function cancle() public {
        if(numPlayer < 2){
            for (uint i = 0; i < players.length; i++) {
                payable(players[i]).transfer(reward);
            }
            _reset();
            return ;
        }
        if (numInput < 2 && commitTime.elapsedMinutes() >= TIME_TO_COMMIT){
            for (uint i = 0; i < players.length; i++) {
                payable(players[i]).transfer(reward/2);
            }
            _reset();
            return ;
        }
        if (numInput == 2 && revealNum < 2 && revealTime.elapsedMinutes() >= TIME_TO_REVEAL){
            for (uint i = 0; i < players.length; i++) {
                payable(players[i]).transfer(reward/2);
            }
            _reset();
            return ;
        }
        require(false, "dont meet condition");
    }


    function _reset() private {
        for (uint i = 0; i < players.length; i++) {
            delete player_not_played[players[i]];
            delete player_choice[players[i]];
            delete player_not_reveal[players[i]];
            delete cr[players[i]];
        }
        delete players;
        numPlayer = 0;
        numInput = 0;
        reward = 0;
    }

    function hash(bytes32 data) public view returns (bytes32) {
        return cr[msg.sender].getHash(data);
    }

    modifier onlyAcc() {
        require(
            msg.sender == 0x5B38Da6a701c568545dCfcB03FcB875f56beddC4 ||
            msg.sender == 0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2 ||
            msg.sender == 0x4B20993Bc481177ec7E8f571ceCaE8A9e22C02db ||
            msg.sender == 0x78731D3Ca6b7E34aC0F824c42a7cC18A495cabaB,
            "Not allowed account"
        );
        _;
    }
}