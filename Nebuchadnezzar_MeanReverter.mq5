//+------------------------------------------------------------------+
//|                                             v1meanreversion.mq5  |
//|                                              Jasper Niittyvuopio |
//|                                             https://www.mql5.com |
//|                                                                  |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Jasper Niittyvuopio"
#property link      "https://www.mql5.com"
#property version   "1.00"

//Include Functions
#include <Trade\Trade.mqh> //Include MQL trade object functions
CTrade   *Trade;           //Declaire Trade as pointer to CTrade class

//Setup Variables
input int                InpMagicNumber  = 2000000;     //Unique identifier for this expert advisor (use symbol identifiers)
input ENUM_APPLIED_PRICE InpAppliedPrice = PRICE_CLOSE; //Applied price for indicators
input string             InpTradeComment = __FILE__;    //Optional comment for trades

//Global Variables
int             TicksReceivedCount  = 0; //Counts the number of ticks from oninit function

//Strategy specific settings

//MeanReversion strategy
input int       BufferCandles = 20; //Dungeon breakout period (MeanReversion)
string          IndicatorMetrics    = "";
int             TicksProcessedCount = 0; //Counts the number of ticks proceeded from oninit function based off candle opens only
static datetime TimeLastTickProcessed;   //Stores the last time a tick was processed based off candle opens only
input bool      TimeoutDelay = false; //Timeout delay enabled (close all positions)
input int       TimeoutDelayPeriods = 1; //Timeout delay periods
ENUM_TIMEFRAMES Timeframe = Period(); //Strategy timeframe

//Risk Metrics
input bool   RiskCompounding   = true;   //Use Compounded Risk Method?
double       StartingEquity    = 0.0;    //Starting Equity
double       CurrentEquityRisk = 0.0;    //Equity that will be risked per trade
input double MaxLossPrc        = 0.02;   //Percent Risk Per Trade
input double StopLossSize     = 0.1;      //Stop Loss Size. 0.xx for yen, 0.0xx for others (ten pips)
input bool   ApplyTakeProfit   = false;  //Apply Take Profit
input double TakeProfitMuliplier = 1;     //Take Profit multiplier

//Store ticketnumbers
ulong TicketNumber = 0;

//Disable trading between certain hours and months
input string StartTime="2:00:00"; //Market open
input string EndTime="2:15:00"; //Market close
input int TradeBanMonth1 = 0; //Trading disabled first month (1-12)
input int TradeBanMonth2 = 0; //Trading disabled second month (1-12)
input int TradeBanMonth3 = 0; //Trading disabled third month (1-12)
input int TradeBanMonth4 = 0; //Trading disabled fourth month (1-12)
input bool CloseTradesDuringVacation = false; //Close open trade when vacation starts?

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
  datetime now = TimeCurrent();
  MqlDateTime time;
  TimeToStruct(now,time);
  if(time.mon != TradeBanMonth1 && time.mon != TradeBanMonth2 && time.mon != TradeBanMonth3 && time.mon != TradeBanMonth4)
  {
    datetime begin = StringToTime(StartTime), stop = StringToTime(EndTime);
    bool isTime = stop <= begin ? now >= begin || now < stop : now >= begin && now < stop;
    if(isTime)
    {
      ////////////////////////////////////////////////////////////////
      //Counts the number of ticks received  
      TicksReceivedCount++; 

      //Check for new candles for MeanReversion strategy
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
        
        StringConcatenate(IndicatorMetrics,Symbol()," | Last Processed(MeanReversion): ",TimeLastTickProcessed);

        //Strategy Trigger - Dungeon Breakout (MeanReversion)
        string OpenSignalBreakout = GetMeanReversionSignal();
        StringConcatenate(IndicatorMetrics, IndicatorMetrics, " | Signal(MeanReversion): ", OpenSignalBreakout);   

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

        //Close all trades if time is up and timeout delay is enabled
        if(TimeoutDelay && TicksProcessedCount >= TimeoutDelayPeriods)
        {
          string TradesClosedMessage = CloseExistingPosition();
          Print("Time's up! Ari can't close for shit. Coffee is for closers only -- ", TradesClosedMessage);
        }
      }
    }
  }
  else if(CloseTradesDuringVacation)
  {
    string TradesClosedMessage = CloseExistingPosition();
    Print("Happy vacation near the palm trees! -- ", TradesClosedMessage);
  }
   
  //Comment for user
   Comment("\n\rExpert_MeanReversion: ", InpMagicNumber, "\n\r",
         "MT5 Server Time: ", TimeCurrent(), "\n\r",
         "Timeframe (MeanReversion): ", EnumToString(Timeframe),"\n\r",
         "\n\r",
         "Ticks Received: ", TicksReceivedCount,"\n\r",
         "Ticks Processed (MeanReversion): ", TicksProcessedCount,"\n\r",
         "\n\r",
         "Symbols Traded: \n\r", 
         "\n\r",
         IndicatorMetrics, "\n\r");

  }
//+------------------------------------------------------------------+
//| Custom function                                                  |
//+------------------------------------------------------------------+

//Custom Function to get dungeon breakout (MeanReversion) signals
string GetMeanReversionSignal()
{
  //Check last closed candle color by comparing open and close prices
  double CurrentClose = NormalizeDouble(iClose(Symbol(),Timeframe,1), 10);
  double LastOpen = NormalizeDouble(iOpen(Symbol(),Timeframe,1), 10);
  Print("last open: ", LastOpen);
  Print("current close: ", CurrentClose);
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
    int HighestIndex = iHighest(Symbol(),Timeframe,MODE_CLOSE,BufferCandles,2);
    double HighestPrevious = NormalizeDouble(iClose(Symbol(),Timeframe,HighestIndex), 10);
    Print("highest previous: ", HighestPrevious);
    if(CurrentClose > HighestPrevious)
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
  else if(LastCandleColor == "bear")
  {
    //Compare current candle close to previous candle close lows
    int LowestIndex = iLowest(Symbol(),Timeframe,MODE_CLOSE,BufferCandles,2);
    double LowestPrevious = NormalizeDouble(iClose(Symbol(),Timeframe,LowestIndex), 10);
    Print("lowest previous: (ari säilyttää muuten marmorikuulia persereijässä)", LowestPrevious);
    if(CurrentClose < LowestPrevious)
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