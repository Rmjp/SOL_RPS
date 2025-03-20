
// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "./CommitReveal.sol";
import "./TimeUnit.sol";
import "./IERC20.sol";

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

    IERC20 public token;                 // reference ไปยัง ERC20 token ที่จะใช้
    uint256 public constant STAKE_AMOUNT = 10**12;

    uint public numInput = 0;
    mapping(address => CommitReveal) public cr;

    constructor(
        address _token
    ) {
        token = IERC20(_token);
    }

    function addPlayer() public payable {
        require(numPlayer < 2, "Already have 2 players");
        if (numPlayer == 1) {
            require(msg.sender != players[0], "You are already in the game");
        }

        player_not_played[msg.sender] = true;
        player_not_reveal[msg.sender] = true;
        players.push(msg.sender);
        numPlayer++;

        // สร้าง CommitReveal instance ให้ผู้เล่น
        cr[msg.sender] = new CommitReveal();

        // ถ้าผู้เล่นครบ 2 คนแล้ว ให้เริ่มนับเวลา Commit
        if (numPlayer == 2) {
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
            require(token.allowance(players[0], address(this)) >= STAKE_AMOUNT, "Player0 allowance not enough");
            require(token.allowance(players[1], address(this)) >= STAKE_AMOUNT, "Player1 allowance not enough");

            // 2) ดึงเงินจากแต่ละคนเข้ามาในคอนแทรกต์
            bool success0 = token.transferFrom(players[0], address(this), STAKE_AMOUNT);
            bool success1 = token.transferFrom(players[1], address(this), STAKE_AMOUNT);
            require(success0 && success1, "transferFrom failed");

            // 3) รวมเป็น reward
            reward = STAKE_AMOUNT * 2;
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
        address account0 = players[0];
        address account1 = players[1];

        // Rock-Paper-Scissors เวอร์ชันเสริม (mod 5)
        // (p0 + 1) % 5 == p1  หรือ (p0 + 3) % 5 == p1 -> p1 ชนะ
        // ถ้าเท่ากัน -> เสมอ
        // ไม่เข้าเงื่อนไขข้างบน -> p0 ชนะ
        if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
            // player[1] ชนะ
            token.transfer(account1, reward);
        }
        else if (p1Choice == p0Choice) {
            // เสมอ แบ่งคนละครึ่ง
            token.transfer(account0, reward / 2);
            token.transfer(account1, reward / 2);
        }
        else {
            // player[0] ชนะ
            token.transfer(account0, reward);
        }

        _reset();
    }

    function withdrawIfTimeout() external {
        // ต้องหมดเวลา reveal ก่อน
        require(revealTime.elapsedMinutes() >= TIME_TO_REVEAL, "Reveal phase not timed out yet");
        // ต้องมีเงินในคอนแทรกต์ (ถ้าไม่มี แปลว่าไม่มีใคร commit ครบ 2)
        require(reward > 0, "No reward in contract");

        // Case 1: reveal มาคนเดียว
        if (revealNum == 1) {
            // ดูว่าใครคือคนที่ reveal
            bool p0Revealed = (player_not_reveal[players[0]] == false);
            bool p1Revealed = (player_not_reveal[players[1]] == false);

            if (p0Revealed && !p1Revealed) {
                require(msg.sender == players[0], "Only the revealer can withdraw");
                token.transfer(players[0], reward);
            }
            else if (!p0Revealed && p1Revealed) {
                require(msg.sender == players[1], "Only the revealer can withdraw");
                token.transfer(players[1], reward);
            }
            else {
                revert("Invalid state");
            }
        }
        // Case 2: ไม่มีใคร reveal
        else if (revealNum == 0) {
            // ใครก็ได้มาเอาเงินไป
            token.transfer(msg.sender, reward);
        }
        else {
            revert("Both players revealed - not applicable here");
        }

        _reset();
    }

    // function cancle() public {
    //     if(numPlayer < 2){
    //         for (uint i = 0; i < players.length; i++) {
    //             payable(players[i]).transfer(reward);
    //         }
    //         _reset();
    //         return ;
    //     }
    //     if (numInput < 2 && commitTime.elapsedMinutes() >= TIME_TO_COMMIT){
    //         for (uint i = 0; i < players.length; i++) {
    //             payable(players[i]).transfer(reward/2);
    //         }
    //         _reset();
    //         return ;
    //     }
    //     if (numInput == 2 && revealNum < 2 && revealTime.elapsedMinutes() >= TIME_TO_REVEAL){
    //         for (uint i = 0; i < players.length; i++) {
    //             payable(players[i]).transfer(reward/2);
    //         }
    //         _reset();
    //         return ;
    //     }
    //     require(false, "dont meet condition");
    // }


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