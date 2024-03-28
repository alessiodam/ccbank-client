local CURRENT_VERSION = "1.6.0"

-- base routes
local BASE_CCBANK_URL = "https://ccbank.tkbstudios.com"
local BASE_CCBANK_WS_URL = "wss://ccbank.tkbstudios.com"

-- API routes
local base_api_url = BASE_CCBANK_URL .. "/api/v1"
local server_version_api_url = base_api_url .. "/version"
local server_login_url = base_api_url .. "/login"
local server_register_url = base_api_url .. "/register"
local server_balance_url = base_api_url .. "/balance"
local latest_client_raw_api_url = base_api_url .. "/latest-client"
local new_transaction_url = base_api_url .. "/transactions/new"
local transaction_list_url = base_api_url .. "/transactions/list?per_page=16"
local change_pin_url = base_api_url .. "/change-pin"

-- Websocket
local transactions_websocket_url = BASE_CCBANK_WS_URL .. "/websockets/transactions"
local transactions_ws

-- some vars
local latest_server_version = "Unknown"
local isLoggedIn = false
local username = ""
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

    local server_version_json, decode_error = textutils.unserializeJSON(server_version_str)
    if not server_version_json then
        write_log("Error decoding server version JSON: " .. (decode_error or "Unknown"))
        return "Unknown"
    end

    local server_version = server_version_json.version
    return server_version
end

local function handle_websocket_transactions()
    if not transactions_ws then
        return
    end
    local _, url, message = os.pullEvent("websocket_message")
    if not message == nil and url == transactions_websocket_url then
        local transaction_json = textutils.unserializeJSON(message)
        local x,y = term.getSize()
        term.setCursorPos(x, y - 2)
        local text = "received " .. tostring(transaction_json.amount) .. " from " .. transaction_json.from_user
        term.setCursorPos(math.floor(x - text:len()), y - 2)
        term.setTextColor(colors.green)
        term.setBackgroundColor(colors.white)
        term.write(text)
        os.sleep(3)
        term.setTextColor(colors.white)
        term.setBackgroundColor(colors.blue)
        local clear_text = string.rep(" ", text:len())
        term.setCursorPos(math.floor(x - text:len()), y - 2)
        term.write(clear_text)
    end
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
    local response, error_msg = http.post(server_login_url, textutils.serializeJSON(postData), postHeaders)
    if not response then
        return {success = false, message = error_msg}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Login response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
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

local function register(username, pin)
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
    local response = http.post(server_register_url, textutils.serializeJSON(postData), postHeaders)
    if not response then
        write_log("Error: Registration request failed")
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Registration response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
    if not decodedResponse then
        write_log("Error decoding registration response JSON: " .. (decodeError or "Unknown"))
        return {success = false, message = "Failed to parse server response"}
    end

    return decodedResponse
end

local function logout()
    isLoggedIn = false
    username = ""
    user_balance = "N/A"
    sessionToken = ""
    transactions_ws.close()
end

local function get_user_balance(session_token)
    local headers = {
        ["Session-Token"] = session_token
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

local function create_transaction(session_token, target_username, amount)
    if string.len(target_username) > 15 or amount <= 0 then
        return {success = false, message = "Invalid target username or amount"}
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Session-Token"] = session_token
    }

    local postData = {
        username = target_username,
        amount = amount
    }

    local response = http.post(new_transaction_url, textutils.serializeJSON(postData), headers)
    if not response then
        write_log("Error: Transaction request failed")
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Transaction response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
    if not decodedResponse then
        write_log("Error decoding transaction response JSON: " .. (decodeError or "Unknown"))
        return {success = false, message = "Failed to parse server response"}
    end

    return decodedResponse
end

local function get_last_transactions()
    local headers = {
        ["Session-Token"] = sessionToken
    }
    local response = http.get(transaction_list_url, headers)
    if response then
        local responseBody = response.readAll()
        response.close()
        local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
        if decodedResponse then
            return {success = true, transactions = decodedResponse}
        else
            write_log("Error decoding transaction list response JSON: " .. (decodeError or "Unknown"))
            return {success = false, message = "Failed to parse server response"}
        end
    else
        write_log("Error: Failed to fetch last transactions")
        return {success = false, message = "Failed to connect to server"}
    end
end

local function change_pin(session_token, new_pin)
    if string.len(new_pin) > 8 then
        return {success = false, message = "Invalid PIN length"}
    end

    local headers = {
        ["Content-Type"] = "application/json",
        ["Session-Token"] = session_token
    }

    local postData = {
        new_pin = new_pin
    }

    local response = http.post(change_pin_url, textutils.serializeJSON(postData), headers)
    if not response then
        write_log("Error: Change PIN request failed")
        return {success = false, message = "Failed to connect to server"}
    end

    local responseBody = response.readAll()
    if not responseBody then
        write_log("Error: Change PIN response is empty")
        return {success = false, message = "Empty response from server"}
    end

    local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
    if not decodedResponse then
        write_log("Error decoding change PIN response JSON: " .. (decodeError or "Unknown"))
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

local function bootupAnimation()
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    print("Bank Of ComputerCraft - by TKB Studios")
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
    print("Bank Of ComputerCraft - by TKB Studios")

    if isLoggedIn then
        term.setTextColor(colors.red)
        print("Logout")
        term.setCursorPos(1, 5)
        term.setTextColor(colors.white)
        print("Username: " .. username)
        print("Balance: " .. user_balance)
        term.setCursorPos(1, 10)
        print("[Create Transaction]")
        term.setCursorPos(1, 12)
        print("[View Transactions]")
        term.setCursorPos(1, 14)
        print("[Change PIN]")
    else
        term.setTextColor(colors.yellow)
        term.setCursorPos(1, 2)
        print("Login")
        term.setCursorPos(1, 5)
        print("Register")
    end

    term.setCursorPos(1, 18)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    print("Server: " .. latest_server_version .. " Client: " .. CURRENT_VERSION)
end


local function handleMouseClick(x, y)
    if y == 2 then
        if isLoggedIn then
            logout()
        else
            term.clear()
            term.setCursorPos(1, 1)
            term.setTextColor(colors.yellow)
            write("Enter username: ")
            username = read()
            term.setTextColor(colors.yellow)
            write("Enter PIN: ")
            local pin = read("*")
            print("Logging in...")
            local loginResponse = login(username, pin)
            if loginResponse.success then
                user_balance = get_user_balance(sessionToken)
            else
                print("Login failed: " .. loginResponse.message)
                os.sleep(2)
            end

        end
    elseif y == 5 and not isLoggedIn then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        write("Enter username: ")
        local reg_username = read()
        term.setTextColor(colors.yellow)
        write("Enter PIN: ")
        local reg_pin = read("*")
        if reg_pin:match("^%d+$") then
            local regResponse = register(reg_username, reg_pin)
            if regResponse.success then
                print("Registration successful! Please login.")
                os.sleep(2)
            else
                print("Registration failed: " .. regResponse.message)
                os.sleep(2)
            end
        else
            print("PIN must contain only numbers.")
            os.sleep(2)
        end
    elseif isLoggedIn and y == 10 then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        write("Enter target username: ")
        local target_username = read()
        term.setTextColor(colors.yellow)
        write("Enter amount: ")
        local amount = tonumber(read())
        print("Creating transaction...")
        local transactionResponse = create_transaction(sessionToken, target_username, amount)
        if transactionResponse.success then
            print("Transaction successful! Transaction ID: " .. transactionResponse.transaction_id)
            user_balance = get_user_balance(sessionToken)
        else
            print("Transaction failed: " .. transactionResponse.message)
            os.sleep(2)
        end
    elseif y == 12 and isLoggedIn then
        term.clear()
        term.setCursorPos(1, 1)
        print("Fetching last transactions...")
        local transactionsResponse = get_last_transactions()
        if transactionsResponse.success then
            term.clear()
            local maxLengthFrom = 0
            local maxLengthTo = 0
            local maxLengthAmount = 0
            for _, transaction in ipairs(transactionsResponse.transactions) do
                maxLengthFrom = math.max(maxLengthFrom, #transaction.from_user)
                maxLengthTo = math.max(maxLengthTo, #transaction.to_user)
                maxLengthAmount = math.max(maxLengthAmount, #tostring(transaction.amount))
            end
            local spacing = 2
            local columnFrom = 1
            local columnTo = columnFrom + maxLengthFrom + spacing
            local columnAmount = columnTo + maxLengthTo + spacing

            term.setCursorPos(columnFrom, 1)
            write("From")
            term.setCursorPos(columnTo, 1)
            write("To")
            term.setCursorPos(columnAmount, 1)
            write("Amount")

            for i, transaction in ipairs(transactionsResponse.transactions) do
                term.setTextColor(colors.white)
                term.setCursorPos(columnFrom, i + 2)
                write(transaction.from_user)
                term.setCursorPos(columnTo, i + 2)
                write(transaction.to_user)
                term.setCursorPos(columnAmount, i + 2)
                if transaction.from_user == username then
                    term.setTextColor(colors.red)
                    write("-" .. tostring(transaction.amount))
                elseif transaction.to_user == username then
                    term.setTextColor(colors.green)
                    write("+" .. tostring(transaction.amount))
                else
                    term.setTextColor(colors.white)
                    write(tostring(transaction.amount))
                end
            end
        else
            print("Failed to fetch transactions: " .. transactionsResponse.message)
        end
        os.sleep(5)
    elseif isLoggedIn and y == 14 then
        term.clear()
        term.setCursorPos(1, 1)
        term.setTextColor(colors.yellow)
        write("Enter new PIN: ")
        local new_pin = read("*")
        print("Changing PIN...")
        local pinChangeResponse = change_pin(sessionToken, new_pin)
        if pinChangeResponse.success then
            print("PIN successfully changed!")
        else
            print("Failed to change PIN: " .. pinChangeResponse.message)
        end
        os.sleep(2)
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

    local lastUpdateCheck = os.time()

    while true do
        local currentTime = os.time()

        if currentTime - lastUpdateCheck >= 300 then
            print("Checking for updates...")
            drawUI()
            if update_client_from_server() then
                return
            end
            lastUpdateCheck = os.time()
        else
            parallel.waitForAll(handle_websocket_transactions, drawUI, mouseClickStuff)
        end
    end
end

main()
