//+------------------------------------------------------------------+
//|                                            v3TrendFollowing.mq5  |
//|                                              Jasper Niittyvuopio |
//|                                             https://www.mql5.com |
//|                                                                  |
//| Changes being implemented (compared to previous version):        | 
//| - Counter signal removed. Sl, Tp and timeout only.               |
//| - Fixed stop loss in aboslute value (APPLIED)                    |
//| - Disable trading during summer months                           |
//| - Disable trading during market close                            |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Jasper Niittyvuopio"
#property link      "https://www.mql5.com"
#property version   "3.00"

//Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions
CTrade   *Trade;           //Declaire Trade as pointer to CTrade class

//Setup Variables
input int                InpMagicNumber  = 1000000;     //Unique identifier for this expert advisor (use symbol identifiers)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; //Applied price for indicators
input string             InpTradeComment = __FILE__;    //Optional comment for trades

//Global Variables
int             TicksReceivedCount  = 0; //Counts the number of ticks from oninit function

//Strategy specific settings

//TrendFollowing strategy
input int       BufferCandles = 20; //Dungeon breakout period (TrendFollowing)
string          IndicatorMetrics    = "";
int             TicksProcessedCount = 0; //Counts the number of ticks proceeded from oninit function based off candle opens only
static datetime TimeLastTickProcessed;   //Stores the last time a tick was processed based off candle opens only
input bool      TimeoutDelay = false; //Timeout delay enabled (close all positions)
input int       TimeoutDelayPeriods = 1; //Timeout delay periods
ENUM_TIMEFRAMES Timeframe = Period(); //Strategy timeframe
string           Bias = "no bias"; //Current bias?

//Risk Metrics
input bool   TslCheck          = true;   //Use Trailing Stop Loss?
input bool   RiskCompounding   = true;   //Use Compounded Risk Method?
double       StartingEquity    = 0.0;    //Starting Equity
double       CurrentEquityRisk = 0.0;    //Equity that will be risked per trade
input double MaxLossPrc        = 0.02;   //Percent Risk Per Trade
input double StopLossSize     = 0.1;      //Stop Loss Size. 0.xx for yen, 0.0xx for others (ten pips)
input bool   ApplyTakeProfit   = false;  //Apply Take Profit
input double TakeProfitMuliplier = 1;     //Take Profit multiplier

//Store ticketnumbers
ulong TicketNumber = 0;

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

  return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
  //Counts the number of ticks received  
   TicksReceivedCount++; 

  //Check for new candles for TrendFollowing strategy
  bool IsNewCandle = false;
  if(TimeLastTickProcessed != iTime(Symbol(),Timeframe,0))
  {
    IsNewCandle = true;
    TimeLastTickProcessed=iTime(Symbol(),Timeframe,0);
  }

  //If there is a new candle, process any trades
  if(IsNewCandle == true)
  {
    //Counts the number of ticks processed
    TicksProcessedCount++;

    //Check if position is still open. If not open, return 0.
    if (!PositionSelectByTicket(TicketNumber))
    {
      TicketNumber = 0;
    }

    //Initiate String for indicatorMetrics Variable. This will reset variable each time OnTick function runs.
    IndicatorMetrics ="";  
    
    StringConcatenate(IndicatorMetrics,Symbol()," | Last Processed(TrendFollowing): ",TimeLastTickProcessed);

    //Strategy Trigger - Dungeon Breakout (TrendFollowing)
    string OpenSignalBreakout = GetTrendFollowingSignal();
    StringConcatenate(IndicatorMetrics, IndicatorMetrics, " | Signal(TrendFollowing): ", OpenSignalBreakout);   
  
    //Enter Trade
    if(OpenSignalBreakout == "long")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_BUY);
      if(NewTicket != 0)
      {
        TicketNumber = NewTicket;
      }
    }
    else if(OpenSignalBreakout == "short")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_SELL);
      if(NewTicket != 0)
        {
          TicketNumber = NewTicket;
        }
    }

    //Adjust Open Positions - Trailing Stop Loss
    if(TslCheck == true)
    {
      AdjustTsl(TicketNumber, StopLossSize);
    }

    //Close all trades if time is up and timeout delay is enabled
    if(TimeoutDelay && TicksProcessedCount >= TimeoutDelayPeriods)
    {
      string TradesClosedMessage = CloseExistingPosition();
      Print("Time's up! Ari can't close for shit. Coffee is for closers only -- ", TradesClosedMessage);
    }
  }
   
  //Comment for user
   Comment("\n\rExpert_TrendFollowing: ", InpMagicNumber, "\n\r",
         "MT5 Server Time: ", TimeCurrent(), "\n\r",
         "Timeframe (TrendFollowing): ", EnumToString(Timeframe),"\n\r",
         "\n\r",
         "Ticks Received: ", TicksReceivedCount,"\n\r",
         "Ticks Processed (TrendFollowing): ", TicksProcessedCount,"\n\r",
         "Bias: ", Bias,"\n\r",
         "\n\r",
         "Symbols Traded: \n\r", 
         "\n\r",
         IndicatorMetrics, "\n\r");

  }
//+------------------------------------------------------------------+
//| Custom function                                                  |
//+------------------------------------------------------------------+

//Custom Function to get dungeon breakout (TrendFollowing) signals
string GetTrendFollowingSignal()
{
  //Check last closed candle color by comparing open and close prices
  double CurrentClose = NormalizeDouble(iClose(Symbol(),Timeframe,0), 10);
  double LastOpen = NormalizeDouble(iOpen(Symbol(),Timeframe,1), 10);
  string LastCandleColor = "";

  if(CurrentClose >= LastOpen)
  {
    LastCandleColor = "bull";
  }
  else
  {
    LastCandleColor = "bear";
  }

  //Check if breakout happened
  if(LastCandleColor == "bull")
  {
    //Compare current candle close to previous candle highs
    int HighestIndex = iHighest(Symbol(),Timeframe,MODE_CLOSE,BufferCandles,2);
    double HighestPrevious = NormalizeDouble(iClose(Symbol(),Timeframe,HighestIndex), 10);
    if(CurrentClose > HighestPrevious)
    {
      //GO LONG
      return("long");
    }
    else
    {
      //Do nothing (return no signal)
      return("no signal");
    }
  }
  else if(LastCandleColor == "bear")
  {
    //Compare current candle close to previous candle lows
    int LowestIndex = iLowest(Symbol(),Timeframe,MODE_CLOSE,BufferCandles,2);
    double LowestPrevious = NormalizeDouble(iClose(Symbol(),Timeframe,LowestIndex), 10);
    if(CurrentClose < LowestPrevious)
    {
      //GO SHORT
      return("short");
    }
    else
    {
      //Do nothing (return no signal)
      return("no signal");
    }
  }
  else
  {
    //Function has failed
    return("ERROR");
  }
}


//Processes open trades for buy and sell
ulong ProcessTradeOpen(ENUM_ORDER_TYPE OrderType)
{
  //Set symbol string and variables
   string CurrentSymbol   = Symbol();  
   double Price           = 0;
   double StopLossPrice   = 0;
   double TakeProfitPrice = 0;
   
   string Message = "";
   ulong Ticket = 0;

  //Check for same type existing position
  string ExistingPosition = FindExistingPosition();

  //Close existing orders and calculate price and stop loss
  if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "no positions")
  {
    //BUY
    Message = "No existing positions";
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - StopLossSize, Digits());
    if(ApplyTakeProfit)
    {
      TakeProfitPrice = NormalizeDouble(Price + StopLossSize*TakeProfitMuliplier, Digits());
    }
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "no positions")
  {
    //SELL
    Message = "No existing positions";
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + StopLossSize, Digits());
    if(ApplyTakeProfit)
    {
    TakeProfitPrice = NormalizeDouble(Price - StopLossSize*TakeProfitMuliplier, Digits()); 
    }
    Bias = "bear";
  }
  else if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "sell")
  {
    //CLOSE ORDERS AND BUY
    Message         = CloseExistingPosition();
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - StopLossSize, Digits());
    if(ApplyTakeProfit)
    {
    TakeProfitPrice = NormalizeDouble(Price + StopLossSize*TakeProfitMuliplier, Digits());
    }
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "buy")
  {
    //CLOSE ORDERS AND SELL
    Message         = CloseExistingPosition();
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + StopLossSize, Digits());
    if(ApplyTakeProfit)
    {
    TakeProfitPrice = NormalizeDouble(Price - StopLossSize*TakeProfitMuliplier, Digits()); 
    }
    Bias = "bear";
  }
  else if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "buy")
  {
    //Do nothing
    Print("Can't open position, already in long");
    return(Ticket);
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "sell")
  {
    //Do nothing
    Print("Can't open position, already in short");
    return(Ticket);
  }
  else
  {
    Print("SYSTEM ERROR");
    return(Ticket);
  }

  Print("What happened to existing positions?: ", Message);

  //Get lot size
  double LotSize = OptimalLotSize(CurrentSymbol,Price,StopLossPrice);

  //Enter Trade
  Trade.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,TakeProfitPrice,InpTradeComment);
  //Get Position Ticket Number
  Ticket = PositionGetTicket(0);
  TicksProcessedCount = 0;

  //Add in any error handling
  Print("Trade Processed For ", CurrentSymbol," OrderType ",OrderType, " Lot Size ", LotSize, " Ticket ", TicketNumber);

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

//Finds existing trade with magic number
string FindExistingPosition()
{
  for(int i=0; i<(int)PositionsTotal(); i++)
  {
    if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
    {
      return("buy");
    }
    else if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
    {
      return("sell");
    }
  }
  return("no positions");
}

//Closes existing trade with magic number
string CloseExistingPosition()
{
  for(int i=0; i<(int)PositionsTotal(); i++)
  {
    ulong Ticket = PositionGetTicket(i);
    if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
    {
     Trade.PositionClose(Ticket);
    }
  }
  return("positions closed");
}


//Adjust Trailing Stop Loss based off ATR
void AdjustTsl(ulong Ticket, double StopLoss)
{
   //Set symbol string and variables
   string CurrentSymbol   = Symbol();
   double Price           = 0.0;
   double OptimalStopLoss = 0.0;  

   //Check correct ticket number is selected for further position data to be stored. Return if error.
   if (!PositionSelectByTicket(Ticket))
      return;

   //Store position data variables
   ulong  PositionDirection = PositionGetInteger(POSITION_TYPE);
   double CurrentStopLoss   = PositionGetDouble(POSITION_SL);
   double CurrentTakeProfit = PositionGetDouble(POSITION_TP);
   
   //Check if position direction is long 
   if (PositionDirection==POSITION_TYPE_BUY)
   {
      //Get optimal stop loss value
      Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
      OptimalStopLoss = NormalizeDouble(Price - StopLoss, Digits());
      
      //Check if optimal stop loss is greater than current stop loss. If TRUE, adjust stop loss
      if(OptimalStopLoss > CurrentStopLoss)
      {
         Trade.PositionModify(Ticket,OptimalStopLoss,CurrentTakeProfit);
         Print("Ticket ", Ticket, " for symbol ", CurrentSymbol," stop loss adjusted to ", OptimalStopLoss);
      }

      //Return once complete
      return;
   } 

   //Check if position direction is short 
   if (PositionDirection==POSITION_TYPE_SELL)
   {
      //Get optimal stop loss value
      Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
      OptimalStopLoss = NormalizeDouble(Price + StopLoss, Digits());

      //Check if optimal stop loss is less than current stop loss. If TRUE, adjust stop loss
      if(OptimalStopLoss < CurrentStopLoss)
      {
         Trade.PositionModify(Ticket,OptimalStopLoss,CurrentTakeProfit);
         Print("Ticket ", Ticket, " for symbol ", CurrentSymbol," stop loss adjusted to ", OptimalStopLoss);
      }
      
      //Return once complete
      return;
   } 
}