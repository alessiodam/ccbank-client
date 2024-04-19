local CURRENT_VERSION = "1.8.0"

-- base routes
local BASE_CCBANK_URL = "https://ccbank.tkbstudios.com"

-- API routes
local base_api_url = BASE_CCBANK_URL .. "/api/v1"
local server_version_api_url = base_api_url .. "/version"
local server_login_url = base_api_url .. "/login"
local server_balance_url = base_api_url .. "/balance"
local latest_client_raw_api_url = "https://raw.githubusercontent.com/tkbstudios/ccbank-client/main/pocket.lua"
local new_transaction_url = base_api_url .. "/transactions/new"

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

    local server_version_json, decode_error = textutils.unserializeJSON(server_version_str)
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
    local response, error_msg = http.post(server_login_url, textutils.serializeJSON(postData), postHeaders)

    local statusCode = response.getResponseCode()
    if statusCode >= 400 and statusCode < 500 then
        local responseBody = response.readAll()
        if responseBody then
            local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
            if decodedResponse then
                return {success = false, message = decodedResponse.message}
            end
        end
        return {success = false, message = "HTTP status code: " .. statusCode}
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
    else
        write_log("Login failed for user '" .. username .. "': " .. decodedResponse.message)
    end

    return decodedResponse
end

local function logout()
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
        local statusCode = response.getResponseCode()
        if statusCode >= 400 and statusCode < 500 then
            local responseBody = response.readAll()
            if responseBody then
                local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
                if decodedResponse then
                    return decodedResponse.message .. " $OKU"
                end
            end
            return "HTTP " .. statusCode
        end
        local responseBody = response.readAll()
        response.close()
        return responseBody
    else
        write_log("Error: Failed to fetch user balance")
        return "N/A"
    end
end

local function create_transaction(target_username, amount)
    if string.len(target_username) > 15 or tonumber(amount) <= 0 then
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

    local response = http.post(new_transaction_url, textutils.serializeJSON(postData), headers)
    if not response then
        write_log("Error: Failed to create transaction")
        return {success = false, message = "Failed to create transaction"}
    end

    local statusCode = response.getResponseCode()
    if statusCode >= 400 and statusCode < 500 then
        local responseBody = response.readAll()
        if responseBody then
            local decodedResponse, decodeError = textutils.unserializeJSON(responseBody)
            if decodedResponse then
                return {success = false, message = decodedResponse.message}
            end
        end
        return {success = false, message = "HTTP status code: " .. statusCode}
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
    end
end

main()
