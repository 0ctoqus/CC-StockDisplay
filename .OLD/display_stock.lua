function checkDisplay()
    local sides = {"front", "back", "left", "right", "top", "bottom"}
    for i=1, #sides do
        local peripheralType = peripheral.getType(sides[i])
        if peripheralType == "monitor" then
            local display = peripheral.wrap(sides[i])
            display.setTextScale(0.5)
            term.redirect(display)
            print("Info: Monitor found to the " .. sides[i])
            return display
        end
    end
    print("Info: No monitor found")
    return term
end

-- Function to load stock data from a file
local function loadStockData(file_name)
    local file = fs.open(file_name, "r")
    if not file then
        print("Error: Can't open file")
        os.exit()
    end
    local decoded, pos, err = textutils.unserializeJSON(file.readAll())
    file.close()
    return decoded
end

-- Function to download stock data to a file and load it
local function getStockData(stockSymbol, region, interval, range)
    local url = "https://query1.finance.yahoo.com/v8/finance/chart/" .. stockSymbol .. "?region=" .. region .. "&lang=en-US&includePrePost=false&interval=" .. interval .. "&useYfid=true&range=" .. range .. "&corsDomain=finance.yahoo.com&.tsrc=finance"

    -- Make the HTTP request
    local response = http.get(url)

    -- Read the response
    if response then
        local data = response.readAll()
        response.close()
        print('Info: Got some data')
        -- Parse the JSON response
        local decoded, pos, err = textutils.unserializeJSON(data)
        -- Display the stock price
        if decoded and decoded["chart"] then
            -- Save the data to a file
            local file_name = "stock_data.txt"
            local file = fs.open(file_name, "w")
            file.write(data)
            file.close()
            -- print("Info: Saved data to file" .. file_name)
            -- return loadStockData(file_name)
        elseif not decoded then
            print("Error: Failed to parse JSON response")
        else
            print("Error: No 'chart' data found in response")
        end
    else
        print("Error: Failed to get stock data")
    end
end

-- Function to draw the graph
local function drawGraph(display, decoded, numPoints, interval)
    -- Get the right currency symbol if we can
    local function converCurrencySymbol(stockCurrency)
        if stockCurrency == "USD" then
            return "$"
        elseif stockCurrency == "EUR" then
            return "€"
        else
            return stockCurrency
        end
    end

    -- Function to get min max for the graph depending on display size
    local function getMinMaxNScale(display, decoded, numPoints)
        -- Define the scale for the graph
        local minPrice = math.huge
        local maxPrice = -math.huge

        -- We get more data point to get some air around the line
        local c_numPoints = numPoints * 1.5

        -- Iterate over the sorted keys to get min and max prices for scale
        local close_values = decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"]
        local skipped_price = 0
        local i = #close_values
        
        while i >= #close_values - c_numPoints - skipped_price do
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
        local displayrWidth, displayHeight = display.getSize()
        local XScale = displayrWidth / numPoints
        local YScale = displayHeight / (maxPrice - minPrice)
        return XScale, YScale, minPrice, maxPrice
    end


    local XScale, YScale, minPrice, maxPrice = getMinMaxNScale(display, decoded, numPoints)
    
    -- Clear the display
    display.clear()
    local displayWidth, displayHeight = display.getSize()
    paintutils.drawFilledBox(1, 1, displayWidth, displayHeight, colors.black)

    -- Draw the graph
    local x1, y1, first_price, first_key
    local close_values = decoded["chart"]["result"][1]["indicators"]["quote"][1]["close"]
    local first_price = nil
    local second_price = nil
    local skipped_price = 0
    local i = #close_values
    
    while i >= #close_values - numPoints - skipped_price do
        local current_step = numPoints - (tonumber(#close_values) - i) + skipped_price
        local price = tonumber(close_values[i])
    
        if price ~= nil then
            if not x1 and not y1 then
                x1 = math.floor(current_step * XScale)
                y1 = math.floor((maxPrice - price) * YScale)
            else
                local x2 = math.floor(current_step * XScale)
                local y2 = math.floor((maxPrice - price) * YScale)
                if y2 > y1 then
                    -- the second point is higher than the previous point, so use a different color
                    paintutils.drawLine(x1, y1, x2, y2, colors.green)
                else
                    -- the second point is lower than or equal to the previous point, so use the original color
                    paintutils.drawLine(x1, y1, x2, y2, colors.red)
                end

                x1 = x2
                y1 = y2
            end
            if not first_price then
                first_price = math.floor(price)
                first_key = i
            elseif not second_price then 
                second_price = math.floor(price)
            end
        else
            skipped_price = skipped_price + 1
        end
        i = i - 1
    end

    term.setCursorPos(1, 1)
    local stockSymbol = decoded["chart"]["result"][1]["meta"]["symbol"]
    local stockCurrency = converCurrencySymbol(decoded["chart"]["result"][1]["meta"]["currency"])
    local stockLastTimestamp = os.date("%d/%m/%y %H:%M", decoded["chart"]["result"][1]["timestamp"][first_key])
    if first_price > second_price then 
        display.setBackgroundColor(colors.green)
    else
        display.setBackgroundColor(colors.red)
    end
    print(stockSymbol .. " " .. interval .. " " .. stockLastTimestamp .. " " .. first_price .. stockCurrency)
end

-- Main function
local function main()
    -- Set the stock info
    local stockSymbol = "NQ=F"
    local region = "US"
    local interval = "1h"
    local range = "1mo"
    local numDisplayPoints = 50

    -- Get the display
    local display = checkDisplay()
    -- Run the graph in an infinite loop
    while true do
        -- Download and Load stock data
        -- getStockData(stockSymbol, region, interval, range)
        local decoded = loadStockData("stock_data.txt")
        -- Draw the graph
        drawGraph(display, decoded, numDisplayPoints, interval)
        -- Add a random delay between 20 seconds and 60 before refreshing the stock data
        os.sleep(math.random() * 40 + 20) 
    end
end

-- Run the main function
main()
