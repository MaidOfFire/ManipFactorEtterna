-- Version: 10.07.24 22:05 JST
-- For Til Death
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
    mfDisplayX = SCREEN_LEFT + 50
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

-- deviations
local deviations = {}
local ldeviations = {}
local rdeviations = {}
local lweights = {}
local rweights = {}

-- Helper function to filter table by percentiles
local function FilterTable(low, high, x, eps)
    local y = {}
    for i = 1, #x do
        if x[i] > (low - eps) and x[i] < (high + eps) and x[i] ~= 0 then
            table.insert(y, x[i])
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

-- Helper function to calculate Arithmetic Mean for deviations
local function ArithmeticMeanForDeviations(x)
    if #x == 0 then return 0 end
    local sum = 0
    for i = 1, #x do
        sum = sum + x[i][2]
    end
    return sum / #x
end

-- Helper function to calculate Weighted Mean for deviations
local function WeightedMeanForDeviations(deviations, weights)
    if #deviations == 0 then return 0 end
    local sum = 0
    local weightSum = 0
    for i = 1, #deviations do
        sum = sum + deviations[i][2] * weights[i]
        weightSum = weightSum + weights[i]
    end
    return sum / weightSum
end

-- Helper function to calculate percentiles
local function Percentile(arr, p)
    if #arr == 0 then return 0 end
    table.sort(arr)
    local index = (p / 100) * (#arr - 1) + 1
    local lower = math.floor(index)
    local upper = lower + 1
    local weight = index % 1

    if upper > #arr then
        return arr[#arr]
    else
        return arr[lower] * (1 - weight) + arr[upper] * weight
    end
end

-- mf value to hsv color
local function byMF(x)
    local hue = math.max(0, 120 - (x * 300)) -- hue from green to red
    local saturation = 0.9 -- Full saturation
    local brightness = 0.9 -- Full brightness

    return HSV(hue, saturation, brightness)
end

-- Function to get the maximum number of tracks (keys)
local function GetMaxTrack()
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
                -- Middle key, skip pairing
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
local function GenerateKeyData(offsetVector, timingVector, trackVector, tapNoteTypeVector)
    local keyData = {}
    for i = 1, #offsetVector do
        if tapNoteTypeVector[i] ~= "TapNoteType_Mine" and tapNoteTypeVector[i] ~= "TapNoteType_HoldTail" then
            table.insert(keyData, {timingVector[i], offsetVector[i], trackVector[i]})
        end
    end
    return keyData
end

-- Function to calculate deviations with dynamic intervals (splitting into 1000 ms chunks)
local function CalculateDeviations(keyAData, keyBData)
    if #keyAData < 2 or #keyBData < 2 then return {}, {} end
    local eps = 0.1
    local deviations = {}
    local unimportances = {} -- Store avgInterval for each deviation

    -- Extract time values from key data
    local timesA = {}
    local timesB = {}
    for i = 1, #keyAData do
        timesA[i] = keyAData[i][1]
    end
    for i = 1, #keyBData do
        timesB[i] = keyBData[i][1]
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
            diffA[#diffA + 1] = diff
        end
    end
    for i = 2, #timesB do
        local diff = timesB[i] - timesB[i - 1]
        if diff ~= 0 then
            diffB[#diffB + 1] = diff
        end
    end

    -- Split data into 1-second (1000 ms) segments and calculate average interval per segment
    local segmentDuration = 1000 -- in ms
    local maxTime = math.max(timesA[#timesA] or 0, timesB[#timesB] or 0)
    local segmentCount = math.ceil(maxTime / segmentDuration)

    local avgIntervals = {}

    for i = 1, segmentCount do
        local segmentStart = (i - 1) * segmentDuration
        local segmentEnd = segmentStart + segmentDuration

        -- Filter diffs within this segment
        local segmentDiffA = {}
        local segmentDiffB = {}

        for idx = 1, #diffA do
            if timesA[idx + 1] >= segmentStart and timesA[idx + 1] < segmentEnd then
                local diff = diffA[idx]
                if diff ~= 0 and diff < segmentDuration then
                    table.insert(segmentDiffA, diff)
                end
            end
        end

        for idx = 1, #diffB do
            if timesB[idx + 1] >= segmentStart and timesB[idx + 1] < segmentEnd then
                local diff = diffB[idx]
                if diff ~= 0 and diff < segmentDuration then
                    table.insert(segmentDiffB, diff)
                end
            end
        end

        -- Recalculate percentiles for this segment
        local nonZeroDiffA = segmentDiffA
        local nonZeroDiffB = segmentDiffB

        local lowerPercentileA = Percentile(nonZeroDiffA, 0)
        local upperPercentileA = Percentile(nonZeroDiffA, 100)

        local lowerPercentileB = Percentile(nonZeroDiffB, 0)
        local upperPercentileB = Percentile(nonZeroDiffB, 100)

        local filteredDiffA = FilterTable(lowerPercentileA, upperPercentileA, nonZeroDiffA, eps)
        local filteredDiffB = FilterTable(lowerPercentileB, upperPercentileB, nonZeroDiffB, eps)

        -- Calculate average intervals and divide by 2
        local k0AvgInterval = #filteredDiffA > 0 and ArithmeticMean(filteredDiffA) or 0
        local k1AvgInterval = #filteredDiffB > 0 and ArithmeticMean(filteredDiffB) or 0

        local avgInterval = (math.min(k0AvgInterval, k1AvgInterval) / 2)
        avgIntervals[i] = avgInterval -- Store average interval for this segment
    end

    -- Now compute deviations using avgInterval per segment
    table.sort(keyAData, function(a, b) return a[1] < b[1] end)
    table.sort(keyBData, function(a, b) return a[1] < b[1] end)

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
            local segmentIndex = math.floor(timeA / segmentDuration) + 1
            local avgInterval = avgIntervals[segmentIndex] or 1 -- Fallback to 1 if no interval exists

            local deviation = (errorB - errorA) / avgInterval

            -- Adjust conditions for accepting deviations
            if deviation > 0 and deviation <= 1.25 then
                local yValue = deviation > 1 and 1 or deviation
                table.insert(deviations, {timeA, yValue})
                table.insert(unimportances, avgInterval) -- Collect unimportance for this deviation
            end
        end
    end

    -- Now compute weights based on unimportances using 5th and 80th percentiles
    if #unimportances == 0 then
        -- Avoid division by zero if no unimportances are collected
        return deviations, {}
    end

    local unimportanceValues = {}
    for i = 1, #unimportances do
        unimportanceValues[i] = unimportances[i]
    end
    local p5 = Percentile(unimportanceValues, 5)
    local p95 = Percentile(unimportanceValues, 80)

    if p95 == p5 then
        p95 = p95 + 1e-6 -- Avoid division by zero
    end

    -- Normalize unimportance values to [0, 1]
    local normalizedUnimportances = {}
    for i = 1, #unimportances do
        local norm = (unimportances[i] - p5) / (p95 - p5)
        norm = math.max(0, math.min(norm, 1)) -- Clamp between 0 and 1
        normalizedUnimportances[i] = norm
    end

    -- Apply sigmoid function
    local desired_peak = 0.5 -- Adjust as needed (between 0 and 1)
    local steepness = 10 -- Adjust steepness (higher value = sharper transition)
    local k = steepness
    local x0 = desired_peak
    local function f(x)
        return 1 / (1 + math.exp(k * (x - x0)))
    end

    local weights = {}
    for i = 1, #normalizedUnimportances do
        weights[i] = f(normalizedUnimportances[i])
    end

    -- Normalize weights to sum to 1
    local weightSum = 0
    for i = 1, #weights do
        weightSum = weightSum + weights[i]
    end
    if weightSum == 0 then
        return deviations, {}
    end
    local normalizedWeights = {}
    for i = 1, #weights do
        normalizedWeights[i] = weights[i] / weightSum
    end

    return deviations, normalizedWeights
end

-- Get manip factor based on key comparisons
local function GetManipFactor()
    -- Generate data for all keys
    keyData = GenerateKeyData(dvt, wuab, ctt, ntt)

    -- Get key mode and specific key pairs
    local keymode = GetMaxTrack()
    local keyPairs = FindKeyPairs(keymode)

    deviations = {}
    ldeviations = {}
    rdeviations = {}
    lweights = {}
    rweights = {}

    for i = 1, #keyPairs do
        local keyA = keyPairs[i][1]
        local keyB = keyPairs[i][2]
        local hand = GetHand(keyA, keymode)

        local keyAData = {}
        local keyBData = {}

        for j = 1, #keyData do
            if keyData[j][3] == keyA then
                table.insert(keyAData, keyData[j])
            elseif keyData[j][3] == keyB then
                table.insert(keyBData, keyData[j])
            end
        end

        local deviation, weights = CalculateDeviations(keyAData, keyBData)
        if #deviation > 0 then
            -- Collect deviations for total MF calculation
            for d = 1, #deviation do
                table.insert(deviations, deviation[d])
            end

            -- Collect deviations and weights for left or right hand
            if hand == "left" then
                for d = 1, #deviation do
                    table.insert(ldeviations, deviation[d])
                    table.insert(lweights, weights[d])
                end
            elseif hand == "right" then
                for d = 1, #deviation do
                    table.insert(rdeviations, deviation[d])
                    table.insert(rweights, weights[d])
                end
            end
        end
    end

    -- Compute original manip factors (arithmetic mean)
    local manip_factor_left_original = ArithmeticMeanForDeviations(ldeviations)
    local manip_factor_right_original = ArithmeticMeanForDeviations(rdeviations)
    local y_lh_count = #ldeviations
    local y_rh_count = #rdeviations
    local total_count = y_lh_count + y_rh_count
    local mftotal_original = total_count > 0 and ((manip_factor_left_original * y_lh_count + manip_factor_right_original * y_rh_count) / total_count) or 0

    -- Compute weighted manip factors
    local manip_factor_left_weighted = WeightedMeanForDeviations(ldeviations, lweights)
    local manip_factor_right_weighted = WeightedMeanForDeviations(rdeviations, rweights)

    local totalWeightLeft = 0
    for i = 1, #lweights do
        totalWeightLeft = totalWeightLeft + lweights[i]
    end

    local totalWeightRight = 0
    for i = 1, #rweights do
        totalWeightRight = totalWeightRight + rweights[i]
    end

    local totalWeight = totalWeightLeft + totalWeightRight
    local mftotal_weighted = totalWeight > 0 and ((manip_factor_left_weighted * totalWeightLeft + manip_factor_right_weighted * totalWeightRight) / totalWeight) or 0

    if mftotal_original ~= mftotal_original then -- x ~= x means that x == NaN
        mftotal_original, manip_factor_left_original, manip_factor_right_original = 0, 0, 0
    end

    if mftotal_weighted ~= mftotal_weighted then -- x ~= x means that x == NaN
        mftotal_weighted, manip_factor_left_weighted, manip_factor_right_weighted = 0, 0, 0
    end

    return {
        original = {mftotal_original, manip_factor_left_original, manip_factor_right_original},
        weighted = {mftotal_weighted, manip_factor_left_weighted, manip_factor_right_weighted}
    }
end

-- Get manip factor based on key comparisons and row time
function GetManipFactorForRow(time)
    -- Collect deviations up to the given time
    local totalDeviations = {}
    for i = 1, #deviations do
        if deviations[i][1] <= time then
            table.insert(totalDeviations, deviations[i])
        end
    end

    local mftotal = ArithmeticMeanForDeviations(totalDeviations)

    if mftotal ~= mftotal then -- x ~= x means that x == NaN
        mftotal = 0
    end

    return mftotal
end

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
                self:settext("dMF")
            else
                -- In aspect ratio greater or equal to 1.6, "MF: number%"
                self:halign(1)
                self:settext("dMF:")
            end
        end,
        MouseOverCommand = function(self)
            local mfd = self:GetParent():GetChild("ManipFactor")
            local mf_values = mfd.mf or {original = {0, 0, 0}, weighted = {0, 0, 0}}
            if aspectRatio < 1.6 then
                mfd:settextf("(L: %2.1f%% R: %2.1f%%) %2.1f%%", mf_values.original[2] * 100, mf_values.original[3] * 100, mf_values.original[1] * 100)
            else
                mfd:settextf("%2.1f%% (L: %2.1f%% R: %2.1f%%)", mf_values.original[1] * 100, mf_values.original[2] * 100, mf_values.original[3] * 100)
            end
        end,
        MouseOutCommand = function(self)
            local mfd = self:GetParent():GetChild("ManipFactor")
            local mf_values = mfd.mf or {original = {0, 0, 0}, weighted = {0, 0, 0}}
            mfd:settextf("%2.1f%% (%2.1f%%)", mf_values.original[1] * 100, mf_values.weighted[1] * 100)
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
            wuab = {}
            for i = 1, #nrt do
                wuab[i] = td:GetElapsedTimeFromNoteRow(nrt[i]) / rate * 1000
            end
            --------------------

            local mf_values = GetManipFactor()
            self.mf = mf_values -- Store mf in self for access in MouseOverCommand

            -- Use the weighted MF for color, original MF for display
            self:diffuse(byMF(mf_values.weighted[1]))
            self:settextf("%2.1f%% (%2.1f%%)", mf_values.original[1] * 100, mf_values.weighted[1] * 100)
        end,
        MouseOverCommand = function(self)
            local mf_values = self.mf or {original = {0, 0, 0}, weighted = {0, 0, 0}}
            if aspectRatio < 1.6 then
                self:settextf("(L: %2.1f%% R: %2.1f%%) %2.1f%%", mf_values.original[2] * 100, mf_values.original[3] * 100, mf_values.original[1] * 100)
            else
                self:settextf("%2.1f%% (L: %2.1f%% R: %2.1f%%)", mf_values.original[1] * 100, mf_values.original[2] * 100, mf_values.original[3] * 100)
            end
        end,
        MouseOutCommand = function(self)
            local mf_values = self.mf or {original = {0, 0, 0}, weighted = {0, 0, 0}}
            self:settextf("%2.1f%% (%2.1f%%)", mf_values.original[1] * 100, mf_values.weighted[1] * 100)
        end
    }
}

return t
