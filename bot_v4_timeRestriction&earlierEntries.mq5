#property copyright "Matia Rasetina, Adrian Hajdin"
#property version   "1.0"

input int MAPeriodShort = 1;
input int MAPeriodLong = 2;
input int MAShift = 0;
input ENUM_MA_METHOD MAMethodS = MODE_SMA;
input ENUM_MA_METHOD MAMethodL = MODE_SMA;
input ENUM_APPLIED_PRICE MAPrice = PRICE_CLOSE;
input double stopLoss = 0.001;
input double takeProfit = 0.003;
input double volume = 1;
//input bool trade = false;

//the distance between current price and stop loss.
input double TrailingStopDistance = 0.0006;

//the amount which the stop loss will increase.
input double TrailingStopStep = 0.0001;

input bool UseNewMethod = true;

input bool      TimeControlEnabled = true;                   //Set true to enable time control, false to Full access.
input datetime  TimeControlStart = D'2020.01.01 00:00:00';   //Time control start
input datetime  TimeControlEnd = D'2020.01.01 08:00:00';     //Time control end

enum orderType{
    orderBuy,
    orderSell
};

datetime candleTimes[], lastCandleTime;

MqlTradeRequest request;
MqlTradeResult result;
MqlTradeCheckResult checkResult;


bool checkTradeTimeAllowed(){
    if(!TimeControlEnabled) return true;

    static bool date_error_notify = false;
    if(TimeControlStart >= TimeControlEnd){
        if(!date_error_notify){
            MessageBox(StringFormat("Start time %s must earlier than end time %s. \nThe trade time limits has been disabled, please check.",
                                    TimeToString(TimeControlStart, TIME_DATE | TIME_SECONDS),
                                    TimeToString(TimeControlEnd, TIME_DATE | TIME_SECONDS)));
            date_error_notify = true;
        }

        return true;
    }

    MqlDateTime dtStart, dtEnd, dtNow;
    TimeToStruct(TimeControlStart, dtStart);
    TimeToStruct(TimeControlEnd, dtEnd);
    TimeToStruct(TimeCurrent(), dtNow);

    if((dtNow.hour >= dtStart.hour && dtNow.min >= dtStart.min)
            && ((dtNow.hour < dtEnd.hour) || (dtNow.hour == dtEnd.hour && dtNow.min < dtEnd.min))){
        return false;
    }

    return true;
}

bool checkNewCandle(datetime &candles[], datetime &last){
    bool newCandle = false;

    CopyTime(_Symbol, _Period, 0, 3, candles);

    if(last != 0){
        if(candles[0] > last){
            newCandle = true;
            last = candles[0];
        }
    }
    else{
        last = candles[0];
    }

    return newCandle;
}


void tryTrailingStop(){
    if(TrailingStopStep == 0 || TrailingStopDistance == 0){
        //or print a alert here.
        return;
    }

    long type = WRONG_VALUE;
    long posID = 0;

    ZeroMemory(request);

    if(PositionSelect(_Symbol)){
        type = PositionGetInteger(POSITION_TYPE);
        posID = PositionGetInteger(POSITION_IDENTIFIER);
        request.tp = PositionGetDouble(POSITION_TP);
    }
    else{
        return;
    }

    bool send_request = false;
    double price_open = PositionGetDouble(POSITION_PRICE_OPEN);
    double current_sl = PositionGetDouble(POSITION_SL), new_sl = 0;
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK), bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    if(type == POSITION_TYPE_BUY){
        double next_sl = price_open + TrailingStopStep;
        while(bid >= (next_sl + TrailingStopDistance)){
            new_sl = next_sl;
            next_sl += TrailingStopStep;
        }

        new_sl = NormalizeDouble(new_sl, _Digits);

        if(new_sl > 0 && new_sl > current_sl){
            send_request = true;
        }
    }
    else if(POSITION_TYPE_SELL){
        double next_sl = price_open - TrailingStopStep;
        while(ask <= (next_sl - TrailingStopDistance)){
            new_sl = next_sl;
            next_sl -= TrailingStopStep;
        }

        new_sl = NormalizeDouble(new_sl, _Digits);

        if(new_sl > 0 && new_sl < current_sl){
            send_request = true;
        }
    }

    if(!send_request) return;

    request.position = PositionGetInteger(POSITION_TICKET);
    request.action  = TRADE_ACTION_SLTP;                    // type of trade operation
    request.symbol = _Symbol;                               // symbol
    request.sl = new_sl;

    ZeroMemory(result);
    if(OrderSend(request, result)){
        Print("Modify with new stoploss: ", new_sl);
    }
    else{
        Print("Modify ERROR :" + IntegerToString(result.retcode));
    }
}

bool closePosition()
{
    double vol = 0;
    long type = WRONG_VALUE;
    long posID = 0;

    ZeroMemory(request);

    if(PositionSelect(_Symbol)){
        vol = PositionGetDouble(POSITION_VOLUME);
        type = PositionGetInteger(POSITION_TYPE);
        posID = PositionGetInteger(POSITION_IDENTIFIER);

        request.sl = PositionGetDouble(POSITION_SL);
        request.tp = PositionGetDouble(POSITION_TP);
    }
    else{
        return false;
    }

    request.symbol = _Symbol;
    request.volume = vol;
    request.action = TRADE_ACTION_DEAL;
    request.type_filling = ORDER_FILLING_FOK;
    request.deviation = 10;
    double price = 0;


    if(type == POSITION_TYPE_BUY){
        //Buy
        request.type = ORDER_TYPE_BUY;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
    }
    else if(POSITION_TYPE_SELL){
        //Sell
        request.type = ORDER_TYPE_SELL;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
    }

    request.price = price;

    if(OrderCheck(request, checkResult)){
        Print("Checked!");
    }
    else{
        Print("Not correct! ERROR :" + IntegerToString(checkResult.retcode));
        return false;
    }

    if(OrderSend(request, result)){
        Print("Successful send!");
    }
    else{
        Print("Error order not send!");
        return false;
    }

    if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED){
        Print("Trade Placed!");
        return true;
    }
    else{
        return false;
    }

}


bool makePosition(orderType type){
    ZeroMemory(request);
    request.symbol = _Symbol;
    request.volume = volume;
    request.action = TRADE_ACTION_DEAL;
    request.type_filling = ORDER_FILLING_FOK;
    double price = 0;

    if(type == orderBuy){
        //Buy
        request.type = ORDER_TYPE_BUY;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_ASK), _Digits);
        request.sl = NormalizeDouble(price - stopLoss, _Digits);
        request.tp = NormalizeDouble(price + takeProfit, _Digits);

    }
    else if(type == orderSell){
        //Sell
        request.type = ORDER_TYPE_SELL;
        price = NormalizeDouble(SymbolInfoDouble(_Symbol, SYMBOL_BID), _Digits);
        request.sl = NormalizeDouble(price + stopLoss, _Digits);
        request.tp = NormalizeDouble(price - takeProfit, _Digits);

    }
    request.deviation = 10;
    request.price = price;


    if(OrderCheck(request, checkResult)){
        Print("Checked!");
    }
    else{
        Print("Not Checked! ERROR :" + IntegerToString(checkResult.retcode));
        return false;
    }

    if(OrderSend(request, result)){
        Print("Order sent!");
    }
    else{
        Print("Order not sent, error");
        return false;
    }

    if(result.retcode == TRADE_RETCODE_DONE || result.retcode == TRADE_RETCODE_PLACED){
        Print("Trade Placed!");
        return true;
    }
    else{
        return false;
    }
}


int OnInit()
{
    ArraySetAsSeries(candleTimes, true);
    return(0);
}

void OnTick()
{
    if(checkNewCandle(candleTimes, lastCandleTime)){
        if(checkTradeTimeAllowed() == false){
            return;
        }

        double maS[];
        double maL[];
        ArraySetAsSeries(maS, true);
        ArraySetAsSeries(maL, true);
        double candleClose[];
        ArraySetAsSeries(candleClose, true);
        int maSHandle = iMA(_Symbol, _Period, MAPeriodShort, MAShift, MAMethodS, MAPrice);
        int maLHandle = iMA(_Symbol, _Period, MAPeriodLong, MAShift, MAMethodL, MAPrice);
        CopyBuffer(maSHandle, 0, 0, 3, maS);
        CopyBuffer(maLHandle, 0, 0, 3, maL);
        CopyClose(_Symbol, _Period, 0, 3, candleClose);

        if(UseNewMethod){
            if(((maS[2] < maL[2]) && (maS[1] > maL[1])) || ((maS[1] < maL[1]) && (maS[0] > maL[0]))){
                //cross up
                Print("Buy order initiated!");
                closePosition();
                makePosition(orderBuy);
            }

            if(((maS[2] > maL[2]) && (maS[1] < maL[1])) || ((maS[1] > maL[1]) && (maS[0] < maL[0]))){
                //cross down
                Print("Sell order initiated!");
                closePosition();
                makePosition(orderSell);
            }
        }
        else{
            if((maS[1] < maL[1]) && (maS[0] > maL[0])){
                //cross up
                Print("Buy order initiated!");
                closePosition();
                makePosition(orderBuy);

            }
            else if((maS[1] > maL[1]) && (maS[0] < maL[0])){
                //cross down
                Print("Sell order initiated!");
                closePosition();
                makePosition(orderSell);

            }
            else{
                //trailing
            }
        }
    }

//tryTrailingStop every tick
    tryTrailingStop();

}
