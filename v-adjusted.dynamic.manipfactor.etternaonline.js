// ==UserScript==
// @name         value-Adjusted Dynamic ManipFactor for EtternaOnline
// @namespace    http://tampermonkey.net/
// @version      0.1
// @description  Estimates the amount of manip from the replay data using normalized unimportance values.
// @author
// @match        https://etternaonline.com/*
// @grant        none
// ==/UserScript==

(function() {
    'use strict';

    const scorePagePattern = /^https:\/\/etternaonline\.com\/users\/[^\/]+\/scores\/[^\/]+\/?$/;
    let locationChangeTimeout;

    // Helper function to calculate weighted mean
    function weightedMean(values, weights) {
        const weightedSum = values.reduce((sum, value, index) => sum + value * weights[index], 0);
        const weightSum = weights.reduce((sum, weight) => sum + weight, 0);
        return weightedSum / weightSum;
    }

    // Function to calculate manipulation factor and Left hand MF, Right hand MF
    function getManipFactor(replayData) {
        const key0Data = [];
        const key1Data = [];
        const key2Data = [];
        const key3Data = [];

        replayData.forEach(([time, error, keyLabel]) => {
            const timeInMs = time * 1000;
            if (keyLabel === 0) {
                key0Data.push({ time: timeInMs, error });
            } else if (keyLabel === 1) {
                key1Data.push({ time: timeInMs, error });
            } else if (keyLabel === 2) {
                key2Data.push({ time: timeInMs, error });
            } else if (keyLabel === 3) {
                key3Data.push({ time: timeInMs, error });
            }
        });

        // Calculate deviations
        const k0to1Deviations = calculateDeviations(key0Data, key1Data);
        const k1to0Deviations = calculateDeviations(key1Data, key0Data);
        const k2to3Deviations = calculateDeviations(key2Data, key3Data);
        const k3to2Deviations = calculateDeviations(key3Data, key2Data);

        // Concatenate yValues and wValues for left hand and right hand
        const y_lh = k0to1Deviations.yValues.concat(k1to0Deviations.yValues);
        const w_lh = k0to1Deviations.wValues.concat(k1to0Deviations.wValues);
        const y_rh = k2to3Deviations.yValues.concat(k3to2Deviations.yValues);
        const w_rh = k2to3Deviations.wValues.concat(k3to2Deviations.wValues);

        // Compute manip_factor_left and manip_factor_right as weighted means
        const manip_factor_left = weightedMean(y_lh, w_lh);
        const manip_factor_right = weightedMean(y_rh, w_rh);

        // Compute total manipFactor as weighted average of left and right hand factors
        const totalWeightLeft = w_lh.reduce((a, b) => a + b, 0);
        const totalWeightRight = w_rh.reduce((a, b) => a + b, 0);
        const manipFactor = (manip_factor_left * totalWeightLeft + manip_factor_right * totalWeightRight) / (totalWeightLeft + totalWeightRight);

        return { manipFactor, leftHandMF: manip_factor_left, rightHandMF: manip_factor_right };
    }

    // Function to calculate deviations between keys using normalized unimportance values
    function calculateDeviations(keyAData, keyBData) {
        const eps = 0.1;
        const xValues = [];
        const yValues = [];
        const wValues = [];
        const unimportances = []; // Store avgInterval for each deviation

        const sortedKeyAData = keyAData.slice().sort((a, b) => a.time - b.time);
        const sortedKeyBData = keyBData.slice().sort((a, b) => a.time - b.time);

        const timesA = sortedKeyAData.map(({ time }) => time);
        const timesB = sortedKeyBData.map(({ time }) => time);

        const diffA = timesA.slice(1).map((time, index) => time - timesA[index]);
        const diffB = timesB.slice(1).map((time, index) => time - timesB[index]);

        // Split data into 1-second (1000 ms) segments and calculate average interval per segment
        const segmentDuration = 1000; // 1000 ms for 1-second segments
        const avgIntervals = [];
        const segmentCount = Math.ceil(Math.max(...timesA, ...timesB) / segmentDuration);

        for (let i = 0; i < segmentCount; i++) {
            const segmentStart = i * segmentDuration;
            const segmentEnd = segmentStart + segmentDuration;

            // Filter diffs within this segment
            const segmentDiffA = diffA.filter((diff, idx) => timesA[idx + 1] >= segmentStart && timesA[idx + 1] < segmentEnd);
            const segmentDiffB = diffB.filter((diff, idx) => timesB[idx + 1] >= segmentStart && timesB[idx + 1] < segmentEnd);

            // Recalculate percentiles for this segment
            const nonZeroDiffA = segmentDiffA.filter(diff => diff !== 0 && diff < segmentDuration);
            const nonZeroDiffB = segmentDiffB.filter(diff => diff !== 0 && diff < segmentDuration);

            const lowerPercentileA = percentile(nonZeroDiffA, 0);
            const upperPercentileA = percentile(nonZeroDiffA, 100);

            const lowerPercentileB = percentile(nonZeroDiffB, 0);
            const upperPercentileB = percentile(nonZeroDiffB, 100);

            const filteredDiffA = nonZeroDiffA.filter(diff => diff > lowerPercentileA - eps && diff < upperPercentileA + eps);
            const filteredDiffB = nonZeroDiffB.filter(diff => diff > lowerPercentileB - eps && diff < upperPercentileB + eps);

            // Calculate average intervals and divide by 2
            const k0AvgInterval = filteredDiffA.length ? filteredDiffA.reduce((sum, diff) => sum + diff, 0) / filteredDiffA.length : 0;
            const k1AvgInterval = filteredDiffB.length ? filteredDiffB.reduce((sum, diff) => sum + diff, 0) / filteredDiffB.length : 0;

            const avgInterval = ((k0AvgInterval + k1AvgInterval) / 2) / 2;
            avgIntervals.push(avgInterval); // Store average interval for this segment
        }

        sortedKeyAData.forEach(({ time: timeA, error: errorA }) => {
            const lastKeyBItem = sortedKeyBData.filter(({ time }) => time < timeA - eps).pop();
            if (lastKeyBItem) {
                const { time: timeB, error: errorB } = lastKeyBItem;
                const segmentIndex = Math.floor(timeA / segmentDuration);
                const avgInterval = avgIntervals[segmentIndex] || 1; // Fallback to 1 if no interval exists

                const deviation = (errorB - errorA) / avgInterval;

                if (deviation > 0 && deviation <= 1.25) {
                    xValues.push(timeA);
                    yValues.push(deviation > 1 ? 1 : deviation);
                    unimportances.push(avgInterval); // Collect unimportance for this deviation
                }
            }
        });

        // Now compute weights based on unimportances using 5th and 95th percentiles
        if (unimportances.length === 0) {
            // Avoid division by zero if no unimportances are collected
            return { xValues, yValues, wValues: [] };
        }

        const unimportanceValues = unimportances.slice(); // Copy of unimportances
        const p5 = percentile(unimportanceValues, 1);
        const p95 = percentile(unimportanceValues, 90);

        // Avoid p95 == p5 which would cause division by zero
        if (p95 === p5) {
            p95 += 1e-6; // Add a small value to p95
        }

        // Normalize unimportance values to [0, 1] using p5 and p95
        const normalizedUnimportances = unimportances.map(u => {
            let norm = (u - p5) / (p95 - p5);
            norm = Math.max(0, Math.min(norm, 1)); // Clamp between 0 and 1
            return norm;
        });

        // Apply the weighting function directly to normalized unimportances
        const desired_peak = 0; // Adjust as needed
        const total_exponent = 2; // Adjust to control sharpness
        const a = desired_peak * total_exponent;
        const b = (1 - desired_peak) * total_exponent;
        const f = x => Math.pow(x, a) * Math.pow(1 - x, b);

        const weights = normalizedUnimportances.map(f);

        // Normalize weights to sum to 1
        const weightSum = weights.reduce((acc, w) => acc + w, 0);
        const normalizedWeights = weights.map(w => w / weightSum);

        // Store weights in wValues
        for (let i = 0; i < normalizedWeights.length; i++) {
            wValues.push(normalizedWeights[i]);
        }

        return { xValues, yValues, wValues };
    }

    // Helper function to calculate percentiles
    function percentile(arr, p) {
        if (arr.length === 0) return 0;
        const sortedArr = arr.slice().sort((a, b) => a - b);
        const index = (p / 100) * (sortedArr.length - 1);
        const lower = Math.floor(index);
        const upper = lower + 1;
        const weight = index % 1;

        if (upper >= sortedArr.length) return sortedArr[lower];
        return sortedArr[lower] * (1 - weight) + sortedArr[upper] * weight;
    }

    // Convert manip factor to color (based on Lua logic)
    function byMF(x) {
        const hue = Math.max(0, 120 - (x * 300)); // hue from green to red
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
            const { manipFactor, leftHandMF, rightHandMF } = getManipFactor(replayData);
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
                manipLabel.innerText = "adjMF (value)"; // Label for Manipulation Factor
                manipLabel.style.textAlign = "left"; // Align label to the left
                manipDiv.appendChild(manipLabel);

                const manipScoreElement = document.createElement("h6");
                manipScoreElement.innerText = `${manipScorePercent}%`; // Display ManipScore in percentage
                manipScoreElement.style.color = byMF(manipFactor); // Apply color based on factor
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
                initializeManipScoreDisplay();
            }
        }, 300);
    };

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
