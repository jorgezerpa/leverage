Ideas for graph UI:
- Have keepers that call "eventCreator" functions every X time. So we create events like "OneMinuteEvent", "ThreeMinutesEvent", "OneHourEvent", etc. Then, when I want to fetch this, I just fetch backwards the requeired timeframe event 

How will be the liquidation process?
- Fetch the current price of the quoute asset 
- Go to positions[tradingPair].[price].[positions] vec 
- Loop for each position and call liquidate on each on them
- THE PROBLEM: how can we efficiently liquidate the under-price positions to?

-----

position == map[tradingPairHash][positionId]

So, to check for liquidations, a keeper or liquidation bot will:
1. Fetch the lastLiquidationId