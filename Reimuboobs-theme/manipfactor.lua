--Version: MFv2 2026-11-25
--For Reimuboobs-theme
local t = Def.ActorFrame {}

local score = SCOREMAN:GetMostRecentScore()
if not score then
    score = SCOREMAN:GetTempReplayScore()
end

local mfDisplayX
local mfDisplayY
local mfDisplayZoom = 0.25

mfDisplayX = SCREEN_RIGHT - 28
mfDisplayY = SCREEN_CENTER_Y + 66

local td = {} -- chart timing data
local dvt = {} -- offset vector
local ctt = {} -- track vector
local nrt = {} -- noterow vector
local wuab = {} -- note timing vector
local ntt = {} -- note type vector

local mf = {} -- manip factor {total, left, right, trill}

--[[ MF v2
  Hands: the left and right half of the columns (any keymode; on odd keymodes the middle column is in neither hand).
  Per hand, consecutive note rows on different fingers form a pair when the chart gap g is at most 150 ms
  (chord row -> chord row is not a pair). For each pair the later note A (one finger) and the earlier note B
  (other finger):
    I = time the finger needs to repeat a note at its current jack load:
        S = leaky count of that finger's notes (memory 150 ms), J = max(S_A, S_B * exp(-g/150)),
        I = -150 * ln(1 - 1/J) / 2   (I = g when J <= 1)
    p = played gap = g + offset_A - offset_B
    c = clamp((g - |p|) / I, 0, 1)   -- 0 when played as written, 1 when the two notes are hit together
    pairs with a missed note are not counted (MF shows only bunching seen in the replay)
  MF = 2 * sum c / notes (all notes of the play): the share of notes that were bunched. Jumping a whole trill gives 100%.
  Left and right hands: their own sum divided by their own notes.
  Trill MF (in brackets) = 2 * sum c / notes in pairs with both notes hit: how bunched the trill parts were,
  whatever their share of the chart. ]]
local MF_GATE = 150 -- ms, largest chart gap of a pair
local MF_TAU = 150 -- ms, jack-load memory
local MF_MISS = 180 -- ms, offsets at or beyond this are misses

-- one finger's notes, sorted by time, with the leaky jack count S
local function FingerNotes(offsetVector, timingVector, trackVector, track, tntypeVector)
    local a, seen = {}, {}
    for i = 1, #offsetVector do
        if trackVector[i] == track and tntypeVector[i] ~= "TapNoteType_Mine" and tntypeVector[i] ~= "TapNoteType_HoldTail" then
            local t = math.floor(timingVector[i] * 10 + 0.5) / 10
            if not seen[t] then -- throw out duplicated notes
                seen[t] = true
                local e = offsetVector[i]
                if math.abs(e) >= MF_MISS then e = nil end
                a[#a + 1] = {t = t, e = e}
            end
        end
    end
    table.sort(a, function(p, q) return p.t < q.t end)
    local S = 0
    for i = 1, #a do
        if i == 1 then S = 1 else S = 1 + S * math.exp(-(a[i].t - a[i - 1].t) / MF_TAU) end
        a[i].S = S
    end
    return a
end

-- MF numerator, notes in counted pairs and note count of one hand (its columns' note lists), using notes up to time `upto`
-- (ms; nil = all). Any number of fingers per hand: neighbouring rows pair unless both are chords (2+ notes of the hand); each
-- later note pairs once, with the earlier row's note on another finger it closed the most (ties: the nearest finger). With two
-- fingers per hand (4K) there is only one such note, so this is the 4K rule exactly.
local function HandMF(cols, upto)
    local rows, ts, notes = {}, {}, 0
    for f, a in ipairs(cols) do
        for _, n in ipairs(a) do
            if upto == nil or n.t <= upto then
                local r = rows[n.t]
                if not r then r = {count = 0}; rows[n.t] = r; ts[#ts + 1] = n.t end
                r[f] = n
                r.count = r.count + 1
                notes = notes + 1
            end
        end
    end
    table.sort(ts)
    local sum, inPair = 0, {}
    for i = 2, #ts do
        local r0, r1, g = rows[ts[i - 1]], rows[ts[i]], ts[i] - ts[i - 1]
        if not ((r0.count >= 2 and r1.count >= 2) or g > MF_GATE + 1e-7) then
            for fa = 1, #cols do
                local A = r1[fa]
                if A and A.e ~= nil then
                    local best, bestC, bestD
                    for fb = 1, #cols do
                        local B = r0[fb]
                        if fb ~= fa and B and B.e ~= nil then
                            local J = math.max(A.S, B.S * math.exp(-g / MF_TAU))
                            local I = g
                            if J > 1 + 1e-9 then I = -MF_TAU * math.log(1 - 1 / J) / 2 end
                            local c = (g - math.abs(g + A.e - B.e)) / I
                            if c > 1 then c = 1 elseif c < 0 then c = 0 end
                            local d = math.abs(fb - fa)
                            if best == nil or c > bestC or (c == bestC and d < bestD) then best, bestC, bestD = B, c, d end
                        end
                    end
                    if best then
                        inPair[A] = true
                        inPair[best] = true
                        sum = sum + 2 * bestC
                    end
                end
            end
        end
    end
    local eligible = 0
    for _ in pairs(inPair) do eligible = eligible + 1 end
    return sum, eligible, notes
end

-- Key count of the chart (as dev's keymode support); unknown steps types fall back to the highest column in the replay
local function GetKeymode()
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
    local steps = GAMESTATE and GAMESTATE:GetCurrentSteps()
    local k = steps and keys[steps:GetStepsType()]
    if k then return k end
    k = 0
    for i = 1, #ctt do if ctt[i] + 1 > k then k = ctt[i] + 1 end end
    return k
end

-- Columns of each hand: the left half and the right half; on odd keymodes the middle column belongs to neither hand
-- (its notes still count in the MF denominator)
local function HandColumns(keymode)
    local half = math.floor(keymode / 2)
    local left, right = {}, {}
    for c = 0, half - 1 do left[#left + 1] = c end
    for c = keymode - half, keymode - 1 do right[#right + 1] = c end
    return left, right
end

local hands = {{}, {}} -- note lists per column, per hand
local middle = {} -- notes outside both hands (middle column of odd keymodes)

local function MFUpTo(upto)
    local sL, pL, nL = HandMF(hands[1], upto)
    local sR, pR, nR = HandMF(hands[2], upto)
    local nM = 0
    for _, n in ipairs(middle) do if upto == nil or n.t <= upto then nM = nM + 1 end end
    local nAll = nL + nR + nM
    local total = nAll > 0 and (sL + sR) / nAll or 0
    local left = nL > 0 and sL / nL or 0
    local right = nR > 0 and sR / nR or 0
    local trill = nil -- no counted pairs: trill MF is undefined (N/A), not 0
    if pL + pR > 0 then trill = (sL + sR) / (pL + pR) end
    return {total, left, right, trill}
end

-- Get manip factor {total, left, right, trill}
local function GetManipFactor()
    local keymode = GetKeymode()
    local leftCols, rightCols = HandColumns(keymode)
    hands = {{}, {}}
    for h, cols in ipairs({leftCols, rightCols}) do
        for _, c in ipairs(cols) do
            hands[h][#hands[h] + 1] = FingerNotes(dvt, wuab, ctt, c, ntt)
        end
    end
    middle = {}
    if keymode % 2 == 1 then middle = FingerNotes(dvt, wuab, ctt, (keymode - 1) / 2, ntt) end
    return MFUpTo(nil)
end

-- Manip factor of the notes up to a row time (ms)
function GetManipFactorForRow(time)
    if #hands[1] + #hands[2] == 0 then return 0 end
    return MFUpTo(time)[1]
end

-- mf value to color: green 0 -> yellow at `mid` -> red from `top` and above.
-- MF: yellow 12%, red 26%; trill MF (brackets): yellow 19%, red 42%. Both carry over the old dMF colours (yellow 20%, red 40%):
-- the median MF v2 of scores at dMF 20% / 40% is 12% / 26%, the median trill MF 19% / 42%.
local function byMF(x, mid, top)
    mid, top = mid or 0.12, top or 0.26
    local hue -- 120 (green) to 60 (yellow) to 0 (red) degrees
    if x <= mid then
        hue = 120 - 60 * x / mid
    else
        hue = math.max(0, 60 - 60 * (x - mid) / (top - mid))
    end
    local saturation = 0.9
    local brightness = 0.9

    return HSV(hue, saturation, brightness)
end

-- Show "MF (trill MF)", optionally with the hands; the bracket gets its own colour
local function ShowMF(actor, withHands, handsFirst)
    local main = string.format("%2.1f%%", mf[1] * 100)
    local br = mf[4] and string.format("(%2.1f%%)", mf[4] * 100) or "(N/A)"
    local hands = string.format("(L: %2.1f%% R: %2.1f%%)", mf[2] * 100, mf[3] * 100)
    local text, pos
    if withHands and handsFirst then
        text, pos = hands .. " " .. main .. " " .. br, #hands + #main + 2
    elseif withHands then
        text, pos = main .. " " .. br .. " " .. hands, #main + 1
    else
        text, pos = main .. " " .. br, #main + 1
    end
    actor:settext(text)
    actor:ClearAttributes()
    actor:diffuse(byMF(mf[1]))
    actor:AddAttribute(pos, {Length = #br, Diffuse = mf[4] and byMF(mf[4], 0.19, 0.42) or color("#9a9993")})
end

-- Manip factor display
t[#t + 1] = Def.ActorFrame {
    UIElements.TextToolTip(1, 1, "Common Large") .. {
        InitCommand = function(self)
            self:xy(mfDisplayX + 3, mfDisplayY):halign(0)
            self:zoom(mfDisplayZoom)
            self:settext("MF")
        end,
        MouseOverCommand = function(self)
            ShowMF(self:GetParent():GetChild("ManipFactor"), true, true)
        end,
        MouseOutCommand = function(self)
            ShowMF(self:GetParent():GetChild("ManipFactor"), false)
        end
    },
    UIElements.TextToolTip(1, 1, "Common Large") .. {
        Name = "ManipFactor",
        InitCommand = function(self)
            self:xy(mfDisplayX, mfDisplayY):halign(1)
            self:zoom(mfDisplayZoom)
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
            if score["GetReplay"] == nil then  -- for better compatibility
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

            ShowMF(self, false)
        end,
        MouseOverCommand = function(self)
            ShowMF(self, true, true)
        end,
        MouseOutCommand = function(self)
            ShowMF(self, false)
        end
    }
}

return t