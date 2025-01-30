# Nebuchadnezzar

MQL5 programming language is very similar to C++. I implemented concurrent programming to create a trading robot that works in real-time market environment. The trading robot is fully functional on Metatrader 5 platform.


There are two seperate algorithms trading two different strategies:

1. The trend follower algorithm trades breakouts of the formation of previous candles.

2. The mean reverter algorithm trades rejections of the lows and highs of the formation of previous candles.

Screenshot of configuration:

![image](https://github.com/user-attachments/assets/8ada5d69-69bf-4a58-83d7-00eb8bc6a7e8)

ATR Loss Multiplier is the size of a stop loss. 

Let's say your backtesting results show you that July and August are bad months for trading. You can disable trading for up to four months every year. You can tell the EA to close all open trades when a disabled month begins (Close open trade when vacation starts?) 

![image](https://github.com/user-attachments/assets/fa6d2810-7641-47c7-95e6-0a6c33440914)

