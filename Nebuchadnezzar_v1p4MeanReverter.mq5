//+------------------------------------------------------------------+
//|                                             v1.4meanreversion.mq5  |
//|                                              Jasper Niittyvuopio |
//|                                             https://www.mql5.com |
//|                                                                  |
//|  - Bug fix. FindExistingPosition() with while-loop doesn't work when there are
//|  multiple algos running concurrently. When there is an existing position generated
//|  by another EA, this EA starts generating multiple orders. Also, the EA's communicate
//|  with each other even if their magic numbers are different.
//|  - The ticket number stays same for every duplicated glitched position. Meanreverter and trendfollower open positions with same ticket.
//|  - Possible solution: start handling positions by PositionSelectByTicket(). Use existing ticketnumber to handle positions.
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Jasper Niittyvuopio"
#property link      "https://www.mql5.com"
#property version   "1.04"

//Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions
CTrade   *Trade;           //Declaire Trade as pointer to CTrade class

//Setup Variables
input int                InpMagicNumber  = 2000000;     //Unique identifier for this expert advisor (use symbol identifiers)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; //Applied price for indicators
input string             InpTradeComment = __FILE__;    //Optional comment for trades

//Global Variables
int             TicksReceivedCount  = 0; //Counts the number of ticks from oninit function
bool            IsNewCandle         = false;

//Strategy specific settings

//MeanReversion strategy
input int       BufferCandles = 20; //Dungeon breakout period (MeanReversion)
string          IndicatorMetrics    = "";
int             TicksProcessedCount = 0; //Counts the number of ticks proceeded from oninit function based off candle opens only
static datetime TimeLastTickProcessed;   //Stores the last time a tick was processed based off candle opens only
ENUM_TIMEFRAMES Timeframe = Period(); //Strategy timeframe

//Store values
double PreviousHigh;
double PreviousLow;
static double LatestAskPrice;
static double LatestBidPrice;

//Risk Metrics
input bool   RiskCompounding   = true;   //Use Compounded Risk Method?
double       StartingEquity    = 0.0;    //Starting Equity
double       CurrentEquityRisk = 0.0;    //Equity that will be risked per trade
input double MaxLossPrc        = 0.02;   //Percent Risk Per Trade (add one decimal for gold)
input double AtrLossMulti      = 1;      //ATR Loss Multiplier
input bool   ApplyTakeProfit   = false;  //Apply Take Profit
input double TakeProfitMuliplier = 1;     //Take Profit multiplier

//ATR Handle and Variables
int HandleAtr;
input int AtrPeriod = 10; //ATR Period
double CurrentAtr;

//Store ticketnumbers
ulong TicketNumber = 0;

//Disable trading between certain hours and months
input string StartTime="2:00:00"; //Market open
input string EndTime="22:50:00"; //Market close
input int TradeBanMonth1 = 0; //Trading disabled first month (1-12)
input int TradeBanMonth2 = 0; //Trading disabled second month (1-12)
input int TradeBanMonth3 = 0; //Trading disabled third month (1-12)
input int TradeBanMonth4 = 0; //Trading disabled fourth month (1-12)
input bool CloseTradesDuringVacation = false; //Close open trade when vacation starts?
input bool CloseTradesDuringWeekend = false; //Close open trades when weekend starts?
string     WeekendCloseTime="22:50:00";
string     TradesClosedMessage = "";

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
  //Declare magic number for all trades
  Trade = new CTrade();
  Trade.SetExpertMagicNumber(InpMagicNumber);

  //Store starting equity onInit
  StartingEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

  // Set up handle for ATR indicator on the initialisation of expert
  HandleAtr = iATR(Symbol(),Timeframe,AtrPeriod);
  Print("Handle for MeanRevertion ATR /", Symbol()," / ", EnumToString(Timeframe),"successfully created");

  return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
    //Remove indicator handle from Metatrader Cache
    IndicatorRelease(HandleAtr);
    Print("Handle released");

    delete(Trade);
    Print("CTrade object destroyed");
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  datetime now = TimeCurrent();
  MqlDateTime time;
  TimeToStruct(now,time);
  if(time.mon != TradeBanMonth1 && time.mon != TradeBanMonth2 && time.mon != TradeBanMonth3 && time.mon != TradeBanMonth4)
  {
    datetime weekendStart = StringToTime(WeekendCloseTime);
    if(CloseTradesDuringWeekend && time.day_of_week == 5 && now >= weekendStart)
    {
      TradesClosedMessage = CloseExistingPosition() + " -- Have a nice weekend!";
    }
    else
    {
      datetime begin = StringToTime(StartTime), stop = StringToTime(EndTime);
      bool isTime = stop <= begin ? now >= begin || now < stop : now >= begin && now < stop;
      if(isTime && time.day_of_week < 6)
      {
        //Trading has begun
        TradesClosedMessage = "";

        //Counts the number of ticks received  
        TicksReceivedCount++; 

        //Check if position is still open. If not open, return 0.
        if (!PositionSelectByTicket(TicketNumber))
        {
          TicketNumber = 0;
        }

        //Check for new candles for MeanReversion strategy
        IsNewCandle = false;
        if(TimeLastTickProcessed != iTime(Symbol(),Timeframe,0))
        {
          IsNewCandle = true;
          TimeLastTickProcessed=iTime(Symbol(),Timeframe,0);
        }

        //If there is a new candle, update buffer
        if(IsNewCandle == true)
        {
          //Counts the number of ticks processed
          TicksProcessedCount++;

          //Initiate String for indicatorMetrics Variable. This will reset variable each time OnTick function runs.
          IndicatorMetrics ="";  
          
          StringConcatenate(IndicatorMetrics,Symbol()," | Last Processed(MeanReversion): ",TimeLastTickProcessed);

          //Update candle buffer & get previous high and low values
          PreviousHigh = GetPreviousHigh();
          PreviousLow = GetPreviousLow();
        }

        if(TicketNumber == 0)
        {
          //Get latest price
          MqlTick LatestPrice;
          SymbolInfoTick(Symbol(), LatestPrice);
          LatestAskPrice = LatestPrice.ask; 
          LatestBidPrice = LatestPrice.bid; 

          //Compare latest price to previous highs and lows and open trade if breakout happens
          if(LatestBidPrice >= PreviousHigh)
          {
            //Money Management - ATR
            CurrentAtr = GetATRValue(HandleAtr); //Gets ATR value double using custom function - convert double to string as per symbol digits
            //Open short position
            TicketNumber = ProcessTradeOpen(ORDER_TYPE_SELL,CurrentAtr);
          }
          else if(LatestAskPrice <= PreviousLow)
          {
            //Money Management - ATR
            CurrentAtr = GetATRValue(HandleAtr); //Gets ATR value double using custom function - convert double to string as per symbol digits
            //Open long position
            TicketNumber = ProcessTradeOpen(ORDER_TYPE_BUY,CurrentAtr);
          }
        }
      }
    }
  } 
  else if(CloseTradesDuringVacation)
  {
    TradesClosedMessage = CloseExistingPosition() + " -- Happy vacation near the palm trees!";
  }
  else
  {
    TradesClosedMessage = "Happy vacation near the palm trees!";
  }
   
  //Comment for user
   Comment("\n\rExpert_MeanReversion: ", InpMagicNumber, "\n\r",
         "MT5 Server Time: ", TimeCurrent(), "\n\r",
         "Timeframe (MeanReversion): ", EnumToString(Timeframe),"\n\r",
         "\n\r",
         "Ticks Received: ", TicksReceivedCount,"\n\r",
         "Ticks Processed (MeanReversion): ", TicksProcessedCount,"\n\r",
         "Dungeon High: ", PreviousHigh,"\n\r",
         "Dungeon Low: ", PreviousLow,"\n\r",
         "ATR Last Processed: ", CurrentAtr,"\n\r",
         "\n\r",
         "Symbols Traded: \n\r", 
         "\n\r",
         IndicatorMetrics, "\n\r",
         "\n\r",
         TradesClosedMessage
         );
  }
//+------------------------------------------------------------------+
//| Custom function                                                  |
//+------------------------------------------------------------------+

//Custom Function to get ATR value
double GetATRValue(int HandleAtr)
{
   //Set symbol string and indicator buffers
   string    CurrentSymbol   = Symbol();
   const int StartCandle     = 0;
   const int RequiredCandles = 3; //How many candles are required to be stored in Expert 

   //Indicator Variables and Buffers
   const int IndexAtr        = 0; //ATR Value
   double    BufferAtr[];         //[prior,current confirmed,not confirmed] 

   //Populate buffers for ATR Value; check errors
   bool FillAtr = CopyBuffer(HandleAtr,IndexAtr,StartCandle,RequiredCandles,BufferAtr); //Copy buffer uses oldest as 0 (reversed)
   if(FillAtr==false)return(0);

   //Find ATR Value for Candle '1' Only
   double CurrentAtr   = NormalizeDouble(BufferAtr[1],5);

   //Return ATR Value
   return(CurrentAtr);
}


//Custom Function to get previous high value from buffer
double GetPreviousHigh()
{
  int HighestIndex = iHighest(Symbol(),Timeframe,MODE_HIGH,BufferCandles,1);
  double HighestPrevious = NormalizeDouble(iHigh(Symbol(),Timeframe,HighestIndex), 10);
  return HighestPrevious;
}


//Custom Function to get previous low value from buffer
double GetPreviousLow()
{
  int LowestIndex = iLowest(Symbol(),Timeframe,MODE_LOW,BufferCandles,1);
  double LowestPrevious = NormalizeDouble(iLow(Symbol(),Timeframe,LowestIndex), 10);
  return LowestPrevious;
}


//Processes open trades for buy and sell
ulong ProcessTradeOpen(ENUM_ORDER_TYPE OrderType, double CurrentAtr)
{
  //Set symbol string and variables
   string CurrentSymbol   = Symbol();  
   double Price           = 0;
   double StopLossPrice   = 0;
   double TakeProfitPrice = 0;
   
   ulong Ticket = 0;

  //Close existing orders and calculate price and stop loss
  if(OrderType == ORDER_TYPE_BUY)
  {
    //BUY
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - CurrentAtr*AtrLossMulti, Digits());
    if(ApplyTakeProfit)
    {
      TakeProfitPrice = NormalizeDouble(Price + CurrentAtr*TakeProfitMuliplier, Digits());
    }
  }
  else if(OrderType == ORDER_TYPE_SELL)
  {
    //SELL
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + CurrentAtr*AtrLossMulti, Digits());
    if(ApplyTakeProfit)
    {
    TakeProfitPrice = NormalizeDouble(Price - CurrentAtr*TakeProfitMuliplier, Digits()); 
    }
  }
  else
  {
    Print("SYSTEM ERROR");
    return Ticket;
  }

  //Get lot size
  double LotSize = OptimalLotSize(CurrentSymbol,Price,StopLossPrice);

  //Enter Trade
  Trade.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,TakeProfitPrice,InpTradeComment);
  //Get Position Ticket Number
  Ticket = Trade.ResultOrder();

  //Add in any error handling
  Print("Trade Processed For ", CurrentSymbol," OrderType ",OrderType, " Lot Size ", LotSize, " Ticket ", Ticket);

  TicksProcessedCount = 0;

  return Ticket;
}


//Finds the optimal lot size for the trade
double OptimalLotSize(string CurrentSymbol, double EntryPrice, double StopLoss)
{
   //Set symbol string and calculate point value
   double TickSize      = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_SIZE);
   double TickValue     = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_VALUE);
   double PointAmount   = SymbolInfoDouble(CurrentSymbol,SYMBOL_POINT);
   double TicksPerPoint = TickSize/PointAmount;
   double PointValue    = TickValue/TicksPerPoint;

   //Calculate risk based off entry and stop loss level by pips
   double RiskPoints = MathAbs((EntryPrice - StopLoss)/TickSize);
      
   //Set risk model - Fixed or compounding
   if(RiskCompounding == true)
   {
      CurrentEquityRisk = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   else
   {
      CurrentEquityRisk = StartingEquity; 
   }

   //Calculate total risk amount in dollars
   double RiskAmount = CurrentEquityRisk * MaxLossPrc;

   //Calculate lot size
   double RiskLots   = NormalizeDouble(RiskAmount/(RiskPoints*PointValue),2);

   //Print values in Journal to check if operating correctly
   PrintFormat("TickSize=%f,TickValue=%f,PointAmount=%f,TicksPerPoint=%f,PointValue=%f,",
                  TickSize,TickValue,PointAmount,TicksPerPoint,PointValue);   
   PrintFormat("EntryPrice=%f,StopLoss=%f,RiskPoints=%f,RiskAmount=%f,RiskLots=%f,",
                  EntryPrice,StopLoss,RiskPoints,RiskAmount,RiskLots);   

   //Return optimal lot size
   return RiskLots;
}

//Closes existing trade with ticket number
string CloseExistingPosition()
{
  Trade.PositionClose(TicketNumber);
  return("position closed");
}
