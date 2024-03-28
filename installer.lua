local latest_client_url = "https://raw.githubusercontent.com/tkbstudios/ccbank-client/main/computer.lua"
local latest_pocket_client_url = "https://raw.githubusercontent.com/tkbstudios/ccbank-client/main/pocket.lua"

local function drawButton(x, y, width, text)
    paintutils.drawFilledBox(x, y, x + width - 1, y, colors.blue)
    term.setCursorPos(x + math.floor((width - #text) / 2), y)
    term.setTextColor(colors.white)
    term.write(text)
end

local function showMessage(y, text)
    term.setCursorPos(1, y)
    term.clearLine()
    term.setCursorPos(1, y)
    print(text)
end

local function downloadAndInstall()
    local client_raw_response
    if pocket then
        showMessage(5, "Downloading Pocket Client...")
        client_raw_response = http.get(latest_pocket_client_url)
    else
        showMessage(5, "Downloading Computer Client...")
        client_raw_response = http.get(latest_client_url)
    end
    
    if client_raw_response == nil then
        showMessage(6, "Error: Failed to fetch latest client from API")
        os.sleep(2)
        os.shutdown()
        return
    end

    local client_raw_data = client_raw_response.readAll()
    if not client_raw_data then
        showMessage(6, "Error: Client raw data response is empty")
        os.shutdown()
    end

    local file = fs.open("startup.lua", "w")
    if file then
        file.write(client_raw_data)
        file.close()
        http.get("https://api.counterapi.dev/v1/ccbanktkbstudios/installs/up") -- update the installs counter
        showMessage(6, "Latest client written to disk")
        showMessage(7, "Restarting...")
        os.sleep(1)
        os.reboot()
    else
        showMessage(6, "Error: Failed to open file for writing client")
        os.sleep(1)
        os.shutdown()
    end
end

-- Main UI
term.clear()
term.setCursorPos(1, 1)
print("Bank Of ComputerCraft Installer")

if not term.isColor() then
    -- Is advanced
    showMessage(4, "Only for advanced computers or advanced pocket computers")
    os.sleep(3)
    os.shutdown()
end

term.clear()
term.setCursorPos(1, 1)
print("Bank Of ComputerCraft Installer")

local total_downloads_response = http.get("https://api.counterapi.dev/v1/ccbanktkbstudios/installs")
if total_downloads_response == nil then
    showMessage(15, "Error: Failed to fetch total downloads from API")
    os.shutdown()
end
local total_downloads_content = total_downloads_response.readAll()
local total_downloads = textutils.unserializeJSON(total_downloads_content).count
term.setCursorPos(1, 10)
term.write("Total downloads: " .. total_downloads)

drawButton(1, 5, 18, "Download & Install")

while true do
    local event, button, x, y = os.pullEvent("mouse_click")
    if event == "mouse_click" then
        if button == 1 and x >= 1 and x <= 18 and y == 5 then
            downloadAndInstall()
        end
    end
end
