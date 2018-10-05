SHOW_ALERTS = true

MPD_COMMANDS = {
  PLAY=true,
  FAST=true,
  REWIND=true
}

BROWSER_LIST = {
  "Google Chrome",
  "Google Chrome Canary",
  "Chromium",
  "Yandex",
  "Vivaldi",
  "Safari",
  "Safari Technology Preview"
}

SAFARI_BROWSERS = {
  ["Safari"]=true,
  ["Safari Technology Preview"]=true
}

YM_SELECTORS = {
  PLAY = "document.querySelector('.player-controls__btn_pause') || document.querySelector('.player-controls__btn_play')";
  FAST = "document.querySelector('.player-controls__btn_next')";
  REWIND = "document.querySelector('.player-controls__btn_prev')";
  LIKE = "document.querySelector('.player-controls__track-controls .d-like')";
}

function showAlert(text)
  if not SHOW_ALERTS then
    return
  end

  hs.alert.show(text, { radius=5 })
end

function sendNotification(title, informativeText, coverUrl)
  local notification = hs.notify.new({title=title, informativeText=informativeText})

  if coverUrl then
    local coverImage = hs.image.imageFromURL(coverUrl)

    if coverImage then
      notification:setIdImage(coverImage)
    end
  end

  notification:send()
end

function isBrowserRunningYm(browserName)
  local ok, isRunning = hs.osascript.applescript([[
    tell application "]] .. browserName .. [[" to set browserTabs to (get first tab in every window whose URL contains the "music.yandex.ru")

    repeat with i from 1 to count of browserTabs
      set browserTab to item i of browserTabs
      
      if browserTab is not missing value then
        return true
      end if
    end repeat

    return false
  ]])

  return ok and isRunning
end

function detectRunningBrowser()
  local browserName

  for i, browser in ipairs(BROWSER_LIST) do
    if hs.appfinder.appFromName(browser) then
      browserName = browser

      if browserName and isBrowserRunningYm(browserName) then
        return browserName
      end
    end
  end
end

function executeJavascript(code, browserName)
  if not browserName then
    return
  end

  local executeStatement

  if SAFARI_BROWSERS[browserName] then
    executeStatement = "do JavaScript \"" .. code .. "\" in browserTab"
  else
    executeStatement = "execute browserTab javascript \"" .. code .. "\""
  end

  local ok, data, raw = hs.osascript.applescript([[
    tell application "]] .. browserName .. [["
      set browserTabs to (get first tab in every window whose URL contains the "music.yandex.ru")
      
      repeat with i from 1 to count browserTabs
        set browserTab to item i of browserTabs
        if browserTab is not missing value then
          tell application "]] .. browserName .. [["

            return ]] .. executeStatement .. [[

          end tell
        end if
      end repeat
    end tell
  ]])

  if ok and data then
    return data
  end
end

function copyTrackUrl(browserName)
  local url = executeJavascript([[
    var link = document.querySelector('.player-controls__wrapper .track__name-wrap .track__title');

    if (link) {
      link.href;
    }
  ]], browserName)

  if url then
    hs.pasteboard.setContents(url)
    showAlert("🔗 Link copied to clipboard")
  end
end

function getTrackCoverUrl(browserName)
  local coverUrl = executeJavascript([[
    var coverImage = document.querySelector('.player-controls .track-cover');

    if (coverImage) {
      coverImage.src;
    }
  ]], browserName)

  return coverUrl
end

function showYmTrackInfo(browserName)
  local data = executeJavascript([[
    var info = document.querySelector('.track__name-wrap');
    if (info) {
      [info.querySelector('.track__title').text, info.querySelector('.d-artists > a').text]
    }
  ]], browserName)

  if data then
    sendNotification(data[1], data[2], getTrackCoverUrl(browserName))
  end
end

function sendYmEvent(eventType, browserName)
  local selector = YM_SELECTORS[eventType]

  if not selector then
    return
  end

  local state = executeJavascript([[
    var target = ]] .. selector .. [[;

    if (target != null) {
      var isLiked = ]] .. (eventType == "LIKE" and "!target.classList.contains('d-like_on')" or "null") .. [[;
      target.click();
      isLiked;
    }
  ]], browserName)

  if eventType == "LIKE" then
    if state then
      showAlert("👍 Liked")
    else
      showAlert("😐 Like removed")
    end
  end
end

function init()
  hs.application.enableSpotlightForNameSearches(true)

  hs.eventtap.new({hs.eventtap.event.types.NSSystemDefined}, function(event)
    local systemKey = event:systemKey()
    local flags = event:getFlags()
    local browserName

    if not systemKey or not systemKey.down then
      return false
    elseif flags and flags.cmd and not systemKey['repeat'] then
      if systemKey.key == "PLAY" then
        browserName = detectRunningBrowser()
        showYmTrackInfo(browserName)
        return browserName ~= nil
      elseif systemKey.key == "FAST" then
        browserName = detectRunningBrowser()
        sendYmEvent("LIKE", browserName)
        return browserName ~= nil
      elseif systemKey.key == "REWIND" then
        browserName = detectRunningBrowser()
        copyTrackUrl(browserName)
        return browserName ~= nil
      end
    elseif MPD_COMMANDS[systemKey.key] and not systemKey['repeat'] then
      browserName = detectRunningBrowser()
      sendYmEvent(systemKey.key, browserName)
      return browserName ~= nil
    end

    return false
  end):start()
end

return {
  name = "Yandex Music Control",
  author = "Maksim Karelov",
  version = "1.0.0",
  license = "MIT",
  homepage = "https://github.com/Ty3uK/YandexMusicControl",
  init = init
}
