// ==UserScript==
// @name         Analyser for Etternaonline
// @namespace    http://tampermonkey.net/
// @version      5.0
// @description  Calculate and plot filtered proportions of error-time differences between keys on EtternaOnline in a combined figure with subplots.
// @author       U1wknUzeU6
// @match        https://etternaonline.com/*
// @grant        none
// @require      https://cdn.plot.ly/plotly-latest.min.js
// ==/UserScript==

// Helper function to calculate percentile
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

(function() {
    "use strict";

    const scorePagePattern = /^https:\/\/etternaonline\.com\/users\/[^\/]+\/scores\/[^\/]+\/?$/;

    const initializePlot = () => {
        function fetchReplayData(callback) {
            const replayData = window.$nuxt?.$children[1]?.$children[1]?.$children[0]?.replay;
            if (replayData) {
                callback(replayData);
            } else {
                console.warn("Replay data not found yet, retrying...");
                setTimeout(() => fetchReplayData(callback), 500);
            }
        }

        function fetchPageHeader(callback) {
            const headerElement = document.querySelector(".header");
            if (headerElement) {
                callback(headerElement);
            } else {
                console.warn("Page header not found yet, retrying...");
                setTimeout(() => fetchPageHeader(callback), 500);
            }
        }

        fetchReplayData(replayData => {
            fetchPageHeader(headerElement => {
                const playerName = headerElement.querySelector(".username a")?.textContent.trim();
                const songName = headerElement.querySelector(".song-name a")?.textContent.trim();
                const dateTime = headerElement.querySelector(".datetime")?.textContent.trim();
                const modifiers = headerElement.querySelector(".modifiers")?.textContent.trim().replace("Modifiers:", "").trim();

                function calculateProportions(keyAData, keyBData) {
                    const eps = 0.1
                    const xValues = [];
                    const yValues = [];

                    // Convert keyAData and keyBData to arrays of note times
                    const timesA = keyAData.map(({ time }) => time);
                    const timesB = keyBData.map(({ time }) => time);

                    // Sort the note times
                    const sortedTimesA = timesA.slice().sort((a, b) => a - b);
                    const sortedTimesB = timesB.slice().sort((a, b) => a - b);

                    // Compute the differences between sorted note times for A and B columns
                    const diffA = sortedTimesA.slice(1).map((time, index) => time - sortedTimesA[index]);
                    const diffB = sortedTimesB.slice(1).map((time, index) => time - sortedTimesB[index]);

                    // Remove zero differences (if any)
                    const nonZeroDiffA = diffA.filter(diff => diff !== 0);
                    const nonZeroDiffB = diffB.filter(diff => diff !== 0);

                    // Calculate the 5th and 95th percentiles for A and B columns
                    const lowerPercentileA = percentile(nonZeroDiffA, 5);
                    const upperPercentileA = percentile(nonZeroDiffA, 95);

                    const lowerPercentileB = percentile(nonZeroDiffB, 5);
                    const upperPercentileB = percentile(nonZeroDiffB, 95);

                    // Filter out the differences outside the 5th and 95th percentiles for A and B columns
                    const filteredDiffA = nonZeroDiffA.filter(diff => diff > (lowerPercentileA-eps) && (diff < upperPercentileA+eps));
                    const filteredDiffB = nonZeroDiffB.filter(diff => diff > (lowerPercentileB-eps) && (diff < upperPercentileB+eps));

                    // Calculate the arithmetic mean of the filtered differences for A and B columns
                    const k0AvgInterval = filteredDiffA.reduce((sum, diff) => sum + diff, 0) / filteredDiffA.length;
                    const k1AvgInterval = filteredDiffB.reduce((sum, diff) => sum + diff, 0) / filteredDiffB.length;

                    // Average of averages
                    let avgInterval = k0AvgInterval//(k0AvgInterval + k1AvgInterval) / 2;
                    // The half of the interval because the interval between notes in a trill is twice as short
                    avgInterval /= 2;

                    const sortedKeyAData = keyAData.slice().sort((a, b) => a.time - b.time);
                    const sortedKeyBData = keyBData.slice().sort((a, b) => a.time - b.time);


                    sortedKeyAData.forEach(({ time: timeA, error: errorA }) => {
                        const lastKeyBItem = sortedKeyBData.filter(({ time }) => time < (timeA - eps)).pop();
                        if (lastKeyBItem) {
                            const { time: timeB, error: errorB } = lastKeyBItem;
                            const deviation = (errorB - errorA) / avgInterval;

                            if ((deviation > 0) & (deviation <= 1.2)) {
                                xValues.push(timeA);
                                yValues.push(deviation > 1 ? 1 : deviation);
                            }
                        }
                    });
                    return { xValues, yValues };
                }

                const key0Data = [];
                const key1Data = [];
                const key2Data = [];
                const key3Data = [];

                replayData.forEach(row => {
                    const [time, error, keyLabel] = row;
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

                const plotData = [
                    { title: "Key 0 to Key 1", data: calculateProportions(key0Data, key1Data) },
                    { title: "Key 1 to Key 0", data: calculateProportions(key1Data, key0Data) },
                    { title: "Key 2 to Key 3", data: calculateProportions(key2Data, key3Data) },
                    { title: "Key 3 to Key 2", data: calculateProportions(key3Data, key2Data) }
                ];

                const colors = [
                    "rgba(255, 99, 71, 0.7)", // Tomato
                    "rgba(60, 179, 113, 0.7)", // Medium Sea Green
                    "rgba(30, 144, 255, 0.7)", // Dodger Blue
                    "rgba(255, 165, 0, 0.7)" // Orange
                ];

                const traces = [];
                const layout = {
                    title: `<span style="font-size: 32px;">${songName}</span><br><span style="font-size: 18px;">${playerName}</span><br><span style="font-size: 16px;">${dateTime}</span><br><span style="font-size: 14px;">${modifiers}</span>`,
                    titlefont: {
                        size: 24
                    },
                    grid: {
                        rows: 4,
                        columns: 2,
                        pattern: "independent"
                    },
                    showlegend: true,
                    legend: {
                        x: 0.5,
                        y: 0,
                        xanchor: "center",
                        yanchor: "top",
                        orientation: "h"
                    },
                    height: 1800,
                    width: 1200,
                    margin: {
                        l: 50,
                        r: 50,
                        b: 50,
                        t: 300,
                        pad: 4
                    },
                    annotations: []
                };

                plotData.forEach((plot, index) => {
                    const row = index + 1;

                    // Scatter plot trace (left side)
                    traces.push({
                        x: plot.data.xValues,
                        y: plot.data.yValues,
                        mode: "markers",
                        type: "scatter",
                        name: plot.title,
                        marker: {
                            color: colors[index]
                        },
                        xaxis: `x${index + 1}`,
                        yaxis: `y${index + 1}`,
                        showlegend: false
                    });

                    // Histogram trace (right side)
                    const histogramTrace = {
                        x: plot.data.yValues,
                        type: "histogram",
                        name: `${plot.title} Distribution`,
                        marker: {
                            color: "rgba(100, 100, 100, 1.0)"
                        },
                        xaxis: `x${index + 5}`,
                        yaxis: `y${index + 5}`,
                        nbinsx: 50,
                        xbins: {
                            start: 0,
                            end: 1.25,
                            size: 0.025
                        },
                        opacity: 0.6,
                        showlegend: false
                    };

                    traces.push(histogramTrace);

                    // Calculate maximum y value for the histogram
                    const histogramData = plot.data.yValues;
                    const histogramCounts = new Array(50).fill(0);
                    histogramData.forEach(value => {
                        const binIndex = Math.min(Math.floor((value / 1.25) * 50), 49);
                        histogramCounts[binIndex]++;
                    });
                    const maxHistogramY = Math.max(...histogramCounts);

                    // Mean and median lines for histograms
                    const meanValue = plot.data.yValues.reduce((a, b) => a + b, 0) / plot.data.yValues.length;
                    const sortedValues = plot.data.yValues.slice().sort((a, b) => a - b);
                    const mid = Math.floor(sortedValues.length / 2);
                    const medianValue = sortedValues.length % 2 !== 0 ? sortedValues[mid] : (sortedValues[mid - 1] + sortedValues[mid]) / 2;

                    // Define x and y axes for scatter plots (left)
                    layout[`xaxis${index + 1}`] = { title: "Time (ms)", domain: [0, 0.45]};
                    layout[`yaxis${index + 1}`] = { title: "|ΔError/ΔTime|", domain: [(4 - row) * 0.25 + 0.05, (5 - row) * 0.25], range: [0, 1.25]};

                    // Define x and y axes for histograms (right)
                    layout[`xaxis${index + 5}`] = { title: "|ΔError/ΔTime|", domain: [0.55, 1], range: [0, 1.25]};
                    layout[`yaxis${index + 5}`] = { title: "Count", domain: [(4 - row) * 0.25 + 0.05, (5 - row) * 0.25], range: [0, maxHistogramY] };

                    // Adding mean and median lines with legend
                    if (index === 0) {  // Add legend only for the first set of mean/median lines
                        traces.push({
                            x: [meanValue, meanValue],
                            y: [0, maxHistogramY],
                            mode: "lines",
                            name: "Mean",
                            line: {
                                dash: "dash",
                                width: 2,
                                color: "red"
                            },
                            xaxis: `x${index + 5}`,
                            yaxis: `y${index + 5}`,
                            showlegend: true
                        });

                        traces.push({
                            x: [medianValue, medianValue],
                            y: [0, maxHistogramY],
                            mode: "lines",
                            name: "Median",
                            line: {
                                dash: "dot",
                                width: 2,
                                color: "blue"
                            },
                            xaxis: `x${index + 5}`,
                            yaxis: `y${index + 5}`,
                            showlegend: true
                        });
                    } else {  // No legend for subsequent mean/median lines
                        traces.push({
                            x: [meanValue, meanValue],
                            y: [0, maxHistogramY],
                            mode: "lines",
                            name: "Mean",
                            line: {
                                dash: "dash",
                                width: 2,
                                color: "red"
                            },
                            xaxis: `x${index + 5}`,
                            yaxis: `y${index + 5}`,
                            showlegend: false
                        });

                        traces.push({
                            x: [medianValue, medianValue],
                            y: [0, maxHistogramY],
                            mode: "lines",
                            name: "Median",
                            line: {
                                dash: "dot",
                                width: 2,
                                color: "blue"
                            },
                            xaxis: `x${index + 5}`,
                            yaxis: `y${index + 5}`,
                            showlegend: false
                        });
                    }

                    // Add title annotations to each scatter plot
                    layout.annotations.push({
                        x: 0.025,
                        y: 1 - (index * 0.255) + 0.001,
                        xref: "paper",
                        yref: "paper",
                        text: plot.title,
                        showarrow: false,
                        font: {
                            size: 14,
                            color: "black"
                        }
                    });
                });

                let plotDiv = document.getElementById("combinedPlot");
                if (plotDiv) {
                    plotDiv.remove();  // Remove existing plot div if it exists
                }

                plotDiv = document.createElement("div");
                plotDiv.id = "combinedPlot";
                plotDiv.style.width = "100%";
                plotDiv.style.height = "1800px";
                document.querySelector(".score-details").appendChild(plotDiv);

                Plotly.newPlot("combinedPlot", traces, layout);
            });
        });
    };

    if (scorePagePattern.test(window.location.href)) {
        initializePlot();
    }

    window.navigation.addEventListener("navigate", event => {
        if (scorePagePattern.test(event.destination.url)) {
            initializePlot();
        }
    });
})();
