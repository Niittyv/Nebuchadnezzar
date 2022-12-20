//+------------------------------------------------------------------+
//|                                               trend_follower.mq5 |
//|                                              Jasper Niittyvuopio |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Jasper Niittyvuopio"
#property link      "https://www.mql5.com"
#property version   "1.00"

//Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions
CTrade   *Trade_TrendFollowing;           //Declaire Trade as pointer to CTrade class
CTrade   *Trade_MeanReversion;

//Setup Variables
input int                InpMagicNumber  = 0000000;     //Unique identifier for this expert advisor (use symbol identifiers)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; //Applied price for indicators
input string             InpTradeComment = __FILE__;    //Optional comment for trades

//Global Variables
int             TicksReceivedCount  = 0; //Counts the number of ticks from oninit function

//Strategy specific settings

//TrendFollowing strategy
input int       BufferCandles_TrendFollowing = 20; //Dungeon breakout period (TrendFollowing)
string          IndicatorMetrics_TrendFollowing    = "";
int             TicksProcessedCount_TrendFollowing = 0; //Counts the number of ticks proceeded from oninit function based off candle opens only
static datetime TimeLastTickProcessed_TrendFollowing;   //Stores the last time a tick was processed based off candle opens only
input ENUM_TIMEFRAMES Timeframe_TrendFollowing = PERIOD_D1; //TrendFollowing strategy timeframe
input bool DisableTrades_Trendfollowing = false; //Disable trades for TrendFollowing strategy (bias will still be generated)
int MagicNumber_TrendFollowing = 1000; //MagicnNumber for TrendFollowing trades

//MeanReversion strategy
input int       BufferCandles_MeanReversion = 20; //Dungeon breakout period (MeanReversion)
string          IndicatorMetrics_MeanReversion    = "";
int             TicksProcessedCount_MeanReversion = 0; //Counts the number of ticks proceeded from oninit function based off candle opens only
static datetime TimeLastTickProcessed_MeanReversion;   //Stores the last time a tick was processed based off candle opens only
input bool MeanReversion = false; //Enable MeanReversion strategy
input ENUM_TIMEFRAMES Timeframe_MeanReversion = PERIOD_M30; //MeanReversion strategy timeframe
string Bias = "no bias"; //Current long-term bias?
int MagicNumber_MeanReversion = 2000; //MagicnNumber for MeanReversion trades

//Risk Metrics
input bool   RiskCompounding   = true;  //Use Compounded Risk Method?
double       StartingEquity    = 0.0;    //Starting Equity
double       CurrentEquityRisk = 0.0;    //Equity that will be risked per trade
input double MaxLossPrc_TrendFollowing        = 0.02;   //Percent Risk Per Trade TrendFollowing
input double MaxLossPrc_MeanReversion         = 0.02;   //Percent Risk Per Trade MeanReversion
input double AtrLossMulti_TrendFollowing      = 2.5;    //ATR Loss Multiple TrendFollowing
input double AtrLossMulti_MeanReversion       = 2.5;    //ATR Loss Multiple MeanReversion

//ATR Handle and Variables
int HandleAtr_TrendFollowing;
int HandleAtr_MeanReversion;
input int AtrPeriod_TrendFollowing = 10;
input int AtrPeriod_MeanReversion = 14;

//Store ticketnumbers
ulong TicketNumber_TrendFollowing = 0;
ulong TicketNumber_MeanReversion = 0;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
  //Declare magic numbers for TrendFollowing and MeanReversion trades
  MagicNumber_TrendFollowing = MagicNumber_TrendFollowing + InpMagicNumber;
  MagicNumber_MeanReversion = MagicNumber_MeanReversion + InpMagicNumber;
  Print("MagicNumber_TrendFollowing", MagicNumber_TrendFollowing);
  Print("MagicNumber_MeanReversion", MagicNumber_MeanReversion);

  //Declare magic number for all trades
  Trade_TrendFollowing = new CTrade();
  Trade_TrendFollowing.SetExpertMagicNumber(MagicNumber_TrendFollowing);

  Trade_MeanReversion = new CTrade();
  Trade_MeanReversion.SetExpertMagicNumber(MagicNumber_MeanReversion);

  //Store starting equity onInit
  StartingEquity  = AccountInfoDouble(ACCOUNT_EQUITY);

  // Set up handle for ATR indicator on the initialisation of expert
  HandleAtr_TrendFollowing = iATR(Symbol(),Timeframe_TrendFollowing,AtrPeriod_TrendFollowing);
  Print("Handle for TrendFollowing ATR /", Symbol()," / ", EnumToString(Timeframe_TrendFollowing),"successfully created");
  HandleAtr_MeanReversion = iATR(Symbol(),Timeframe_MeanReversion,AtrPeriod_MeanReversion);
  Print("Handle for MeanReversion ATR /", Symbol()," / ", EnumToString(Timeframe_MeanReversion),"successfully created");
  return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
  //Remove indicator handle from Metatrader Cache
  IndicatorRelease(HandleAtr_TrendFollowing);
  IndicatorRelease(HandleAtr_MeanReversion);
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
  bool IsNewCandle_TrendFollowing = false;
  if(TimeLastTickProcessed_TrendFollowing != iTime(Symbol(),Timeframe_TrendFollowing,0))
  {
    IsNewCandle_TrendFollowing = true;
    TimeLastTickProcessed_TrendFollowing=iTime(Symbol(),Timeframe_TrendFollowing,0);
  }

  //If there is a new candle for TrendFollowing strategy, process any trades
  if(IsNewCandle_TrendFollowing == true)
  {
    string strategy = "TrendFollowing";
    //Counts the number of ticks processed
    TicksProcessedCount_TrendFollowing++;

    //Initiate String for indicatorMetrics Variable. This will reset variable each time OnTick function runs.
    IndicatorMetrics_TrendFollowing ="";  
    StringConcatenate(IndicatorMetrics_TrendFollowing,Symbol()," | Last Processed(TrendFollowing): ",TimeLastTickProcessed_TrendFollowing);

    //Money Management - ATR
    double CurrentAtr_TrendFollowing = GetATRValue(HandleAtr_TrendFollowing); //Gets ATR value double using custom function - convert double to string as per symbol digits
    StringConcatenate(IndicatorMetrics_TrendFollowing, IndicatorMetrics_TrendFollowing, " | ATR(TrendFollowing): ", CurrentAtr_TrendFollowing);

    //Strategy Trigger - Dungeon Breakout (TrendFollowing)
    string OpenSignalBreakout = GetTrendFollowingSignal(Timeframe_TrendFollowing,BufferCandles_TrendFollowing);
    StringConcatenate(IndicatorMetrics_TrendFollowing, IndicatorMetrics_TrendFollowing, " | Signal(TrendFollowing): ", OpenSignalBreakout);   
  
    //Enter Trade
    if(OpenSignalBreakout == "long")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_BUY,CurrentAtr_TrendFollowing,AtrLossMulti_TrendFollowing,MagicNumber_TrendFollowing,strategy,MaxLossPrc_TrendFollowing);
      if(NewTicket != 0)
      {
        TicketNumber_TrendFollowing = NewTicket;
      }
    }
    else if(OpenSignalBreakout == "short")
    {
      ulong NewTicket = ProcessTradeOpen(ORDER_TYPE_SELL,CurrentAtr_TrendFollowing,AtrLossMulti_TrendFollowing,MagicNumber_TrendFollowing,strategy,MaxLossPrc_TrendFollowing);
      if(NewTicket != 0)
      {
        TicketNumber_TrendFollowing = NewTicket;
      }
    }
  }


  //If there is a new candle for MeanReversion, process any trades (if MeanReversion is enabled)
   
  //Comment for user
   Comment("\n\rExpert_TrendFollowing: ", MagicNumber_TrendFollowing, "\n\r",
         "Expert_MeanReversion: ", MagicNumber_MeanReversion, "\n\r",
         "MT5 Server Time: ", TimeCurrent(), "\n\r",
         "MeanReversion enabled: ", MeanReversion,"\n\r",
         "Timeframe (TrendFollowing): ", EnumToString(Timeframe_TrendFollowing),"\n\r",
         "Timeframe (MeanReversion): ", EnumToString(Timeframe_MeanReversion),"\n\r",
         "\n\r",
         "Ticks Received: ", TicksReceivedCount,"\n\r",
         "Ticks Processed (TrendFollowing): ", TicksProcessedCount_TrendFollowing,"\n\r",
         "Ticks Processed (MeanReversion): ", TicksProcessedCount_MeanReversion,"\n\r",
         "Bias: ", Bias,"\n\r",
         "\n\r",
         "Symbols Traded: \n\r", 
         "\n\r",
         IndicatorMetrics_TrendFollowing, "\n\r",
         "\n\r",
         IndicatorMetrics_MeanReversion, "\n\r");

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
string GetTrendFollowingSignal(ENUM_TIMEFRAMES timeframe, int period)
{
  //Check last closed candle color by comparing open and close prices
  double CurrentClose = NormalizeDouble(iClose(Symbol(),timeframe,0), 10);
  double LastOpen = NormalizeDouble(iOpen(Symbol(),timeframe,1), 10);
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
    //Compare current candle close to previous candle close highs
    int HighestIndex = iHighest(Symbol(),timeframe,MODE_CLOSE,period,2);
    double HighestPreviousClose = NormalizeDouble(iClose(Symbol(),timeframe,HighestIndex), 10);
    if(CurrentClose > HighestPreviousClose)
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
    //Compare current candle close to previous candle close lows
    int LowestIndex = iLowest(Symbol(),timeframe,MODE_CLOSE,period,2);
    double LowestPreviousClose = NormalizeDouble(iClose(Symbol(),timeframe,LowestIndex), 10);
    if(CurrentClose < LowestPreviousClose)
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
    //function has failed
    return("ERROR");
  }
}


//Processes open trades for buy and sell
ulong ProcessTradeOpen(ENUM_ORDER_TYPE OrderType, double CurrentAtr, double AtrLossMulti, int MagicNumber, string strategy, double MaxLossPrc)
{
  //Set symbol string and variables
   string CurrentSymbol   = Symbol();  
   double Price           = 0;
   double StopLossPrice   = 0;
   
   string message = "";
   ulong ticket = 0;

  //Check for same type existing position
  string ExistingPosition = FindExistingPosition(MagicNumber);

  //Close existing orders and calculate price and stop loss
  if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "no positions")
  {
    //BUY
    message = "No existing positions";
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - CurrentAtr*AtrLossMulti, Digits());
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "no positions")
  {
    //SELL
    message = "No existing positions";
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + CurrentAtr*AtrLossMulti, Digits());
    Bias = "bear";
  }
  else if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "sell")
  {
    //CLOSE ORDERS AND BUY
    message = CloseExistingPosition(MagicNumber, strategy);
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_ASK), Digits());
    StopLossPrice   = NormalizeDouble(Price - CurrentAtr*AtrLossMulti, Digits());
    Bias = "bull";
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "buy")
  {
    //CLOSE ORDERS AND SELL
    message = CloseExistingPosition(MagicNumber, strategy);
    Price           = NormalizeDouble(SymbolInfoDouble(CurrentSymbol, SYMBOL_BID), Digits());
    StopLossPrice   = NormalizeDouble(Price + CurrentAtr*AtrLossMulti, Digits());
    Bias = "bear";
  }
  else if(OrderType == ORDER_TYPE_BUY && ExistingPosition == "buy")
  {
    //Do nothing
    message = "Already in long";
    return(ticket);
  }
  else if(OrderType == ORDER_TYPE_SELL && ExistingPosition == "sell")
  {
    //Do nothing
    message = "Already in short";
    return(ticket);
  }
  else
  {
    Print("SYSTEM ERROR");
    return(ticket);
  }

  Print("What happened to existing positions?: ", message);

  //Get lot size
  double LotSize = OptimalLotSize(CurrentSymbol,Price,StopLossPrice, MaxLossPrc);

  //Enter Trade
  if(strategy == "TrendFollowing")
  {
    Trade_TrendFollowing.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,0,InpTradeComment);
    //Get Position Ticket Number
    ulong  Ticket = PositionGetTicket(0);
  }
  else if(strategy == "MeanReversion")
  {
    Trade_MeanReversion.PositionOpen(CurrentSymbol,OrderType,LotSize,Price,StopLossPrice,0,InpTradeComment);
    //Get Position Ticket Number
    ulong  Ticket = PositionGetTicket(0);
  }
  return ticket;
}

//Finds existing trade with magic number
string FindExistingPosition(int MagicNumber)
{
  for(int i=0; i<(int)PositionsTotal(); i++)
  {
    ulong ticket = PositionGetTicket(i);
    if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)
    {
      return("buy");
    }
    else if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_SELL)
    {
      return("sell");
    }
  }
  return("no positions");
}

//Closes existing trade with magic number
string CloseExistingPosition(int MagicNumber, string strategy)
{
  for(int i=0; i<(int)PositionsTotal(); i++)
  {
    ulong ticket = PositionGetTicket(i);
    if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && strategy == "TrendFollowing")
    {
     Trade_TrendFollowing.PositionClose(ticket);
    }
    else if(PositionGetInteger(POSITION_MAGIC) == MagicNumber && strategy == "MeanReversion")
    {
      Trade_MeanReversion.PositionClose(ticket);
    }
  }
  return("positions closed");
}

//Finds the optimal lot size for the trade
double OptimalLotSize(string CurrentSymbol, double EntryPrice, double StopLoss, double MaxLossPrc)
{
   //Set symbol string and calculate point value
   double TickSize      = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_SIZE);
   double TickValue     = SymbolInfoDouble(CurrentSymbol,SYMBOL_TRADE_TICK_VALUE);
   if(SymbolInfoInteger(CurrentSymbol,SYMBOL_DIGITS) <= 3)
      TickValue = TickValue/100;
   double PointAmount   = SymbolInfoDouble(CurrentSymbol,SYMBOL_POINT);
   double TicksPerPoint = TickSize/PointAmount;
   double PointValue    = TickValue/TicksPerPoint;

   //Calculate risk based off entry and stop loss level by pips
   double RiskPoints = MathAbs((EntryPrice - StopLoss)/TickSize);
      
   //Set risk model - Fixed or compounding
   if(RiskCompounding == true)
      CurrentEquityRisk = AccountInfoDouble(ACCOUNT_EQUITY);
   else
      CurrentEquityRisk = StartingEquity; 

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