--Version: 09.16.24 19:34
--For Til Death
local t = Def.ActorFrame {}

local score = SCOREMAN:GetMostRecentScore()
if not score then
    score = SCOREMAN:GetTempReplayScore()
end

local aspectRatio = GetScreenAspectRatio()

local mfDisplayX
local mfDisplayY
local mfDisplayZoom = 0.25

if aspectRatio < 1.6 then
    mfDisplayX = SCREEN_RIGHT - 30
    mfDisplayY = SCREEN_CENTER_Y + 66
else
    mfDisplayX = SCREEN_LEFT + 42
    mfDisplayY = 350
end

local td = {} -- chart timing data
local dvt = {} -- offset vector
local ctt = {} -- track vector
local nrt = {} -- noterow vector
local wuab = {} -- note timing vector
local ntt = {} -- note type vector

-- key data
local keyData

-- deviations for total mf
local deviations = {}

local mf = {} -- manip factor

-- filter table by percentiles
local function FilterTable(low, high, x, eps)
    local y = {}
    for i = 1, #x do
        if x[i] > (low - eps) and x[i] < (high + eps) and x[i] ~= 0 then
            table.insert(y, x[i])
        end
    end
    return y
end

-- filter deviations table by time
local function FilterTableByTime(x, time)
    local y = {}
    for i = 1, #x do
        for k = 1, #x[i] do
            if x[i][k][1] <= time then
                table.insert(y, x[i][k])
            end
        end
    end
    return y
end

-- Helper function to calculate Arithmetic Mean
local function ArithmeticMean(x)
    local sum = 0
    for i = 1, #x do
        sum = sum + x[i]
    end
    return sum / #x
end

local function ArithmeticMeanForDeviatons(x)
    local sum = 0
    local count = 0
    for i = 1, #x do
        sum = sum + x[i][2]
        count = count + 1
    end
    return sum / count
end

local function ArithmeticMeanForTimedDeviatons(x)
    local sum = 0
    local count = 0
    for i = 1, #x do
        sum = sum + x[i][2]
        count = count + 1
    end
    return sum / count
end

-- Helper function to calculate Weighted Mean
local function WeightedMean(x, w)
    local sump = 0
    local sum = 0
    for i = 1, #x do
        sump = sump + (x[i] * w[i])
        sum = sum + w[i]
    end
    return sump / sum
end

-- Helper function to calculate the 5th and 95th percentiles
local function Percentile(sortedArray, p)
    local index = (p / 100) * (#sortedArray - 1) + 1
    local lowerBound = math.floor(index)
    local upperBound = math.ceil(index)
    local fracPart = index - lowerBound

    if fracPart == 0 then
        return sortedArray[lowerBound]
    else
        return sortedArray[lowerBound] + fracPart * (sortedArray[upperBound] - sortedArray[lowerBound])
    end
end

-- mf value to hsv color
local function byMF(x)
    if x > 0.4 then
        x = 0.4
    end
    -- Calculate the hue from 0 (green) to 0.4 (red)
    local hue = 120 - (x * 300) -- 120 to 0 degrees
    local saturation = 0.9 -- Full saturation
    local brightness = 0.9 -- Full brightness

    return HSV(hue, saturation, brightness)
end

local function GetMaxTrack() -- copied from 00 Utility.lua
	local keys = {
		StepsType_Dance_Threepanel = 3,
		StepsType_Dance_Single = 4,
		StepsType_Pump_Single = 5,
		StepsType_Pnm_Five = 5,
		StepsType_Pump_Halfdouble = 6,
		StepsType_Bm_Single5 = 6,
		StepsType_Dance_Solo = 6,
		StepsType_Kb7_Single = 7,
		StepsType_Bm_Single7 = 8,
		StepsType_Dance_Double = 8,
		StepsType_Pnm_Nine = 9,
		StepsType_Pump_Double = 10,
		StepsType_Bm_Double5 = 12,
		StepsType_Bm_Double7 = 16,
	}
	local stepstype = GAMESTATE:GetCurrentSteps():GetStepsType()
	return keys[stepstype]
end

-- im sorry
local function FindKeyPairs(keymode)
    local keyPairs = {}
    for i = 0, keymode - 1 do
        if keymode % 2 == 0 then
            if i == 0 then
                for j = 1, keymode / 2 - 1 do
                    table.insert(keyPairs, {math.floor(i), math.floor(j)})
                end
            elseif i == keymode - 1 then
                for j = keymode - 2, keymode / 2, -1 do
                    table.insert(keyPairs, {math.floor(i), math.floor(j)})
                end
            elseif i <= keymode / 2 - 1 then
                for j = 0, keymode / 2 - 1 do
                    if i ~= j then
                        table.insert(keyPairs, {math.floor(i), math.floor(j)})
                    end
                end
            elseif i > keymode / 2 - 1 then
                for j = keymode / 2, keymode - 1  do
                    if i ~= j then
                        table.insert(keyPairs, {math.floor(i), math.floor(j)})
                    end
                end
            end
        else
            if i == 0 then
                for j = 1, keymode / 2 - 1.5 do
                    table.insert(keyPairs, {math.floor(i), math.floor(j)})
                end
            elseif i == keymode / 2 - 0.5 then
            elseif i == keymode - 1 then
                for j = keymode - 2, keymode / 2 + 0.5, -1 do
                    table.insert(keyPairs, {math.floor(i), math.floor(j)})
                end
            elseif i <= keymode / 2 - 1.5 then
                for j = 0, keymode / 2 - 1.5 do
                    if i ~= j then
                        table.insert(keyPairs, {math.floor(i), math.floor(j)})
                    end
                end
            elseif i > keymode / 2 - 1.5 then
                for j = keymode / 2 + 0.5, keymode - 1  do
                    if i ~= j then
                        table.insert(keyPairs, {math.floor(i), math.floor(j)})
                    end
                end
            end
        end
    end
    return keyPairs
end

local function GetHand(track, keymode)
    if keymode % 2 == 0 then
        if track <= keymode / 2 - 1  then
            return  "left"
        else
            return "right"
        end
    else
        if track <= keymode / 2 - 1.5 then
            return  "left"
        else
            return "right"
        end
    end
end

-- Generate key data
local function GenerateKeyData(offsetVector, timingVector, trackVector, tntypeVector)
    local keyData = {}
    for i = 1, #offsetVector do
        if tntypeVector[i] == "TapNoteType_Tap" then
            table.insert(keyData, {timingVector[i], offsetVector[i], trackVector[i]})
        end
    end
    return keyData
end

-- Function to calculate deviations
local function CalculateDeviations(keyAData, keyBData, keymode)
    if keyAData and keyBData then
        local eps = 0.1
        local deviations = {}

        -- Extract time values from key data
        local timesA = {}
        local timesB = {}
        for i = 1, #keyAData do
            table.insert(timesA, keyAData[i][1])
        end
        for i = 1, #keyBData do
            table.insert(timesB, keyBData[i][1])
        end

        -- Sort the note times for both keys
        table.sort(timesA)
        table.sort(timesB)

        -- Compute differences between sorted note times
        local diffA = {}
        local diffB = {}
        for i = 2, #timesA do
            local diff = timesA[i] - timesA[i - 1]
            if diff ~= 0 then
                table.insert(diffA, diff)
            end
        end
        for i = 2, #timesB do
            local diff = timesB[i] - timesB[i - 1]
            if diff ~= 0 then
                table.insert(diffB, diff)
            end
        end

        -- Calculate percentiles (5th and 95th) for both columns
        table.sort(diffA)
        table.sort(diffB)

        local lowerPercentileA = Percentile(diffA, 5)
        local upperPercentileA = Percentile(diffA, 95)
        local lowerPercentileB = Percentile(diffB, 5)
        local upperPercentileB = Percentile(diffB, 95)

        -- Filter differences outside the 5th and 95th percentiles
        local filteredDiffA = FilterTable(lowerPercentileA, upperPercentileA, diffA, eps)
        local filteredDiffB = FilterTable(lowerPercentileB, upperPercentileB, diffB, eps)

        -- Calculate arithmetic mean of filtered differences for A and B columns
        local k0AvgInterval = ArithmeticMean(filteredDiffA)
        local k1AvgInterval = ArithmeticMean(filteredDiffB)

        -- Average of averages
        local avgInterval = (k0AvgInterval + k1AvgInterval) / 2
        -- Halve the interval (for trills)
        avgInterval = avgInterval / (keymode / 4) -- scaler
        avgInterval = avgInterval / 2

        table.sort(keyAData, function(a, b) return a[1] < b[1] end)
        table.sort(keyBData, function(a, b) return a[1] < b[1] end)
        -- Calculate deviations
        local finder = 1
        for i = 1, #keyAData do
            local timeA, errorA = keyAData[i][1], keyAData[i][2]

            -- Find the closest previous note in keyBData
            local lastKeyBItem
            for j = finder, #keyBData do
                if keyBData[j][1] < (timeA - eps) then
                    lastKeyBItem = keyBData[j]
                    finder = j
                else
                    break
                end
            end

            -- Add deviations if conditions are met
            if lastKeyBItem then
                local errorB = lastKeyBItem[2]
                local deviation = (errorB - errorA) / avgInterval
                local absDeviation = math.abs(deviation)
                if absDeviation <= 1.5 then
                    table.insert(deviations, {timeA, absDeviation})
                end
            end
        end

        return deviations
    else
        return {0}
    end
end

-- Get manip factor based on key comparisons
local function GetManipFactor()
    -- Generate data for all keys
    keyData = GenerateKeyData(dvt, wuab, ctt, ntt)

    -- get key mode and all possible key pairs excluding middle key for keymods with odd keycount
    local keymode = GetMaxTrack()
    local keyPairs = FindKeyPairs(keymode)

    deviations = {}
    local mfs = {}
    local mfsw = {}

    local ldeviations = {}
    local lmfs = {}
    local lmfsw = {}

    local rdeviations = {}
    local rmfs = {}
    local rmfsw = {}

    for i = 1, #keyPairs do
        local keyAData = {}
        local keyBData = {}
        local hand = GetHand(keyPairs[i][1], keymode)
        for j = 1, #keyData do
            if keyPairs[i][1] == keyData[j][3] then
                table.insert(keyAData, keyData[j])
            elseif keyPairs[i][2] == keyData[j][3] then
                table.insert(keyBData, keyData[j])
            end
        end
        if #keyAData >= 2 and #keyBData >= 2 then
            local deviation = CalculateDeviations(keyAData, keyBData, keymode)
            table.insert(deviations, deviation)
            table.insert(mfs, ArithmeticMeanForDeviatons(deviation))
            table.insert(mfsw, #deviation)
            if hand == "left" then
                table.insert(ldeviations, deviation)
                table.insert(lmfs, ArithmeticMeanForDeviatons(deviation))
                table.insert(lmfsw, #deviation)
            elseif hand == "right" then
                table.insert(rdeviations, deviation)
                table.insert(rmfs, ArithmeticMeanForDeviatons(deviation))
                table.insert(rmfsw, #deviation)
            end
        end
    end

    -- Final manip factor
    local mftotal = WeightedMean(mfs, mfsw)

    -- left/right mf
    local mfleft = WeightedMean(lmfs, lmfsw)
    local mfright = WeightedMean(rmfs, rmfsw)

    if mftotal ~= mftotal then -- x ~= x means that x == NaN
        mftotal, mfleft, mfright = 0, 0, 0
    end

    return {mftotal, mfleft, mfright}
end

-- Get manip factor based on key comparisons and row time
function GetManipFactorForRow(time)
    local mfs = {}
    local mfsw = {}

    table.insert(mfs, ArithmeticMeanForTimedDeviatons(FilterTableByTime(deviations, time)))
    for i = 1, #mfs do
        table.insert(mfsw, #mfs)
    end

    local mftotal = WeightedMean(mfs, mfsw)

    if mftotal ~= mftotal then -- x ~= x means that x == NaN
        mftotal = 0
    end

    return mftotal
end

-- Manip factor display
t[#t + 1] = Def.ActorFrame {
    -- First Text Element (Either "MF" or "MF:")
    UIElements.TextToolTip(1, 1, "Common Large") .. {
        Name = "MFText",
        InitCommand = function(self)
            self:xy(mfDisplayX, mfDisplayY)
            self:zoom(mfDisplayZoom)
            if aspectRatio < 1.6 then
                -- In aspect ratio less than 1.6, "number% MF"
                self:addx(3)
                self:halign(0)
                self:settext("tMF")
            else
                -- In aspect ratio greater or equal to 1.6, "MF: number%"
                self:halign(1)
                self:settext("tMF:")
            end
        end,
        MouseOverCommand = function(self)
            local mfd = self:GetParent():GetChild("ManipFactor")
            if aspectRatio < 1.6 then
                mfd:GetParent():GetChild("ManipFactor"):settextf("(L: %2.1f%% R: %2.1f%%) %2.1f%%", mf[2] * 100, mf[3] * 100, mf[1] * 100)
            else
                mfd:GetParent():GetChild("ManipFactor"):settextf("%2.1f%% (L: %2.1f%% R: %2.1f%%)", mf[1] * 100, mf[2] * 100, mf[3] * 100)
            end
        end,
        MouseOutCommand = function(self)
            self:GetParent():GetChild("ManipFactor"):settextf("%2.1f%%", mf[1] * 100)
        end
    },
    -- Second Text Element (ManipFactor Value)
    UIElements.TextToolTip(1, 1, "Common Large") .. {
        Name = "ManipFactor",
        InitCommand = function(self)
            self:xy(mfDisplayX, mfDisplayY)
            self:zoom(mfDisplayZoom)
            if aspectRatio < 1.6 then
                -- Display "number% MF", move text more to the right
                self:halign(1)
            else
                -- Display "MF: number%"
                self:addx(3)
                self:halign(0)
            end
            self:maxwidth(480)
            self:queuecommand("Set")
        end,
        GetScoreMessageCommand = function(self, params)
            if params.score then
                score = params.score
            end
            self:queuecommand("Set")
        end,
        SetCommand = function(self)
            -- Get replay data
            local replay
            if score["GetReplay"] == nil then -- for better compatibility
                replay = score
            else
                replay = score:GetReplay()
            end
            local rate = SCREENMAN:GetTopScreen():GetReplayRate()
            td = GAMESTATE:GetCurrentSteps():GetTimingData()
            dvt = replay:GetOffsetVector()
            ctt = replay:GetTrackVector()
            nrt = replay:GetNoteRowVector()
            ntt = replay:GetTapNoteTypeVector()
            -- Convert noterows to timing in ms
            for i = 1, #nrt do
                wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i]) / rate * 1000
            end
            --------------------

            mf = GetManipFactor()

            self:diffuse(byMF(mf[1]))
            self:settextf("%2.1f%%", mf[1] * 100)
        end,
        MouseOverCommand = function(self)
            if aspectRatio < 1.6 then
                self:settextf("(L: %2.1f%% R: %2.1f%%) %2.1f%%", mf[2] * 100, mf[3] * 100, mf[1] * 100)
            else
                self:settextf("%2.1f%% (L: %2.1f%% R: %2.1f%%)", mf[1] * 100, mf[2] * 100, mf[3] * 100)
            end
        end,
        MouseOutCommand = function(self)
            self:settextf("%2.1f%%", mf[1] * 100)
        end
    }
}

return t