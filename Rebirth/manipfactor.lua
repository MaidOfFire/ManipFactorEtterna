--Version: MFv2 2026-11-25
--For Rebirth
local t = Def.ActorFrame {}

local score = SCOREMAN:GetMostRecentScore()
if not score then
    score = SCOREMAN:GetTempReplayScore()
end

local aspectRatio = GetScreenAspectRatio()

local mfDisplayX
local mfDisplayY
local mfDisplayZoom = 0.95

if aspectRatio < 1.6 then
    mfDisplayX = SCREEN_RIGHT - 88
    mfDisplayY = SCREEN_BOTTOM - 241
else
    mfDisplayX = SCREEN_RIGHT - 107
    mfDisplayY = SCREEN_BOTTOM - 241
end

local td = {} -- chart timing data
local dvt = {} -- offset vector
local ctt = {} -- track vector
local nrt = {} -- noterow vector
local wuab = {} -- note timing vector
local ntt = {} -- note type vector

local mf = {} -- manip factor {total, left, right, trill}

--[[ MF v2
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

-- MF numerator, notes in counted pairs and note count of one hand, using notes up to time `upto` (ms; nil = all)
local function HandMF(f0, f1, upto)
    local rows, ts, notes = {}, {}, 0
    for f, a in ipairs({f0, f1}) do
        for _, n in ipairs(a) do
            if upto == nil or n.t <= upto then
                local r = rows[n.t]
                if not r then r = {}; rows[n.t] = r; ts[#ts + 1] = n.t end
                r[f] = n
                notes = notes + 1
            end
        end
    end
    table.sort(ts)
    local sum, inPair = 0, {}
    for i = 2, #ts do
        local r0, r1, g = rows[ts[i - 1]], rows[ts[i]], ts[i] - ts[i - 1]
        if not ((r0[1] and r0[2] and r1[1] and r1[2]) or g > MF_GATE + 1e-7) then
            for f = 1, 2 do
                local A, B = r1[f], r0[3 - f]
                if A and B and A.e ~= nil and B.e ~= nil then
                    inPair[A] = true
                    inPair[B] = true
                    local J = math.max(A.S, B.S * math.exp(-g / MF_TAU))
                    local I = g
                    if J > 1 + 1e-9 then I = -MF_TAU * math.log(1 - 1 / J) / 2 end
                    local c = (g - math.abs(g + A.e - B.e)) / I
                    if c > 1 then c = 1 end
                    if c > 0 then sum = sum + 2 * c end
                end
            end
        end
    end
    local eligible = 0
    for _ in pairs(inPair) do eligible = eligible + 1 end
    return sum, eligible, notes
end

local fingers = {}

local function MFUpTo(upto)
    local sL, pL, nL = HandMF(fingers[1], fingers[2], upto)
    local sR, pR, nR = HandMF(fingers[3], fingers[4], upto)
    local total = (nL + nR > 0) and (sL + sR) / (nL + nR) or 0
    local left = nL > 0 and sL / nL or 0
    local right = nR > 0 and sR / nR or 0
    local trill = nil -- no counted pairs: trill MF is undefined (N/A), not 0
    if pL + pR > 0 then trill = (sL + sR) / (pL + pR) end
    return {total, left, right, trill}
end

-- Get manip factor {total, left, right, trill}
local function GetManipFactor()
    for k = 0, 3 do
        fingers[k + 1] = FingerNotes(dvt, wuab, ctt, k, ntt)
    end
    return MFUpTo(nil)
end

-- Manip factor of the notes up to a row time (ms)
function GetManipFactorForRow(time)
    if #fingers == 0 then return 0 end
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
    UIElements.QuadButton(1, 1) .. {
        InitCommand = function(self)
            self:xy(mfDisplayX - 35, mfDisplayY - 22)
            self:halign(0):valign(0)
            self:zoomto(100,30)
            self:diffusealpha(0)
        end,
        MouseOverCommand = function(self)
            ShowMF(self:GetParent():GetChild("ManipFactor"), true, true)
        end,
        MouseOutCommand = function(self)
            ShowMF(self:GetParent():GetChild("ManipFactor"), false)
        end
    },
    LoadFont("Common Normal") .. {
        InitCommand = function(self)
            self:xy(mfDisplayX + 3, mfDisplayY)
            self:halign(0):valign(1)
            self:zoom(mfDisplayZoom)
            self:settext("MF")
        end
    },
    LoadFont("Common Normal") .. {
        Name = "ManipFactor",
        InitCommand = function(self)
            self:xy(mfDisplayX, mfDisplayY)
            self:zoom(mfDisplayZoom)
            self:halign(1):valign(1)
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
        end
    }
}

return t