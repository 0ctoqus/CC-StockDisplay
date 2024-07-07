-- ==================================================================================================================================================================================================
-- CC:StockDisplay by Octopus
--
-- This script is designed to display a stock value on a Computecraft monitor inside Minecraft.
-- It currently fetches data from the Yahoo Finance API and displays it.
--
-- Customization:
-- You can set the different colors just below, as well as the stock you want to display.
--
-- How it works:
-- 1. Automatically download the display lib from Github, allowing us to have an improved resolution for display, but comes with some drawbacks.
-- 2. Registers the script to startup, so it will start automatically with the computer (and so also on world load).
-- 3. Checks if you already have a stock selected to display.
--    If not, it will prompt you to select one stock with an iterval and range. It will then save it to a config file for later use.
--    If you want to change the selection, you can do it by changing the local stocks array and deleting if it exists the selected_stock_config.json.
-- 4. Fetches the current GMT real world time from the internet to later calculate market open and close.
-- 5. Sets the display to an external monitor if possible.
-- 6. Downloads and loads the stock data (in this step, we also remove empty values by discarding them).
-- 7. Displays the graph and stock information based on the collected values.
--
-- Limitations:
-- Currently, the script can only display one stock per computer.
-- No axes are currently displayed on the graph.
-- Each candles represent the current non-null close value versus the previous non-null close value to avoid missing data points. So no 100% real world timeframe handling or accurate display.
-- Pixels may be missing on the graph due to the current library being used to display smaller characters.
-- ==================================================================================================================================================================================================

-- Set the colors of display
-- You can select from white, orange, magenta, lightBlue, yellow, lime, pink, gray, lightGray, cyan, purple, blue, brown, green, red, black
local defaultTextColor = colors.white
local buyColor = colors.lime
local sellColor = colors.red
local backgroundColor = colors.black

-- Define a table of stock symbols and regions
-- You can look in the URL of quotes selected from https://finance.yahoo.com/lookup to add them here
local stocks = {
    {"AAPL","US"},
    {"GOOGL","US"},
    {"AMZN","US"},
    {"FB","US"},
    {"MSFT","US"},
    {"TSLA","US"},
    {"BABA","US"},
    {"NQ=F", "US"},
    {"LQQ.PA", "EU"},
}

-- Define a table of intervals
local intervals = {{"1m", nil}, {"2m", nil}, {"5m", nil}, {"15m", nil}, {"30m", nil}, {"60m", nil}, {"90m", nil},
                   {"1h", nil}, {"1d", nil}, {"5d", nil}, {"1wk", nil}, {"1mo", nil}, {"3mo", nil}}

-- Define a table of ranges
local ranges = {{"1d", nil}, {"5d", nil}, {"1mo", nil}, {"3mo", nil}, {"6mo", nil}, {"1y", nil}, {"2y", nil},
                {"5y", nil}, {"10y", nil}, {"ytd", nil}, {"max", nil}}

-- Custom print function that can be used to debug and always print to Term
local function printDebug(message)
    local oldOutput = term.current()
    term.redirect(term.native())
    local color
    if string.match(message, "Info") then
        color = buyColor
    elseif string.match(message, "Error") then
        color = sellColor
    else
        color = defaultTextColor
    end
    term.setTextColor(color)
    print(message)
    term.setTextColor(defaultTextColor)
    term.redirect(oldOutput)
end

-- Function to load the pixelbox_lite.lua library from https://github.com/9551-Dev/pixelbox_lite
local function loadPixelBoxLiteLib(libFileName)
    -- Check if the pixelbox_lite.lua file already exists
    if not fs.exists(libFileName) then
        -- Download the pixelbox_lite.lua file using http.get()
        local response = http.get("https://raw.githubusercontent.com/9551-Dev/pixelbox_lite/master/" .. libFileName)
        if response then
            local file = fs.open(libFileName, "w")
            file.write(response.readAll())
            file.close()
            response.close()
            printDebug("Info: Downloaded pixelbox_lite.lua")
        else
            printDebug("Error: Failed to download " .. libFileName)
            return nil
        end
    else
        printDebug("Info: Lib " .. libFileName .. " already exists")
    end
    -- Load the pixelbox_lite.lua library
    dofile(libFileName)
    return PixelBox
end

local function registerStartup(scriptName)
    printDebug("Info: Checking script is set to startup")
    local startupFile = fs.open("/startup", "r")
    local scriptAlreadyInStartup = false
    local scriptPath = shell.getRunningProgram()
    local scriptName = fs.getName(scriptPath)
    local startupCommand = "shell.run(\"" .. scriptName .. "\")"

    -- Check if the script is already in the startup file
    if startupFile then
        local line = startupFile.readLine()
        while line do
            if line == startupCommand then
                scriptAlreadyInStartup = true
                break
            end
            line = startupFile.readLine()
        end
        startupFile.close()
    end

    -- If the script is not already in the startup file, add it
    if not scriptAlreadyInStartup then
        printDebug("Info: Registering script for startup")
        startupFile = fs.open("/startup", "a")
        startupFile.writeLine(startupCommand)
        startupFile.close()
    else
        printDebug("Info: Script already registered for startup")
    end
end

-- Function to prompt the user to select a stock and save it to a file
local function selectStock(fileName)
    -- Function to prompt the user to select an option from a list
    local function selectOption(options, currentSelectionText)
        printDebug("Info: Select an option for the " .. currentSelectionText)
        for i, option in ipairs(options) do
            printDebug(i .. ". " .. option[1])
        end
        printDebug("Info: Enter the number you want to select.")

        while true do
            local event, key = os.pullEvent("key")
            if key ~= nil then
                local selection = tonumber(key) - 48
                if selection and selection ~= 292 and selection >= 1 and selection <= #options then
                    return options[selection]
                end
            end
        end
    end
    -- Check if the selected stock file exists
    if not fs.exists(fileName) then
        -- Prompt the user to select a stock
        local selectedStock = selectOption(stocks, "stock")
        printDebug("Info: Selected " .. selectedStock[1] .. ":" .. selectedStock[2])
        os.sleep(1)

        -- Prompt the user to select an interval
        local selectedInterval = selectOption(intervals, "interval")
        printDebug("Info: Selected " .. selectedInterval[1])
        os.sleep(1)

        -- Prompt the user to select a range
        local selectedRange = selectOption(ranges, "range")
        printDebug("Info: Selected " .. selectedRange[1])
        os.sleep(1)

        -- Save the selected stock, interval, and range to a file
        local file = fs.open(fileName, "w")
        local data = {selectedStock, selectedInterval, selectedRange}
        file.write(textutils.serializeJSON(data))
        file.close()
        printDebug("Info: Selected stock, interval, and range saved")
    end
end

-- Function to load the selected stock, interval, and range from a file and set the stockSymbol, interval, and range variables
local function loadSelectedStockParameters(fileName)
    -- Check if the selected stock file exists
    if fs.exists(fileName) then
        -- Open the selected stock file for reading
        local file = fs.open(fileName, "r")
        -- Read the contents of the file
        local contents = file.readAll()
        -- Close the file
        file.close()
        -- Deserialize the JSON contents of the file
        local selectedData = textutils.unserializeJSON(contents)
        -- Set the stockSymbol, interval, and range variables
        local stockSymbol = selectedData[1][1]
        local region = selectedData[1][2]
        local interval = selectedData[2][1]
        local range = selectedData[3][1]
        printDebug("Info: Parameters loaded " .. stockSymbol .. " (" .. region .. ", " .. interval .. ", " .. range ..
                       ")")
        return stockSymbol, region, interval, range
    else
        printDebug("Error: Selected stock file not found.")
    end
end

-- Function to download the current time in GMT format from the WorldTimeAPI
local function getGMTTime()
    local url = "http://worldtimeapi.org/api/timezone/GMT"

    printDebug("Info: Getting current GMT time from internet")
    -- Make the HTTP request
    local response = http.get(url)

    -- Read the response
    if response then
        local data = response.readAll()
        response.close()
        -- Parse the JSON response
        local decoded, pos, err = textutils.unserializeJSON(data)
        -- Retrieve the Unix timestamp
        if decoded and decoded["unixtime"] then
            local timestamp = decoded["unixtime"]
            printDebug("Info: Retrieved current GMT time successful")
            return timestamp
        elseif not decoded then
            printDebug("Error: Failed to parse JSON response")
        else
            printDebug("Error: No unixtime data found in response")
        end
    else
        printDebug("Error: Failed to get current GMT time")
    end
end

-- Function do check if a monitor is connected and init the Pixelbox lib
local function checkDisplay()
    local display = nil
    local sides = {"front", "back", "left", "right", "top", "bottom"}
    for i = 1, #sides do
        local peripheralType = peripheral.getType(sides[i])
        if peripheralType == "monitor" then
            display = peripheral.wrap(sides[i])
            display.setTextScale(0.5)
            term.redirect(display)
            term.clear()
            printDebug("Info: Monitor found to the " .. sides[i])
        end
    end
    if not display then
        printDebug("Info: No monitor found, using term")
        display = term
    end
    display.setBackgroundColor(backgroundColor)
    local box = require("pixelbox_lite").new(term.current())
    return display, box
end

-- Function to load stock data from a file
local function loadStockData(file_name)
    local function removeNilValues(arr)
        local filtered = {}
        for i = 1, #arr do
            if arr[i] ~= textutils.json_null then
                filtered[#filtered + 1] = arr[i]
            end
        end
        return filtered
    end

    local file = fs.open(file_name, "r")
    if not file then
        printDebug("Error: Can't open file")
        os.exit()
    end

    local decoded, pos, err = textutils.unserializeJSON(file.readAll(), {
        parse_null = true
    })
    -- We remove nill values return by the API

    decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"] = removeNilValues(
        decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"])
    file.close()
    return decoded
end

-- Function to download stock data to a file and load it
local function getStockData(stockSymbol, region, interval, range)
    local url = "https://query1.finance.yahoo.com/v8/finance/chart/" .. stockSymbol .. "?region=" .. region ..
                    "&lang=en-US&includePrePost=false&interval=" .. interval .. "&useYfid=true&range=" .. range ..
                    "&corsDomain=finance.yahoo.com&.tsrc=finance"

    -- Make the HTTP request
    local response = http.get(url)

    printDebug("Info: Getting stock data for " .. stockSymbol)
    -- Read the response
    if response then
        local data = response.readAll()
        response.close()
        -- Parse the JSON response
        local decoded, pos, err = textutils.unserializeJSON(data)
        -- Display the stock price
        if decoded and decoded["chart"] then
            -- Save the data to a file
            local file_name = "stock_data.json"
            local file = fs.open(file_name, "w")
            file.write(data)
            file.close()
            printDebug("Info: Saved updated data")
            -- printDebug("Info: Saved data to file" .. file_name)
            -- return loadStockData(file_name)
            return 0
        elseif not decoded then
            printDebug("Error: Failed to parse JSON response")
            return 1
        else
            printDebug("Error: No 'chart' data found in response")
            return 1
        end
    else
        -- printDebug("Error: Failed to get stock data. This could be because of selected parameters. Please delete the select_stock_config.json and select something else")
        printDebug("Error: Failed to retrieve stock data for the selected parameters :(\n" .. "Possible reasons:\n" ..
                       "- The selected stock symbol may be invalid or not found.\n" ..
                       "- The selected interval or range may not be supported for the chosen stock.\n" ..
                       "- There could be a temporary issue with the data provider.\n\n" ..
                       "Please try this to resolve the issue:\n" .. "\t1. Delete the selected_stock_config.json file.\n" ..
                       "\t2. Restart the script and select a different stock or parameters.\n" ..
                       "\t3. Check the stock symbol and try again.")
        return 1
    end
end

-- Function to draw the graph
local function drawGraph(display, box, decoded, numPoints, interval, gmtTimestamp)
    -- Function to draw a line pixel by pixel
    -- Resolution is maximized by using custom characters but the downside is that sometime pixels can be missing from the chart
    local function drawLine(box, x1, y1, x2, y2, color)
        local dx = math.abs(x2 - x1)
        local dy = math.abs(y2 - y1)
        local sx = (x1 < x2) and 1 or -1
        local sy = (y1 < y2) and 1 or -1
        local err = dx - dy

        while true do
            box.canvas[y1][x1] = color
            if x1 == x2 and y1 == y2 then
                break
            end
            local e2 = 2 * err
            if e2 > -dy then
                err = err - dy
                x1 = x1 + sx
            end
            if e2 < dx then
                err = err + dx
                y1 = y1 + sy
            end
        end
    end

    -- Get the right currency symbol if we can
    local function converCurrencySymbol(stockCurrency)
        if stockCurrency == "USD" then
            return "$"
        elseif stockCurrency == "EUR" then
            return "\162"
        else
            return stockCurrency
        end
    end

    -- Function to get min max for the graph depending on display size
    local function getMinMaxNScale(display, box, decoded, numPoints)
        -- Define the scale for the graph
        local minPrice = math.huge
        local maxPrice = -math.huge

        -- We get more data point to get some air around the line
        local c_numPoints = numPoints * 1.5

        -- Iterate over the sorted keys to get min and max prices for scale
        local close_values = decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"]

        local skipped_price = 0
        local i = #close_values

        while i > 0 and i >= #close_values - c_numPoints - skipped_price do
            local price = tonumber(close_values[i])
            if price ~= nil then
                minPrice = math.min(minPrice, price)
                maxPrice = math.max(maxPrice, price)
            else
                skipped_price = skipped_price + 1
            end
            i = i - 1
        end

        -- Set scale
        local XScale = box.width / numPoints
        local displayWidth, displayHeight = display.getSize()
        local YScale = (displayHeight - 1) * 3 / (maxPrice - minPrice) -- We remove one height to have space to display the stock price, Y scaling from lib is term_height*3
        return XScale, YScale, minPrice, maxPrice
    end

    -- Draw lines recursively, starting from the latest close value and working backwards until we reach the last one that can fit on the screen.
    -- 1. By starting from the latest close value, we ensure that all lines fit within the screen boundaries, avoiding any potential overlapping or off-screen rendering issues.
    -- 2. Then by display first value starting to the left, we handle the case when two "pixels" could overlap, in this case we display the most recent one.
    function drawLineRecursively(i, box, close_values, numPoints, skipped_price, maxPrice, XScale, YScale, previousOpen)
        if i > 0 and i >= #close_values - numPoints - skipped_price then
            local current_step = numPoints - (tonumber(#close_values) - i) + skipped_price
            -- local open = tonumber(open_values[i])
            local close = tonumber(close_values[i])
            local draw = false
            if close ~= nil and close ~= textutils.json_null then
                if previousOpen ~= nil and previousOpen ~= textutils.json_null then
                    local x1 = math.floor(current_step * XScale)
                    local x2 = math.floor(current_step * XScale)
                    local y1 = math.floor((maxPrice - previousOpen) * YScale) + 4 -- We adjust the Y value so we don't clip the price display, normaly should be 3 be 4 seems to prevent clipping best
                    local y2 = math.floor((maxPrice - close) * YScale) + 4
                    local color = y1 < y2 and buyColor or sellColor
                    drawLineRecursively(i - 1, box, close_values, numPoints, skipped_price, maxPrice, XScale, YScale,
                        close)
                    drawLine(box, x1, y1, x2, y2, color)
                else
                    drawLineRecursively(i, box, close_values, numPoints, skipped_price, maxPrice, XScale, YScale, close)
                end
            else
                skipped_price = skipped_price + 1
                drawLineRecursively(i - 1, box, close_values, numPoints, skipped_price, maxPrice, XScale, YScale,
                    previousOpen)
            end
            return close, i
        end
    end

    -- Determine of market is open or not
    local function isMarketOpen(decoded, gmtTimestamp)
        -- Get the current time as a table representing the local time and add the gmtoffset from the current stock
        local stockCurrentTime = gmtTimestamp + os.clock() * 1000 + decoded["chart"]["result"][1]["meta"]["gmtoffset"]

        -- Retrieve the start and end times for the regular trading session from the data
        local startTime = decoded["chart"]["result"][1]["meta"]["currentTradingPeriod"]["regular"]["start"]
        local endTime = decoded["chart"]["result"][1]["meta"]["currentTradingPeriod"]["regular"]["end"]

        -- Compare the current time to the start and end times to determine if the market is open or closed
        if stockCurrentTime > startTime and stockCurrentTime < endTime then
            -- Market open
            printDebug("Info: Market is open")
            return "\24"
        else
            -- Market close
            printDebug("Info: Market is close")
            return "\25"
        end
    end

    -- Get the display scaling depending on the number of data points and price
    local XScale, YScale, minPrice, maxPrice = getMinMaxNScale(display, box, decoded, numPoints)

    -- Draw the graph
    local x1, y1, first_price, first_key, previousOpen = nil
    local close_values = decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"]
    local skipped_price = 0
    local i = #close_values
    box:clear()
    first_price, first_key = drawLineRecursively(#close_values, box, close_values, numPoints, skipped_price, maxPrice,
        XScale, YScale, previousOpen) -- Start the recursion
    box:render()

    -- Reset cursor and background to displat top infos
    term.setCursorPos(1, 1)
    display.setBackgroundColor(backgroundColor)

    -- Display first stock infos
    local marketStatus = isMarketOpen(decoded, gmtTimestamp)
    local stockSymbol = decoded["chart"]["result"][1]["meta"]["symbol"]
    local stockLastTimestamp = os.date("%d/%m %H:%M", decoded["chart"]["result"][1]["timestamp"][first_key])
    display.setTextColor(defaultTextColor)
    print(marketStatus .. stockSymbol .. " " .. interval .. " " .. stockLastTimestamp .. " ")
    -- display.write(marketStatus .. stockSymbol .. " " .. interval .. " " .. stockLastTimestamp .. " ")

    -- Displat second stocks infos
    first_price = math.floor(first_price)
    local stockCurrency = converCurrencySymbol(decoded["chart"]["result"][1]["meta"]["currency"])
    local previousClose = tonumber(decoded["chart"]["result"][1]["meta"]["previousClose"])
    local pcChange = tonumber(string.format("%.2f", first_price / previousClose * 100 - 100))
    if pcChange > 0 then
        pcChange = "+" .. pcChange .. "%"
        display.setTextColour(buyColor)
    else
        pcChange = pcChange .. "%"
        display.setTextColour(sellColor)
    end
    print(first_price .. stockCurrency .. " " .. pcChange)
    -- display.write(first_price .. stockCurrency .. " " .. pcChange)    
end

-- Main function
local function main()
    -- Init terminal
    term.clear()
    term.setCursorPos(1, 1)
    printDebug("Running CC:StockDisplay by Octopus")
    printDebug("To stop execution hold CTRL+T")

    -- Load the PixelBox class using the loadPixelBoxLite() function
    local libFileName = "pixelbox_lite.lua"
    local PixelBox = loadPixelBoxLiteLib(libFileName)

    -- Set script to autoload on computer start
    registerStartup()

    -- If it doesn't exist, prompt the user to select a stock
    local configFileName = "selected_stock_config.json"
    selectStock(configFileName)
    -- If it does exist, load the selected stock from the file
    local stockSymbol, region, interval, range = loadSelectedStockParameters(configFileName)

    -- Get the current gmt timestamp
    gmtTimestamp = getGMTTime()

    -- Run the graph in an infinite loop
    while true do
        -- Get the display
        local display, box = checkDisplay()

        -- Download and Load stock data
        if getStockData(stockSymbol, region, interval, range) == 1 then
            return
        end
        local decoded = loadStockData("stock_data.json")

        -- Set the max number od siplay points
        local numDisplayPoints = box.width
        local numDataPoints = #decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"]
        if numDisplayPoints > numDataPoints then
            numDisplayPoints = numDataPoints
        end

        -- Draw the graph
        drawGraph(display, box, decoded, numDisplayPoints, interval, gmtTimestamp)

        -- Add a random delay between 20 seconds and 60 before refreshing the stock data
        local sleepTime = math.random() * 40 + 20
        printDebug("Info: Sleeping for " .. math.ceil(sleepTime) .. "s until update")
        os.sleep(sleepTime)
    end
end

-- Run the main function
main()
