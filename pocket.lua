os.pullEvent = os.pullEventRaw -- disables CTRL-T termination

os.loadAPI("json")

local CURRENT_VERSION = "1.5.0"

-- base routes
local BASE_CCBANK_URL = "https://ccbank.tkbstudios.com"
local BASE_CCBANK_WS_URL = "wss://ccbank.tkbstudios.com"

-- API routes
local base_api_url = BASE_CCBANK_URL .. "/api/v1"
local server_version_api_url = base_api_url .. "/version"
local server_login_url = base_api_url .. "/login"
local server_balance_url = base_api_url .. "/balance"
local latest_client_raw_api_url = base_api_url .. "/latest-pocket-client"
local new_transaction_url = base_api_url .. "/transactions/new"

-- Websocket
local transactions_websocket_url = BASE_CCBANK_WS_URL .. "/websockets/transactions"
local transactions_ws

-- some vars
local latest_server_version = "Unknown"
local isLoggedIn = false
local username = ""
local user_pin = ""
local sessionToken = ""
local user_balance = "N/A"


-- functions declaration
local function write_log(message)
    local file = io.open("log.txt", "a")
    if file then
        file:write(os.date("[%Y-%m-%d %H:%M:%S] ") .. message .. "\n")
        file:close()
    else
        print("Error: Failed to open log file")
    end
end

local function get_latest_server_version()
    local server_version_response = http.get(server_version_api_url)
    if not server_version_response then
        write_log("Error: Failed to fetch server version")
        return "Unknown"
    end

    local server_version_str = server_version_response.readAll()
    if not server_version_str then
        write_log("Error: Server version response is empty")
        return "Unknown"
    end

    local server_version_json, decode_error = json.decode(server_version_str)
    if not server_version_json then
        write_log("Error decoding server version JSON: " .. (decode_error or "Unknown"))
        return "Unknown"
    end

    local server_version = server_version_json.version
    return server_version
end

local function login(username, pin)
    if string.len(username) > 15 or string.len(pin) > 8 then
        return {success = false, message = "Invalid username or PIN length"}
    end

    local postData = {
        username = username,
        pin = pin
    }
    local postHeaders = {
        ["Content-Type"] = "application/json"
    }
    local response = http.post(server_login_url, json.encode(postData), postHeaders)
    if not response then
        write_log("Error: Login request failed")
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Login response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = json.decode(responseBody)
    if not decodedResponse then
        write_log("Error decoding login response JSON: " .. (decodeError or "Unknown"))
        return {success = false, message = "Failed to parse server response"}
    end

    if decodedResponse.success then
        sessionToken = decodedResponse.session_token
        isLoggedIn = true
        write_log("User '" .. username .. "' logged in successfully")
        local ws_error_msg
        transactions_ws, ws_error_msg = http.websocket(transactions_websocket_url, {["Session-Token"] = sessionToken})
        if not transactions_ws then
            write_log("Error: Failed to open websocket: " .. (ws_error_msg or "Unknown"))
        else
            write_log("Websocket opened successfully")
        end
    else
        write_log("Login failed for user '" .. username .. "': " .. decodedResponse.message)
    end

    return decodedResponse
end

local function logout()
    transactions_ws.close()
    isLoggedIn = false
    username = ""
    user_pin = ""
    user_balance = "N/A"
    sessionToken = ""
end

local function get_user_balance()
    local headers = {
        ["Session-Token"] = sessionToken
    }

    local response = http.get(server_balance_url, headers)
    if response then
        local responseBody = response.readAll()
        response.close()
        return responseBody
    else
        write_log("Error: Failed to fetch user balance")
        return "N/A"
    end
end

local function create_transaction(target_username, amount)
    if string.len(target_username) > 15 or amount <= 0 then
        return {success = false, message = "Invalid target username or amount"}
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Session-Token"] = sessionToken
    }

    local postData = {
        username = target_username,
        amount = amount
    }

    local response = http.post(new_transaction_url, json.encode(postData), headers)
    if not response then
        write_log("Error: Transaction request failed")
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Transaction response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = json.decode(responseBody)
    if not decodedResponse then
        write_log("Error decoding transaction response JSON: " .. (decodeError or "Unknown"))
        return {success = false, message = "Failed to parse server response"}
    end

    return decodedResponse
end

local function update_client_from_server()
    if CURRENT_VERSION == latest_server_version then
        print("No updates available!")
        return false
    elseif latest_server_version == "Unknown" then
        write_log("Unknown server version!")
        write_log("Shutdown!")
        os.sleep(1)
        os.shutdown()
    else
        print("Update available! Updating...")
        local client_raw_response = http.get(latest_client_raw_api_url)
        if not client_raw_response then
            write_log("Error: Failed to fetch latest client raw data")
            return "Unknown"
        end

        local client_raw_data = client_raw_response.readAll()
        if not client_raw_data then
            write_log("Error: Client raw data response is empty")
            return "Unknown"
        end

        local file = fs.open("startup.lua", "w")
        if file then
            file.write(client_raw_data)
            file.close()
            write_log("Latest client raw data written to disk")
            os.reboot()
        else
            write_log("Error: Failed to open file for writing client update")
        end
        return true
    end
end

local function create_transaction_screen()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("To who?\n")
    local target_username = read()
    print("\n")
    term.setTextColor(colors.yellow)
    write("Amount\n")
    local amount = tonumber(read())
    print("\n")
    write("PIN:\n")
    local pin = read("*")
    print("\n")
    if pin == user_pin then
        print("Creating transaction...")
        local transactionResponse = create_transaction(target_username, amount)
        if transactionResponse.success then
            print("Transaction success!\nID: " .. transactionResponse.transaction_id)
            user_balance = get_user_balance()
        else
            print("Transaction failed:\n" .. transactionResponse.message)
            os.sleep(2)
            return
        end
    else
        print("Wrong PIN!")
        os.sleep(2)
        return
    end
end

local function bootupAnimation()
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("Bank Of ComputerCraft")
    print("by TKB Studios")
    print("")
    print("Initializing...")
    print("Fetching server version...")
    latest_server_version = get_latest_server_version()
    print("Checking for client updates...")
    update_client_from_server()
    print("Bootup complete!")
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawUI()
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("Bank Of ComputerCraft")
    print("by TKB Studios")

    if isLoggedIn then
        term.setTextColor(colors.red)
        print("Logout")
        term.setCursorPos(1, 5)
        term.setTextColor(colors.white)
        print("Username: " .. username)
        print("Balance: " .. user_balance)
        term.setCursorPos(1, 8)
        print("[Create Transaction]")
    else
        term.setTextColor(colors.yellow)
        term.setCursorPos(1, 3)
        print("[LOGIN]")
    end

    term.setCursorPos(1, 18)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    print("Server: " .. latest_server_version .. "\nClient: " .. CURRENT_VERSION)
end

--[[
local function handle_websocket_transactions()
    if not transactions_ws then
        return
    end
    local _, url, message = os.pullEvent("websocket_message")
    write_log(url .. " " .. message)
    if url == transactions_websocket_url then
        write_log("handling ws msg")
        local transaction_json = json.decode(message)
        local x,y = term.getSize()
        term.setCursorPos(x, y - 3)
        local text = "received " .. tostring(transaction_json.amount) .. " from " .. transaction_json.from_user
        user_balance = user_balance + transaction_json.amount
        write_log(text)
        term.setCursorPos(math.floor(x - text:len()), y - 3)
        term.setTextColor(colors.green)
        term.setBackgroundColor(colors.white)
        term.write(text)
        os.sleep(3)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.blue)
        local clear_text = string.rep(" ", text:len())
        term.setCursorPos(math.floor(x - text:len()), y - 3)
        term.write(clear_text)
        write_log("done handling websocket transaction")
    end
end
--]]

local function handleMouseClick(x, y)
    if y == 3 then
        if isLoggedIn then
            logout()
        else
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            write("Username:\n")
            username = read()
            term.setTextColor(colors.yellow)
            write("PIN:\n")
            local pin = read("*")
            print("Logging in...")
            local loginResponse = login(username, pin)
            if loginResponse.success then
                user_pin = pin
                user_balance = get_user_balance()
            else
                print("Login failed: " .. loginResponse.message)
                os.sleep(2)
            end

        end
    elseif isLoggedIn and y == 8 then
        create_transaction_screen()
    end
end

local function mouseClickStuff()
    local event, button, x, y = os.pullEvent("mouse_click")
    if event == "mouse_click" then
        handleMouseClick(x, y)
    end
end

local function main()
    bootupAnimation()

    while true do
        drawUI()
        mouseClickStuff()
        -- find a way to do websocket stuff
    end
end

main()
