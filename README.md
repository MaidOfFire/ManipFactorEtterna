# ManipFactor Etterna
An Etterna addon that estimates the amount of manip based on replay data, introducing a new metric for play accuracy. Offers both an In-Game version and a browser-based version for EtternaOnline.

Follow the instructions below for installation:

## In-Game Installation:
### Til Death:
1. Move `manipfactor.lua` to the following directory inside your Etterna game folder:
> Themes\Til Death\BGAnimations\ScreenEvaluation decorations
2. Open `default.lua` from the same folder and **before** the line:
```
return t
```
add the following line:
```
t[#t + 1] = LoadActor("manipfactor")
```

3. Open `scoreboard.lua` from the same folder and **after the second occurrence** of the line:
```
self:GetParent():GetParent():GetParent():GetChild("OffsetPlot"):playcommand("SetFromScore", {score =  hsTable[index]})
```
add the following line:
```
MESSAGEMAN:Broadcast("GetScore", {score = hsTable[index]})
```
as on the figure:

![](https://i.imgur.com/fJyWtYi.png)

![](https://i.imgur.com/nkgtlSO.png)

### Rebirth:
1. Move `manipfactor.lua` to the following directory inside your Etterna game folder:
>Themes\Rebirth\BGAnimations\ScreenEvaluation decorations
2. open `mainDisplay.lua` from the same folder and **before** the line:
```
return t
```
add the following line:
```
t[#t + 1] = LoadActor("manipfactor")
```

3. In the same file, find the block of code that starts with:
```
JudgeWindowChangedMessageCommand = function(self)
```
and above the `end,` line, add the following line:
```
MESSAGEMAN:Broadcast("GetScore", {score = params.score})
```
as on the figure:
![](https://i.imgur.com/Wb4Qk6i.png)

![](https://i.imgur.com/Ym6Ajnm.png)

---

## EtternaOnline Installation:
1. Install the [Tampermonkey](https://www.tampermonkey.net/) browser extension.
2. Copy the script from this repository: [manipfactor.etternaonline.js](https://raw.githubusercontent.com/MaidOfFire/ManipFactorEtterna/main/manipfactor.etternaonline.js).
3. Paste the script to Tampermonkey:
   * Click on the Tampermonkey icon in your browser's toolbar.
   * Click the + icon or select "Create a new script" to open a new script editor.
   * Paste the copied script into the editor and save it.

![](https://i.imgur.com/8zgsVxT.png)

---

## How it Works:
The number **Manip Factor** (or MF) gets bigger the more a player hits one-hand misaligned notes (like trills or streams), as if they were a single aligned pattern (like jumps). The assumption is that when a player abuses this kind of playstyle, the hit errors (offsets) for consecutive different columns notes will be negatively correlated—meaning if one note is hit late, the next one tends to be hit early, making the difference between the errors larger than if the notes were hit as expected.

To measure the degree of such abuse from the replay data, we collect pairs of all misaligned one-hand notes and calculate the difference between their error values: |error_B - error_A|. Then we normalize this by using half the average time interval between notes on a single column and average the number across all pairs. The bigger the final number gets the more the player's technique leans toward manip play. 



