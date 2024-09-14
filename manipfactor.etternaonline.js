// ==UserScript==
// @name         ManipFactor for EtternaOnline
// @namespace    http://tampermonkey.net/
// @version      0.1.5
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

        const k0to1Deviations = calculateDeviations(key0Data, key1Data);
        const k1to0Deviations = calculateDeviations(key1Data, key0Data);
        const k2to3Deviations = calculateDeviations(key2Data, key3Data);
        const k3to2Deviations = calculateDeviations(key3Data, key2Data);

        const mfk0to1 = k0to1Deviations.yValues.reduce((a, b) => a + b, 0) / k0to1Deviations.yValues.length;
        const mfk1to0 = k1to0Deviations.yValues.reduce((a, b) => a + b, 0) / k1to0Deviations.yValues.length;
        const mfk2to3 = k2to3Deviations.yValues.reduce((a, b) => a + b, 0) / k2to3Deviations.yValues.length;
        const mfk3to2 = k3to2Deviations.yValues.reduce((a, b) => a + b, 0) / k3to2Deviations.yValues.length;

        // LH-MF (Weighted average of 0→1 and 1→0)
        const leftHandWeights = [
            k0to1Deviations.yValues.length,
            k1to0Deviations.yValues.length
        ];
        const leftHandMF = weightedMean([mfk0to1, mfk1to0], leftHandWeights);

        // RH-MF (Weighted average of 2→3 and 3→2)
        const rightHandWeights = [
            k2to3Deviations.yValues.length,
            k3to2Deviations.yValues.length
        ];
        const rightHandMF = weightedMean([mfk2to3, mfk3to2], rightHandWeights);

        // Overall manip factor
        const overallWeights = [
            k0to1Deviations.yValues.length,
            k1to0Deviations.yValues.length,
            k2to3Deviations.yValues.length,
            k3to2Deviations.yValues.length
        ];
        const manipFactor = weightedMean([mfk0to1, mfk1to0, mfk2to3, mfk3to2], overallWeights);

        return { manipFactor, leftHandMF, rightHandMF };
    }

    // Function to calculate ManipScore based on manip factor
    function manipScoreFunction(manipFactor) {
        if (manipFactor <= 0.1) {
            return 1;
        } else {
            const C = 2.3;
            const k = 10;
            const b = -0.1;
            return Math.exp(-k * Math.pow(manipFactor + b, C));
        }
    }

    // Function to calculate deviations between keys
    function calculateDeviations(keyAData, keyBData) {
        const eps = 0.1;
        const xValues = [];
        const yValues = [];

        const sortedKeyAData = keyAData.slice().sort((a, b) => a.time - b.time);
        const sortedKeyBData = keyBData.slice().sort((a, b) => a.time - b.time);

        const timesA = sortedKeyAData.map(({ time }) => time);
        const timesB = sortedKeyBData.map(({ time }) => time);

        const diffA = timesA.slice(1).map((time, index) => time - timesA[index]);
        const diffB = timesB.slice(1).map((time, index) => time - timesB[index]);

        const nonZeroDiffA = diffA.filter(diff => diff !== 0);
        const nonZeroDiffB = diffB.filter(diff => diff !== 0);

        const lowerPercentileA = percentile(nonZeroDiffA, 5);
        const upperPercentileA = percentile(nonZeroDiffA, 95);

        const lowerPercentileB = percentile(nonZeroDiffB, 5);
        const upperPercentileB = percentile(nonZeroDiffB, 95);

        const filteredDiffA = nonZeroDiffA.filter(diff => diff > lowerPercentileA - eps && diff < upperPercentileA + eps);
        const filteredDiffB = nonZeroDiffB.filter(diff => diff > lowerPercentileB - eps && diff < upperPercentileB + eps);

        const k0AvgInterval = filteredDiffA.reduce((sum, diff) => sum + diff, 0) / filteredDiffA.length;
        const k1AvgInterval = filteredDiffB.reduce((sum, diff) => sum + diff, 0) / filteredDiffB.length;

        let avgInterval = (k0AvgInterval + k1AvgInterval) / 2;
        avgInterval /= 2;

        sortedKeyAData.forEach(({ time: timeA, error: errorA }) => {
            const lastKeyBItem = sortedKeyBData.filter(({ time }) => time < timeA - eps).pop();
            if (lastKeyBItem) {
                const { time: timeB, error: errorB } = lastKeyBItem;
                const deviation = (errorB - errorA) / avgInterval;
                const absDeviation = Math.abs(deviation);
                if (absDeviation <= 1.5) {
                    xValues.push(timeA);
                    yValues.push(absDeviation);
                }
            }
        });

        return { xValues, yValues };
    }

    // Helper function to calculate percentiles
    function percentile(arr, p) {
        if (arr.length === 0) return 0;
        arr.sort((a, b) => a - b);
        const index = (p / 100) * (arr.length - 1);
        const lower = Math.floor(index);
        const upper = lower + 1;
        const weight = index % 1;

        if (upper >= arr.length) return arr[lower];
        return arr[lower] * (1 - weight) + arr[upper] * weight;
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
                manipLabel.innerText = "MF"; // Label for Manipulation Factor
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
