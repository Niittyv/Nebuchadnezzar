//+------------------------------------------------------------------+
//|                                            v2.1TrendFollowing.mq5|
//|                                              Jasper Niittyvuopio |
//|                                             https://www.mql5.com |
//|                                                                  |
//| Changes being implemented (compared to previous version):        | 
//| - Close above/below candle buffer high/low (NOT APPLIED)         |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Jasper Niittyvuopio"
#property link      "https://www.mql5.com"
#property version   "1.00"

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
ENUM_TIMEFRAMES Timeframe = Period(); //Strategy timeframe
string           Bias = "no bias"; //Current bias?

//Risk Metrics
input bool   RiskCompounding   = true;  //Use Compounded Risk Method?
double       StartingEquity    = 0.0;    //Starting Equity
double       CurrentEquityRisk = 0.0;    //Equity that will be risked per trade
input double MaxLossPrc        = 0.02;   //Percent Risk Per Trade
input double AtrLossMulti      = 2.5;    //ATR Loss Multiplier

//ATR Handle and Variables
int HandleAtr;
input int AtrPeriod = 10; //ATR Period

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

  // Set up handle for ATR indicator on the initialisation of expert
  HandleAtr = iATR(Symbol(),Timeframe,AtrPeriod);
  Print("Handle for TrendFollowing ATR /", Symbol()," / ", EnumToString(Timeframe),"successfully created");
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

    //Initiate String for indicatorMetrics Variable. This will reset variable each time OnTick function runs.
    IndicatorMetrics ="";  
    
    StringConcatenate(IndicatorMetrics,Symbol()," | Last Processed(TrendFollowing): ",TimeLastTickProcessed);

    //Money Management - ATR
    double CurrentAtr = GetATRValue(HandleAtr); //Gets ATR value double using custom function - convert double to string as per symbol digits
    StringConcatenate(IndicatorMetrics, IndicatorMetrics, " | ATR(TrendFollowing): ", CurrentAtr);

    //Strategy Trigger - Dungeon Breakout (TrendFollowing)
    string OpenSignalBreakout = GetTrendFollowingSignal();
    StringConcatenate(IndicatorMetrics, IndicatorMetrics, " | Signal(TrendFollowing): ", OpenSignalBreakout);   
  
    //Enter Trade
    if(OpenSignalBreakout == "long")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_BUY,CurrentAtr);
      if(NewTicket != 0)
      {
        TicketNumber = NewTicket;
      }
    }
    else if(OpenSignalBreakout == "short")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_SELL,CurrentAtr);
      if(NewTicket != 0)
        {
          TicketNumber = NewTicket;
        }
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
ulong ProcessTradeOpen(ENUM_ORDER_TYPE OrderType, double CurrentAtr)
{
  //Set symbol string and variables
   string CurrentSymbol   = Symbol();  
   double Price           = 0;
   double StopLossPrice   = 0;
   
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
    StopLossPrice   = NormalizeDouble(Price - CurrentAtr*AtrLossMulti, Digits());
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "no positions")
  {
    //SELL
    Message = "No existing positions";
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + CurrentAtr*AtrLossMulti, Digits());
    Bias = "bear";
  }
  else if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "sell")
  {
    //CLOSE ORDERS AND BUY
    Message         = CloseExistingPosition();
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - CurrentAtr*AtrLossMulti, Digits());
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "buy")
  {
    //CLOSE ORDERS AND SELL
    Message         = CloseExistingPosition();
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + CurrentAtr*AtrLossMulti, Digits());
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
  Trade.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,0,InpTradeComment);
  //Get Position Ticket Number
  Ticket = PositionGetTicket(0);

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