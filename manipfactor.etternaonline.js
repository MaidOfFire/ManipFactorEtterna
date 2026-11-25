// ==UserScript==
// @name         ManipFactor for EtternaOnline
// @namespace    http://tampermonkey.net/
// @version      0.2.0
// @description  Estimates the amount of manip from the replay data.
// @author       U1wknUzeU6, OpakyL
// @match        https://etternaonline.com/*
// @grant        none
// @updateURL    https://raw.githubusercontent.com/MaidOfFire/ManipFactorEtterna/main/manipfactor.etternaonline.js
// @downloadURL  https://raw.githubusercontent.com/MaidOfFire/ManipFactorEtterna/main/manipfactor.etternaonline.js
// @homepageURL  https://github.com/MaidOfFire/ManipFactorEtterna
// @supportURL   https://github.com/MaidOfFire/ManipFactorEtterna/issues/new
// ==/UserScript==

(function() {
    'use strict';

    const scorePagePattern = /^https:\/\/etternaonline\.com\/users\/[^\/]+\/scores\/[^\/]+\/?$/;
    let locationChangeTimeout;

    /* MF v2
       Per hand, consecutive note rows on different fingers form a pair when the chart gap g is at most 150 ms
       (chord row -> chord row is not a pair). For the later note A and the earlier note B of the other finger:
         I = time the finger needs to repeat a note at its current jack load:
             S = leaky count of that finger's notes (memory 150 ms), J = max(S_A, S_B * exp(-g/150)),
             I = -150 * ln(1 - 1/J) / 2   (I = g when J <= 1)
         p = played gap = g + offset_A - offset_B
         c = clamp((g - |p|) / I, 0, 1)   (0 when played as written, 1 when the two notes are hit together)
         pairs with a missed note are not counted (MF shows only bunching seen in the replay)
       MF = 2 * sum c / notes (all notes of the play): the share of notes that were bunched; jumping a whole trill gives 100%.
       Left and right hands: their own sum divided by their own notes.
       Trill MF (in brackets) = 2 * sum c / notes in pairs with both notes hit: how bunched the trill parts were. */
    const MF_GATE = 150, MF_TAU = 150, MF_MISS = 180;

    function fingerNotes(replayData, column) {
        const seen = new Set(), a = [];
        for (const [time, error, col] of replayData) {
            if (col !== column) continue;
            const t = Math.round(time * 1e4) / 10;   // ms, 0.1 ms grid
            if (seen.has(t)) continue;               // throw out duplicated notes
            seen.add(t);
            a.push({ t, e: Math.abs(error) >= MF_MISS ? null : error });
        }
        a.sort((p, q) => p.t - q.t);
        let S = 0;
        a.forEach((n, i) => { S = i === 0 ? 1 : 1 + S * Math.exp(-(n.t - a[i - 1].t) / MF_TAU); n.S = S; });
        return a;
    }

    function handMF(f0, f1) {
        const rows = new Map();
        [f0, f1].forEach((a, f) => a.forEach(n => { if (!rows.has(n.t)) rows.set(n.t, {}); rows.get(n.t)[f] = n; }));
        const ts = [...rows.keys()].sort((p, q) => p - q);
        let sum = 0; const inPair = new Set();
        for (let i = 1; i < ts.length; i++) {
            const r0 = rows.get(ts[i - 1]), r1 = rows.get(ts[i]), g = ts[i] - ts[i - 1];
            if ((0 in r0 && 1 in r0 && 0 in r1 && 1 in r1) || g > MF_GATE + 1e-7) continue;
            for (const f of [0, 1]) {
                const A = r1[f], B = r0[1 - f];
                if (!A || !B || A.e === null || B.e === null) continue;
                inPair.add(A); inPair.add(B);
                const J = Math.max(A.S, B.S * Math.exp(-g / MF_TAU));
                const I = J > 1 + 1e-9 ? -MF_TAU * Math.log(1 - 1 / J) / 2 : g;
                const c = Math.min(1, (g - Math.abs(g + A.e - B.e)) / I);
                if (c > 0) sum += 2 * c;
            }
        }
        return { sum, eligible: inPair.size, notes: f0.length + f1.length };
    }

    // Manip factor and left / right hand MF
    function getManipFactor(replayData) {
        const k = [0, 1, 2, 3].map(c => fingerNotes(replayData, c));
        const L = handMF(k[0], k[1]), R = handMF(k[2], k[3]);
        const n = L.notes + R.notes, p = L.eligible + R.eligible;
        return {
            manipFactor: n ? (L.sum + R.sum) / n : 0,
            trillMF: p ? (L.sum + R.sum) / p : null,   // no counted pairs: N/A, not 0
            leftHandMF: L.notes ? L.sum / L.notes : 0,
            rightHandMF: R.notes ? R.sum / R.notes : 0
        };
    }

    // mf value to color: green 0 -> yellow at `mid` -> red from `top` and above.
    // MF: yellow 12%, red 26%; trill MF (brackets): yellow 19%, red 42%. Both carry over the old dMF colours (yellow 20%, red 40%):
    // the median MF v2 of scores at dMF 20% / 40% is 12% / 26%, the median trill MF 19% / 42%.
    function byMF(x, mid = 0.12, top = 0.26) {
        const hue = x <= mid ? 120 - 60 * x / mid : Math.max(0, 60 - 60 * (x - mid) / (top - mid));
        const saturation = 0.9;
        const brightness = 0.9;
        return `hsl(${hue}, ${saturation * 100}%, ${brightness * 100}%)`;
    }

    // Fetch replay data from the page
    function fetchReplayData(callback) {
        const replayData = window.$nuxt?.$children[1]?.$children[1]?.$children[0]?.replay;
        if (replayData) {
            callback(replayData);
        } else {
            console.warn("Replay data not found yet, retrying...");
            setTimeout(() => fetchReplayData(callback), 500);
        }
    }

    // Initialize and display manip score with hover details
    const initializeManipScoreDisplay = () => {
        fetchReplayData(replayData => {
            const { manipFactor, trillMF, leftHandMF, rightHandMF } = getManipFactor(replayData);
            const manipScorePercent = (manipFactor * 100).toFixed(2); // convert to percentage

            // Create new element to display ManipScore
            const gradeOverallWrapper = document.querySelector(".grade-overall-wrapper");
            if (gradeOverallWrapper) {
                const manipDiv = document.createElement("div");
                manipDiv.style.display = "flex";
                manipDiv.style.flexDirection = "column";
                manipDiv.style.alignItems = "flex-start"; // Align to left

                const manipLabel = document.createElement("div");
                manipLabel.className = "msd font-small-bold";
                manipLabel.innerText = "MF"; // Label for Manipulation Factor
                manipLabel.style.textAlign = "left"; // Align label to the left
                manipDiv.appendChild(manipLabel);

                const manipScoreElement = document.createElement("h6");
                // MF over all notes, trill MF in brackets with its own colour (N/A when the play has no counted pairs)
                manipScoreElement.innerText = `${manipScorePercent}% `;
                manipScoreElement.style.color = byMF(manipFactor);
                const trillElement = document.createElement("span");
                trillElement.innerText = trillMF === null ? "(N/A)" : `(${(trillMF * 100).toFixed(2)}%)`;
                trillElement.style.color = trillMF === null ? "#9a9993" : byMF(trillMF, 0.19, 0.42);
                manipScoreElement.appendChild(trillElement);
                manipDiv.appendChild(manipScoreElement);

                // Create tooltip for LH-MF and RH-MF values
                const tooltip = document.createElement("div");
                tooltip.style.position = "absolute";
                tooltip.style.padding = "10px";
                tooltip.style.background = "rgba(0, 0, 0, 0.8)";
                tooltip.style.color = "#fff";
                tooltip.style.borderRadius = "5px";
                tooltip.style.display = "none";
                tooltip.style.zIndex = "1000";

                tooltip.innerHTML = `
                    <strong>Details:</strong><br>
                    Left Hand: ${(leftHandMF * 100).toFixed(2)}%<br>
                    Right Hand: ${(rightHandMF * 100).toFixed(2)}%<br>
                `;

                // Show tooltip on hover
                manipDiv.addEventListener("mouseenter", function(e) {
                    tooltip.style.display = "block";
                    tooltip.style.left = `${e.pageX + 10}px`;
                    tooltip.style.top = `${e.pageY + 10}px`;
                });

                // Move tooltip with mouse
                manipDiv.addEventListener("mousemove", function(e) {
                    tooltip.style.left = `${e.pageX + 10}px`;
                    tooltip.style.top = `${e.pageY + 10}px`;
                });

                // Hide tooltip on mouseleave
                manipDiv.addEventListener("mouseleave", function() {
                    tooltip.style.display = "none";
                });

                // Append the new element and tooltip to the page
                gradeOverallWrapper.appendChild(manipDiv);
                document.body.appendChild(tooltip);
            }
        });
    };

    const initializeWrapper = () => {
        clearTimeout(locationChangeTimeout);
        // Set a debounce to prevent multiple callings
        locationChangeTimeout = setTimeout(() => {
            if (scorePagePattern.test(window.location.href)) {
                // Check if on score page and display ManipScore
                if (scorePagePattern.test(window.location.href)) {
                    initializeManipScoreDisplay();
                }
            }
        }, 300);
    }

    // First init of script
    initializeWrapper();

    // Monkey-patch history methods to detect navigation
    (function() {
        const _pushState = history.pushState;
        const _replaceState = history.replaceState;

        history.pushState = function(state, title, url) {
            const result = _pushState.apply(this, arguments);
            window.dispatchEvent(new Event('locationchange'));
            return result;
        };

        history.replaceState = function(state, title, url) {
            const result = _replaceState.apply(this, arguments);
            window.dispatchEvent(new Event('locationchange'));
            return result;
        };

        window.addEventListener('popstate', function() {
            window.dispatchEvent(new Event('locationchange'));
        });
    })();

    // Listen for custom 'locationchange' event
    window.addEventListener('locationchange', function() {
        initializeWrapper();
    });
})();
