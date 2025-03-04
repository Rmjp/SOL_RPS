# เกมเป่ายิ้งฉุบ บน smart contrat
โครงสร้างโดยรวมแบ่งออกเป็น 3 ไฟล์คือ

1. **RPS.sol** (สัญญาหลักในการเล่นเกม เป่ายิ้งฉุบ)  
2. **CommitReveal.sol** (ส่วนจัดการกระบวนการ Commit-Reveal)  
3. **TimeUnit.sol** (ส่วนจัดการเวลาในแต่ละเฟสของเกม)

---

## 1. โค้ดที่ป้องกันการ Lock เงินไว้ใน Contract

ในสัญญา RPS จะมีส่วนของการจัดการเงินเดิมพัน (เดิมพันคนละ 1 ETH) โดยมีกลไกป้องกันไม่ให้เงินถูก “ล็อก” (Lock) ทิ้งไว้ในสัญญาโดยไม่มีทางดึงคืนได้ ซึ่งทำได้โดยเงื่อนไขต่อไปนี้

- **ฟังก์ชัน `cancle()`** 
  ```solidity
  function cancle() public {
      if(numPlayer < 2){
          for (uint i = 0; i < players.length; i++) {
              payable(players[i]).transfer(reward);
          }
          _reset();
          return ;
      }
      ...
      if (numInput < 2 && commitTime.elapsedMinutes() >= TIME_TO_COMMIT){
          for (uint i = 0; i < players.length; i++) {
              payable(players[i]).transfer(reward/2);
          }
          _reset();
          return ;
      }
      ...
      require(false, "dont meet condition");
  }
  ```
  - มีเงื่อนไขในการเช็คว่า “ผู้เล่นเข้ามาไม่ครบ” หรือ “เกินเวลาที่กำหนดในเฟส Commit / Reveal แล้ว” ก็จะคืนเงินให้ผู้เล่น
  - ทำให้ไม่เกิดสถานการณ์ที่เงินค้างในสัญญาโดยไม่สามารถถอนออกได้

- **ฟังก์ชัน `_reset()`**  
  ```solidity
  function _reset() private {
      for (uint i = 0; i < players.length; i++) {
          ...
      }
      delete players;
      numPlayer = 0;
      numInput = 0;
      reward = 0;
  }
  ```
  - เคลียร์ค่าต่าง ๆ ในสัญญา หากมีการยกเลิกหรือจบเกม จะทำให้ผู้เล่นไม่สามารถล็อกเงินไว้แล้วละทิ้งสัญญาได้

สรุปคือ มีฟังก์ชัน `cancle()` เพื่อยกเลิกและคืนเงิน และ `_reset()` เพื่อเคลียร์สถานะสัญญา ทำให้เงินไม่ถูกล็อกในสัญญาอย่างถาวร

---

## 2. โค้ดส่วนที่ทำการซ่อน Choice และ Commit

การซ่อน Choice ของผู้เล่นทำผ่านกลไก Commit-Reveal ที่อยู่ในสัญญา **`CommitReveal.sol`** โดยผู้เล่นจะส่งค่า `commit` ซึ่งเป็น `hash(revealData)` (ยังไม่บอก Choice จริง) เพื่อป้องกันการลอกเลียนหรือเดา Choice

- **โค้ดใน `CommitReveal.sol`**  
  ```solidity
  function commit(bytes32 dataHash) public {
      commits[msg.sender].commit = dataHash;
      commits[msg.sender].block = uint64(block.number);
      commits[msg.sender].revealed = false;
      ...
  }
  ...
  function getHash(bytes32 data) public pure returns(bytes32) {
      return keccak256(abi.encodePacked(data));
  }
  ```
  - ผู้เล่นจะทำการเรียก `commit(...)` พร้อมส่ง `dataHash` (ซึ่งเป็นการแฮชของข้อมูล Choice + secret ที่ผู้เล่นเตรียมไว้)  
  - จะบันทึกไว้ใน `commits[msg.sender].commit`

- **โค้ดใน `RPS.sol`** ที่รับ Commit จากผู้เล่น  
  ```solidity
  function input(bytes32 choice) public {
      require(numPlayer == 2);
      require(player_not_played[msg.sender]);
      require(commitTime.elapsedMinutes() < TIME_TO_COMMIT, "Commit phase timed out");
      ...
      cr[msg.sender].commit(choice);
      ...
  }
  ```
  - จะเรียก `cr[msg.sender].commit(choice)` เพื่อบันทึก Commit ซึ่ง `cr[msg.sender]` เป็นสัญญา CommitReveal ของแต่ละผู้เล่น (สร้างจาก `new CommitReveal()` ตอน `addPlayer()`)

การซ่อน Choice จึงถูกจัดการโดยการส่งแฮชไปแทน ทำให้ผู้อื่นไม่สามารถรู้ Choice ที่แท้จริงได้จนกว่าจะมาถึงขั้นตอน Reveal

---

## 3. โค้ดส่วนที่จัดการกับความล่าช้าที่ผู้เล่นไม่ครบทั้งสองคนเสียที (Timeout)

สัญญามีการกำหนดเวลา (Timeout) สองระยะหลัก ๆ คือ

1. **Commit Phase** – ผู้เล่นทั้งสองต้อง Commit ภายในเวลาที่กำหนด (`TIME_TO_COMMIT = 5` นาที)  
2. **Reveal Phase** – ผู้เล่นทั้งสองต้อง Reveal ภายในเวลาที่กำหนด (`TIME_TO_REVEAL = 5` นาที)

หากมีการล่าช้า สัญญาจะอนุญาตให้ยกเลิกได้ผ่านฟังก์ชัน `cancle()` ซึ่งมีเงื่อนไขต่าง ๆ

```solidity
function cancle() public {
    // ถ้าผู้เล่นยังไม่ครบ 2 คน -> คืนเงิน
    if(numPlayer < 2){
        ...
        return ;
    }

    // ถ้าผู้เล่น Commit ไม่ครบ (numInput < 2) และหมดเวลา Commit -> คืนเงิน
    if (numInput < 2 && commitTime.elapsedMinutes() >= TIME_TO_COMMIT){
        ...
        return ;
    }

    // ถ้าผู้เล่น Reveal ไม่ครบ (revealNum < 2) และหมดเวลา Reveal -> คืนเงิน
    if (numInput == 2 && revealNum < 2 && revealTime.elapsedMinutes() >= TIME_TO_REVEAL){
        ...
        return ;
    }
}
```

- ในแต่ละเฟสจะใช้สัญญา `TimeUnit` (เช่น `commitTime.elapsedMinutes()` และ `revealTime.elapsedMinutes()`) เพื่อตรวจเช็คว่าผ่านไปกี่นาทีแล้ว  
- ถ้าเกินเวลา ก็จะใช้เงื่อนไข `if(...)` ต่าง ๆ ใน `cancle()` เพื่อยกเลิกเกมและคืนเงินตามสถานการณ์

**สรุป:** มีการตั้งตัวจับเวลาสำหรับ Commit และ Reveal ถ้าใครไม่ทำภายในเวลาที่กำหนด สัญญาจะสามารถเรียก `cancle()` เพื่อคืนเงินบางส่วนหรือตามเงื่อนไขได้

---

## 4. โค้ดส่วนทำการ Reveal และนำ Choice มาตัดสินผู้ชนะ

เมื่อผู้เล่น Commit แล้วครบ (2 คน) และอยู่ในเวลาที่กำหนด ก็จะเปิดให้ “Reveal” โดยผู้เล่นต้องส่ง `revealData` ที่เป็นข้อมูลจริง (Choice) เพื่อให้ระบบตรวจสอบว่าตรงกับค่า `commit` ก่อนหน้า

- **ส่วนการเรียก `revealChoice()`** ใน `RPS.sol`  
  ```solidity
  function revealChoice(bytes32 revealData) external {
      require(numInput == 2);
      require(revealTime.elapsedMinutes() < TIME_TO_REVEAL, "Timeout");
      require(player_not_reveal[msg.sender], "Player is revealed");

      cr[msg.sender].reveal(revealData); 
      player_choice[msg.sender] = uint8(bytes1(revealData[31]));
      ...
      revealNum ++;
      if (revealNum == 2){
          _checkWinnerAndPay();
      }
  }
  ```
  - เช็คว่าผู้เล่น Commit ครบ (numInput == 2)  
  - เช็คเวลาว่ายังไม่เกินเวลาช่วง Reveal  
  - เรียก `cr[msg.sender].reveal(revealData)` (ฟังก์ชันใน CommitReveal.sol) เพื่อยืนยันว่าค่า `revealData` ตรงกับ `commit` ที่เคยส่ง  
  - แยก choice จริงออกมาจาก `revealData` (ในตัวอย่างนี้เป็นการดึง byte สุดท้าย `revealData[31]` มาตีความเป็นตัวเลือก 0-4)  
  - นับจำนวนคน Reveal (`revealNum`) ถ้าครบ 2 คนแล้ว ไปสู่ `_checkWinnerAndPay()`

- **ส่วนการตัดสินผู้ชนะ `_checkWinnerAndPay()`**  
  ```solidity
  function _checkWinnerAndPay() private {
      uint p0Choice = player_choice[players[0]];
      uint p1Choice = player_choice[players[1]];
      address payable account0 = payable(players[0]);
      address payable account1 = payable(players[1]);

      if ((p0Choice + 1) % 5 == p1Choice || (p0Choice + 3) % 5 == p1Choice) {
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
  ```
  - นำตัวเลือกของผู้เล่น 2 คน มาคำนวณว่าใครชนะ/เสมอ/แพ้  
  - จากตัวอย่าง `(p0Choice + 1) % 5 == p1Choice` หรือ `(p0Choice + 3) % 5 == p1Choice` คำนวณผู้ชนะ (Rock-Paper-Scissors-Lizard-Spock) ใช้การเปรียบเทียบเลข Mod 5 มาตัดสิน
  - ส่ง ETH ให้ผู้ชนะ หรือถ้าเสมอให้แบ่งกันคนละครึ่ง
  - สุดท้ายเรียก `_reset()` เพื่อล้างสถานะสัญญา

---

## ภาพรวมการทำงาน (Workflow)

1. **รอผู้เล่นกด `addPlayer()`** สองคน  
   - แต่ละคนต้องใส่ 1 ETH เข้ามาเป็นค่าน้ำหนัก (reward = 2 ETH)
   - เมื่อครบ 2 คน จะเริ่มนับเวลาเฟส Commit โดยสัญญาเรียก `commitTime.setStartTime()`

2. **ผู้เล่นแต่ละคนต้องกด `input(...)`** พร้อมส่งค่า Commit (hash) ภายในเวลาที่กำหนด (TIME_TO_COMMIT)  
   - เมื่อทั้งสองคน Commit แล้ว (numInput = 2) จะเริ่มนับเวลาเฟส Reveal โดยสัญญาเรียก `revealTime.setStartTime()`

3. **ผู้เล่นแต่ละคนกด `revealChoice(...)`** พร้อมส่งข้อมูลจริง (revealData) ภายในเวลาที่กำหนด (TIME_TO_REVEAL)  
   - สัญญาจะตรวจสอบว่า hash ตรงกับค่าที่ Commit ไว้หรือไม่  
   - ดึง choice มาเก็บใน `player_choice`  
   - เมื่อ Reveal ครบ 2 คนจะเรียก `_checkWinnerAndPay()`

4. **หากมีการไม่ทำตามกำหนดเวลาหรือมีกรณียกเลิก** ใช้ฟังก์ชัน `cancle()` ในการคืนเงินและ Reset

---

## สรุป

- **ป้องกันการ Lock เงิน:** มีฟังก์ชันยกเลิก (`cancle()`) และเคลียร์สภาพ (`_reset()`) เพื่อป้องกันเงินค้างในสัญญา  
- **ซ่อน Choice และ Commit:** ใช้สัญญา `CommitReveal` เพื่อรับค่าแฮช (commit) ในเฟสแรก แล้วจึงเปิดเผย (reveal) ในเฟสที่สอง  
- **จัดการ Timeout:** มีการจับเวลาในเฟส Commit และ Reveal ผ่านสัญญา `TimeUnit` หากไม่ดำเนินการตามเวลา ก็ยกเลิกและคืนเงิน  
- **Reveal & ตัดสินผู้ชนะ:** เมื่อผู้เล่นทั้งสองคน Reveal เรียบร้อย จะตรวจ Choice แล้วโอน ETH ให้ผู้ชนะหรือแบ่งกรณีเสมอ ก่อนรีเซ็ตสถานะทั้งหมด  