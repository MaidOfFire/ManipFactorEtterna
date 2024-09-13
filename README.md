# ManipFactorEtterna
## In-Game Installation:
### Til Death:
1. Move `manipfactor.lua` to:
> Themes\Til Death\BGAnimations\ScreenEvaluation decorations
2. Open `default.lua` from the same folder and add:
```
t[#t + 1] = LoadActor("manipfactor")
```
right before:
```
return t
```
3. Open `scoreboard.lua` from the same folder and add:
```
MESSAGEMAN:Broadcast("GetScore", {score = hsTable[index]})
```
after the second occurrence of:
```
self:GetParent():GetParent():GetParent():GetChild("OffsetPlot"):playcommand("SetFromScore", {score =  hsTable[index]})
```

![](https://i.imgur.com/fJyWtYi.png)

### Rebirth:
1. Move `manipfactor.lua` to:
>Themes\Rebirth\BGAnimations\ScreenEvaluation decorations
2. open `mainDisplay.lua` from the same folder and add:
```
t[#t + 1] = LoadActor("manipfactor")
```
right before:
```
return t
```
3. In the same file, find the line:
```
JudgeWindowChangedMessageCommand = function(self)
```
and add the following line above `end,`:
```
MESSAGEMAN:Broadcast("GetScore", {score = params.score})
```

![](https://i.imgur.com/PWOHL84.png)

## EtternaOnline Installation:
1. Install the [Tampermonkey](https://www.tampermonkey.net/) browser extension.
2. Copy the script from this repository: [manipfactor.etternaonline.js](https://raw.githubusercontent.com/MaidOfFire/ManipFactorEtterna/main/manipfactor.etternaonline.js).
3. Paste the script to Tampermonkey:
   * Click on the Tampermonkey icon in your browser's toolbar.
   * Click the + icon or select "Create a new script" to open a new script editor.
   * Paste the copied script into the editor and save it.

![](https://i.imgur.com/8zgsVxT.png)

## How it Works:
