--
-- BunkerSilosHud
--
-- @description:	A hud that shows the contents of all silos (BGA and cow), including the distribution inside each silo, plus the fill levels of all liquid manure tanks and some BGA data.
-- @author:			Jakob Tischler
-- @project start:	13 Jan 2014
-- @date:			26 Jan 2015
-- @version:		2.1
-- @history:		0.98 (25 Feb 2014): * initial release
-- 					0.99 (02 Mar 2014): * add safety check against impromperly created BunkerSilo triggers (w/o movingPlanes) - you know who you are!
--										* add warning sign if silo is fully fermented but the cover plane hasn't been removed yet
--										* fix scrolling functionality/zooming inhibit for vehicles with 'InteractiveControl' spec
--					2.0  (14 Jan 2015): * conversion to FS15
--										* GUI update
--										* add BGA data (especially BGAextension): bunker fill level, bunker/fermenter dry matter, current and historic generator power
--										* add MP/DS support
--					2.1  (26 Jan 2015): * add support for manure heaps
--										* add distinction between pigs and cattle
--										* hud is now draggable via drag+drop
-- @contact:		jakobgithub -ätt- gmail -dot- com
-- @note:			Modification, upload, distribution or any other change without the author's written permission is not allowed.
-- @thanks:			Peter van der Veen and Claus G. Pedersen, for testing the English version
--					upsidedown, for the camera movement function and general testing
--					upsidedown and mor2000 for multiplayer testing
--
-- Copyright (C) 2014-2015 Jakob Tischler
-- 

--[[
TODO:
1) how to render the effects overlay OVER the rendered text (z-index)? As of right now, the text, even though rendered before, is still rendered above the effects overlay.
2) fix BGA bonus base text width when bonusFillLevel > bonusCapacity bug in BGAextension is fixed
3) setTool(nil) doesn't really work / only works sporadically
]]

-- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

local abs, ceil, floor, max, min, pow = math.abs, math.ceil, math.floor, math.max, math.min, math.pow;
local function round(n, precision)
	if precision and precision > 0 then
		return floor((n * pow(10, precision)) + 0.5) / pow(10, precision);
	end;
	return floor(n + 0.5);
end;

local targetAspectRatio = 16/9; -- = 1920/1080;
local aspectRatioRatio = g_screenAspectRatio / targetAspectRatio;
local sizeRatio = 1;
if g_screenWidth > 1920 then
	sizeRatio = 1920 / g_screenWidth;
elseif g_screenWidth < 1920 then
	sizeRatio = max((1920 / g_screenWidth) * .75, 1);
end;

local function getFullPx(n, dimension)
	if dimension == 'x' then
		return round(n * g_screenWidth) / g_screenWidth;
	else
		return round(n * g_screenHeight) / g_screenHeight;
	end;
end;

-- px are in targetSize for 1920x1080
local function pxToNormal(px, dimension, fullPixel)
	local ret;
	if dimension == 'x' then
		ret = (px / 1920) * sizeRatio;
	else
		ret = (px / 1080) * sizeRatio * aspectRatioRatio;
	end;
	if fullPixel == nil or fullPixel then
		ret = getFullPx(ret, dimension);
	end;

	return ret;
end;

local function getPxToNormalConstant(widthPx, heightPx)
	return widthPx/g_screenWidth, heightPx/g_screenHeight;
end;

-- #-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#-#

BunkerSilosHud = {
	modDir = g_currentModDirectory;
	modName = g_currentModName;
	imgDir = g_currentModDirectory .. 'res/';
	saveAndLoadFunctionsOverwritten = false;
	hasMouseCursorActive = false;
	canScroll = false;

	HUDSTATE_INTERACTIVE = 1;
	HUDSTATE_ACTIVE = 2;
	HUDSTATE_CLOSED = 3;

	TOPSECTION_SILOS = 1;
	TOPSECTION_BGA = 2;

	version = '0.0';
	author = 'Jakob Tischler';
};
local modItem = ModsUtil.findModItemByModName(BunkerSilosHud.modName);
if modItem and modItem.version and modItem.author then
	BunkerSilosHud.version, BunkerSilosHud.author = modItem.version, modItem.author;
end;
addModEventListener(BunkerSilosHud);

function BunkerSilosHud:loadMap(name)
	if self.initialized then
		return;
	end;

	self.debugActive = false; -- #####

	self.complexBgaInstalled = getfenv(0)['ZZZ_complexBGA'] ~= nil;
	self:debug('complexBgaInstalled=' .. tostring(self.complexBgaInstalled));

	if not BunkerSilosHud.saveAndLoadFunctionsOverwritten then
		self:setSaveAndLoadFunctions();
	end;

	self.inputModifier = self:getKeyIdOfModifier(InputBinding.BUNKERSILOS_HUD);
	self.helpButtonText = g_i18n:getText('BUNKERSILOS_SHOWHUD');

	local langNumData = {
		br = { '.', ',' },
		cz = { ' ', ',' },
		de = { "'", ',' },
		en = { ',', '.' },
		es = { '.', ',' },
		fr = { ' ', ',' },
		it = { '.', ',' },
		jp = { ',', '.' },
		pl = { ' ', ',' },
		ru = { ' ', ',' }
	};
	self.numberSeparator = '\'';
	self.numberDecimalSeparator = '.';
	if g_languageShort and langNumData[g_languageShort] then
		self.numberSeparator        = langNumData[g_languageShort][1];
		self.numberDecimalSeparator = langNumData[g_languageShort][2];
	end;

	self.gui = {
		hudState = BunkerSilosHud.HUDSTATE_CLOSED;

		width  = pxToNormal(500, 'x');
		height = pxToNormal(244, 'y');

		hPadding = pxToNormal(25, 'x');

		fontSizeTitle = pxToNormal(16, 'y');
		fontSize = pxToNormal(14, 'y');
		fontSizeSmall = pxToNormal(12, 'y');
		fontSizeTiny = pxToNormal(10, 'y');

		buttonGfxWidth  = pxToNormal(16, 'x');
		buttonGfxHeight = pxToNormal(16, 'y');
	};

	local horizontalMargin = pxToNormal(16, 'x');
	self.gui.x1 = getFullPx(1 - self.gui.width - horizontalMargin, 'x');
	self.gui.y1 = pxToNormal(390, 'y');

	self.gui.boxAreaWidth = self.gui.width - (2 * self.gui.hPadding);
	self.gui.boxMargin = pxToNormal(3, 'x');
	self.gui.boxMaxHeight = pxToNormal(44, 'y');

	self.gui.colors = {
		default 			= self:rgba( 33, 48, 24, 1.0),
		defaultHover		= self:rgba( 33, 48, 24, 2/3),
		defaultTransparent	= self:rgba( 33, 48, 24, 0.5),
		clicked 			= self:rgba( 33, 48, 24, 1/3),
		defaultNonCompacted	= self:rgba( 33, 48, 24, 0.5),
		text 				= self:rgba(  0,  5,  0, 1.0),
		rotten 				= self:rgba( 73, 47, 42, 1.0),
		rottenNonCompacted	= self:rgba( 73, 47, 42, 0.5),
		barSpecial			= self:rgba(200, 10, 10, 1.0)
	};


	-- fill bar graph
	self.gui.barHeight = pxToNormal(14, 'y');
	self.gui.barBorderWidth = pxToNormal(4, 'x');

	local imgPath = 'dataS2/menu/white.png';
	self.barOverlayId = createImageOverlay(imgPath);
	self.barSpecialOverlayId = createImageOverlay(imgPath);
	self.barBgOverlayId = createImageOverlay(imgPath);
	self:setOverlayIdColor(self.barOverlayId, 'barColor', 'default');
	self:setOverlayIdColor(self.barSpecialOverlayId, 'barSpecialColor', 'barSpecial');
	self:setOverlayIdColor(self.barBgOverlayId, 'barBgColor', 'defaultTransparent');


	self.gui.iconFilePath = Utils.getFilename('bshIcons.png', BunkerSilosHud.imgDir);
	self.gui.iconFileSize = { 16, 128 };
	self.gui.iconUVs = {
		arrowLeft		= { 0, 48, 16,32 },
		arrowRight		= { 0, 32, 16,16 },
		closeHud		= { 0, 16, 16, 0 },
		mouse			= { 0, 64, 16,48 },
		warning			= { 0, 80, 16,64 },
		radioDeselected = { 0, 96, 16,80 },
		radioSelected	= { 0,112, 16,96 }
	};

	local gfxPath = Utils.getFilename('bshHud.png', BunkerSilosHud.imgDir);
	self.gui.background = Overlay:new('bshBackground', gfxPath, 0, 0, self.gui.width, self.gui.height);
	self.gui.effects =    Overlay:new('bshFx',		   gfxPath, 0, 0, self.gui.width, self.gui.height);
	self:setOverlayUVsPx(self.gui.background, { 6,250, 506,  6 }, 512,512);
	self:setOverlayUVsPx(self.gui.effects,    { 6,506, 506,262 }, 512,512);

	self.gui.buttons = {};

	-- mouse wheel icon
	self.gui.mouseWheel = Overlay:new('bshMouse', self.gui.iconFilePath, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
	self:setOverlayUVsPx(self.gui.mouseWheel, self.gui.iconUVs.mouse, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);

	-- warning icon
	self.gui.warning = Overlay:new('bshWarning', self.gui.iconFilePath, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
	self:setOverlayUVsPx(self.gui.warning, self.gui.iconUVs.warning, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);
	self.displayWarning = false;
	self.blinkLength = 500; -- in ms

	-- close button
	self.gui.closeHudButton = BshButton:new('closeHud', 'setHudState', BunkerSilosHud.HUDSTATE_CLOSED, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);

	-- ################################################################################

	self.bunkerStates = {
		[0] = g_i18n:getText('BUNKERSILOS_STATE_0'), -- to be filled
		[1] = g_i18n:getText('BUNKERSILOS_STATE_1'), -- fermentation
		[2] = g_i18n:getText('BUNKERSILOS_STATE_2')  -- done/silage
	};

	local ce = g_currentMission.missionInfo.customEnvironment;
	if ce and _G[ce] and _G[ce].g_i18n and _G[ce].g_i18n.getText then
		self.mapI18n = _G[ce].g_i18n;
	end;
	self:debug(('ce=%q, mapI18n=%s'):format(tostring(ce), tostring(self.mapI18n)));

	self.bgas = {};
	self.bgaToBshData = {};

	self.silos = {};
	self.tempSiloTriggers = {};
	self.siloTriggerIdToIdx = {};

	self.tanks = {};
	self.tanksIdentifiedById = {};

	local bgaIdx = 0;
	local bunkerSiloIdx = 0;
	local liquidManureIdx = 0;
	local manureIdx = 0;

	for k,v in pairs(g_currentMission.tipTriggers) do
		if g_currentMission.tipTriggers[k] ~= nil then
			local t = g_currentMission.tipTriggers[k];

			-- Silos
			if t.bunkerSilo ~= nil and t.bunkerSilo.movingPlanes ~= nil then
				bunkerSiloIdx = bunkerSiloIdx + 1;
				self.tempSiloTriggers[bunkerSiloIdx] = v;

				local siloTable = {
					bunkerSiloIdx = bunkerSiloIdx;
					bunkerSiloNum = bunkerSiloIdx;
					triggerId = t.triggerId;
					state = t.bunkerSilo.state;
					stateText = self.bunkerStates[tonumber(t.bunkerSilo.state)];
					-- fillLevel = t.bunkerSilo.fillLevel;
					-- fillLevelFormatted = self:formatNumber(t.bunkerSilo.fillLevel, 0);
					-- fillLevelPct = 0;
					-- fillLevelPctFormatted = '0';
					capacity = t.bunkerSilo.capacity;
					capacityFormatted = self:formatNumber(t.bunkerSilo.capacity, 0);
					-- toFillFormatted = '0';
					-- compactedFillLevel = t.bunkerSilo.compactedFillLevel;
					-- compactPct = 0;
					-- compactPctFormatted = '0';
					fermentingTime = t.bunkerSilo.fermentingTime;
					fermentingDuration = t.bunkerSilo.fermentingDuration;
					fermentationPct = 0;
					fermentationPctFormatted = '0';
					movingPlanesNum = #t.bunkerSilo.movingPlanes;
					movingPlanes = {};
					rottenFillLevel = 0;
					rottenFillLevelPctFormatted = '0';
				};
				siloTable.boxWidth = (self.gui.boxAreaWidth - (siloTable.movingPlanesNum-1)*self.gui.boxMargin) / siloTable.movingPlanesNum;

				for i=1, siloTable.movingPlanesNum do
					local movingPlane = {};
					movingPlane.boxX = 0;
					movingPlane.boxCenterX = movingPlane.boxX + siloTable.boxWidth * 0.5;

					table.insert(siloTable.movingPlanes, movingPlane);
				end;

				local name = getUserAttribute(t.triggerId, 'bshName');
				if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
					siloTable.name = self.mapI18n:getText('BSH_' .. name);
					t.bshName = siloTable.name;
					t.bunkerSilo.bshName = siloTable.name;
				else
					siloTable.name = ('%s %.2d'):format(g_i18n:getText('BUNKERSILOS_SILO'), bunkerSiloIdx);
				end;

				table.insert(self.silos, siloTable);
				self.siloTriggerIdToIdx[t.triggerId] = bunkerSiloIdx;

				self:debug(('add silo %d (triggerId %s, #movingPlanes=%d, name %q) / total: %d'):format(bunkerSiloIdx, tostring(t.triggerId), siloTable.movingPlanesNum, tostring(siloTable.name), #self.silos));
			end;
		end;
	end; --END for

	for i,onCreateObject in pairs(g_currentMission.onCreateLoadedObjects) do
		-- BGAs
		if onCreateObject.isa and onCreateObject:isa(Bga) then
			bgaIdx = bgaIdx + 1;
			local bgaTable = {
				bgaIdx = bgaIdx;
				bgaNum = bgaIdx;
				onCreateIndex = i;
				isBga = true;
				nodeId = onCreateObject.nodeId;
				name = ('%s %.2d'):format(g_i18n:getText('BUNKERSILOS_BGA'), bgaIdx);
			};

			-- BGA extension (complexBGA, upsidedown)
			if onCreateObject.fermenter_TS_clog then
				self:debug('    isComplexBga = true');
				bgaTable.isComplexBga = true;
				bgaTable.tsGraphNumValues = 48; -- 48 hours -- prev: 1 point per hour, 5 days
				local posX, posY = 0, 0;
				local width = self.gui.boxAreaWidth * ((bgaTable.tsGraphNumValues - 1) / bgaTable.tsGraphNumValues);
				local height = self.gui.boxMaxHeight;
				local minValue, maxValue = 0, 500;
				local showGraphLabels, labelExtraText = false, '';
				bgaTable.tsGraph = Graph:new(bgaTable.tsGraphNumValues, posX, posY, width, height, minValue, maxValue, showGraphLabels, labelExtraText);
				bgaTable.tsGraph:setColor(unpack(self.gui.colors.default));

				bgaTable.powerHistory = {};

				if not self.hourChangeListenerAdded then
					g_currentMission.environment:addHourChangeListener(self);
					self.hourChangeListenerAdded = true;
					self.updateBgaPowerHistoryOnce = true;
				end;
			end;

			local name = getUserAttribute(onCreateObject.nodeId, 'bshName');
			if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
				bgaTable.name = self.mapI18n:getText('BSH_' .. name);
			end;

			self.bgas[#self.bgas + 1] = bgaTable;

			-- reference history directly in BGA so it can be saved to the xml
			onCreateObject.bshPowerHistory = self.bgas[#self.bgas].powerHistory;
			self.bgaToBshData[onCreateObject] = self.bgas[#self.bgas];

			self:debug(('add BGA %d (onCreateIndex %d, name %q) / total: %d'):format(bgaIdx, i, tostring(bgaTable.name), #self.bgas));

			-- #####

			-- BGA liquid manure tank(s)
			if onCreateObject.liquidManureSiloTrigger ~= nil then
				local trigger = onCreateObject.liquidManureSiloTrigger;
				local triggerId = trigger.triggerId;
				if not self.tanksIdentifiedById[triggerId] then
					liquidManureIdx = liquidManureIdx + 1;

					local tankTable = {
						tankNum = liquidManureIdx;
						onCreateIndex = i;
						triggerId = triggerId;
						isBGA = true;
						fillLevel = trigger.fillLevel;
						fillLevelFormatted = '0';
						fillLevelPct = 0;
						fillLevelPctFormatted = '0';
						capacity = trigger.capacity;
						capacityFormatted = self:formatNumber(trigger.capacity, 0);
						name = ('%s %.2d (%s)'):format(g_i18n:getText('BUNKERSILOS_TANK'), liquidManureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_BGA'));
					};

					local name = getUserAttribute(triggerId, 'bshName');
					if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
						tankTable.name = self.mapI18n:getText('BSH_' .. name);
						trigger.bshName = tankTable.name;
					end;
					tankTable.fillLevelTxtPosX = 0;

					table.insert(self.tanks, tankTable);
					self.tanksIdentifiedById[triggerId] = true;
					self:debug(('add LiquidManureTank %d (triggerId %s, name %q) [BGA] / total: %d'):format(liquidManureIdx, tostring(triggerId), tostring(tankTable.name), #self.tanks));
				end;
			end;


		-- AnimalHusbandry [cows]
		elseif onCreateObject.isa and onCreateObject:isa(AnimalHusbandry) then
			-- liquid manure tank
			if onCreateObject.liquidManureTrigger ~= nil then
				local trigger = onCreateObject.liquidManureTrigger;
				local triggerId = trigger.triggerId;
				if not self.tanksIdentifiedById[triggerId] then
					liquidManureIdx = liquidManureIdx + 1;
					local tankTable = {
						tipTriggersIdx = k;
						tankNum = liquidManureIdx;
						onCreateIndex = i;
						triggerId = triggerId;
						isCowsLiquidManure = true;
						fillLevel = trigger.fillLevel;
						fillLevelFormatted = '0';
						fillLevelPct = 0;
						fillLevelPctFormatted = '0';
						capacity = trigger.capacity;
						capacityFormatted = self:formatNumber(trigger.capacity, 0);
						name = ('%s %.2d (%s)'):format(g_i18n:getText('BUNKERSILOS_TANK'), liquidManureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_COWS'));
					};

					local name = getUserAttribute(triggerId, 'bshName');
					if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
						tankTable.name = self.mapI18n:getText('BSH_' .. name);
					end;
					tankTable.fillLevelTxtPosX = 0;

					table.insert(self.tanks, tankTable);
					self.tanksIdentifiedById[triggerId] = true;
					self:debug(('add LiquidManureTank %d (triggerId %s, name %q) [cows] / total: %d'):format(liquidManureIdx, tostring(triggerId), tostring(tankTable.name), #self.tanks));
				end;
			end;

			-- manure heap
			if onCreateObject.manureHeap ~= nil then
				local trigger = onCreateObject.manureHeap;
				local triggerId = trigger.triggerId;
				if not self.tanksIdentifiedById[triggerId] and trigger.capacity then
					manureIdx = manureIdx + 1;
					local tankTable = {
						tipTriggersIdx = k;
						tankNum = manureIdx;
						onCreateIndex = i;
						triggerId = triggerId;
						isCowsManure = true;
						fillLevel = trigger.fillLevel;
						fillLevelFormatted = '0';
						fillLevelPct = 0;
						fillLevelPctFormatted = '0';
						capacity = trigger.capacity;
						capacityFormatted = self:formatNumber(trigger.capacity, 0);
						name = ('%s %.2d (%s)'):format(g_i18n:getText('Manure_storage'), manureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_COWS'));
					};

					local name = getUserAttribute(triggerId, 'bshName');
					if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
						tankTable.name = self.mapI18n:getText('BSH_' .. name);
					end;
					tankTable.fillLevelTxtPosX = 0;

					table.insert(self.tanks, tankTable);
					self.tanksIdentifiedById[triggerId] = true;
					self:debug(('add ManureHeap %d (triggerId %s, name %q) [cows] / total: %d'):format(manureIdx, tostring(triggerId), tostring(tankTable.name), #self.tanks));
				end;
			end;


		-- ManureLager tanks
		elseif onCreateObject.ManureLagerDirtyFlag ~= nil or Utils.endsWith(onCreateObject.className, 'ManureLager') then
			local triggerId = onCreateObject.triggerId;
			if not self.tanksIdentifiedById[triggerId] then
				liquidManureIdx = liquidManureIdx + 1;
				local tankTable = {
					tankNum = liquidManureIdx;
					onCreateIndex = i;
					isManureLager = true;
					fillLevel = onCreateObject.fillLevel;
					fillLevelFormatted = '0';
					fillLevelPct = 0;
					fillLevelPctFormatted = '0';
					capacity = onCreateObject.capacity;
					capacityFormatted = self:formatNumber(onCreateObject.capacity, 0);
					name = ('%s %.2d (%s)'):format(g_i18n:getText('BUNKERSILOS_TANK'), liquidManureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_MANURESTORAGE'));
				};

				local name = getUserAttribute(triggerId, 'bshName');
				if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
					tankTable.name = self.mapI18n:getText('BSH_' .. name);
					onCreateObject.bshName = tankTable.name;
				end;
				tankTable.fillLevelTxtPosX = 0;

				self.tanks[#self.tanks + 1] = tankTable;
				self.tanksIdentifiedById[triggerId] = true;
				self:debug(('add LiquidManureTank %d (triggerId %s, name %q) [ManureLager] / total: %d'):format(liquidManureIdx, tostring(triggerId), tostring(tankTable.name), #self.tanks));
			end;


		-- Pigs/cattle [Schweinemast by marhu]
		elseif onCreateObject.SchweineZuchtDirtyFlag and onCreateObject.numSchweine ~= nil then
			-- liquid manure tank
			if onCreateObject.liquidManureSiloTrigger ~= nil then
				local trigger = onCreateObject.liquidManureSiloTrigger;
				local triggerId = trigger.triggerId;
				if triggerId and not self.tanksIdentifiedById[triggerId] then
					liquidManureIdx = liquidManureIdx + 1;
					local tankTable = {
						tankNum = liquidManureIdx;
						onCreateIndex = i;
						isPigsLiquidManure = true;
						fillLevel = trigger.fillLevel;
						fillLevelFormatted = '0';
						fillLevelPct = 0;
						fillLevelPctFormatted = '0';
						capacity = trigger.capacity;
						capacityFormatted = self:formatNumber(trigger.capacity, 0);
					};

					local animalType = 'pigs';
					local name = getUserAttribute(triggerId, 'bshName');
					if name ~= nil and self.mapI18n and self.mapI18n:hasText('BSH_' .. name) then
						tankTable.name = self.mapI18n:getText('BSH_' .. name);
						onCreateObject.bshName = tankTable.name;
					else
						if onCreateObject.animal and onCreateObject.animal == 'beef' then
							animalType = 'cattle';
						end;
						if onCreateObject.StationNr then
							tankTable.name = ('%s (%s #%d)'):format(g_i18n:getText('BUNKERSILOS_TANK'), g_i18n:getText('BUNKERSILOS_TANKTYPE_' .. animalType:upper()), onCreateObject.StationNr);
						else
							tankTable.name = ('%s %.2d (%s)'):format(g_i18n:getText('BUNKERSILOS_TANK'), liquidManureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_' .. animalType:upper()));
						end;
					end;
					tankTable.fillLevelTxtPosX = 0;

					table.insert(self.tanks, tankTable);
					self.tanksIdentifiedById[triggerId] = true;
					self:debug(('add LiquidManureTank %d (triggerId %s, name %q) [%s] / total: %d'):format(liquidManureIdx, tostring(triggerId), tostring(tankTable.name), animalType, #self.tanks));
				end;
			end;

			-- manure heap [NOTE: SchweineZucht manure heap doesn't have a triggerId! -> no custom naming possible]
			if onCreateObject.manureHeap ~= nil then
				local trigger = onCreateObject.manureHeap;
				if trigger.capacity then
					manureIdx = manureIdx + 1;
					local tankTable = {
						tipTriggersIdx = k;
						tankNum = manureIdx;
						onCreateIndex = i;
						-- triggerId = triggerId;
						isPigsManure = true;
						fillLevel = trigger.FillLvl;
						fillLevelFormatted = '0';
						fillLevelPct = 0;
						fillLevelPctFormatted = '0';
						capacity = trigger.capacity;
						capacityFormatted = self:formatNumber(trigger.capacity, 0);
					};

					local animalType = 'pigs';
					if onCreateObject.animal and onCreateObject.animal == 'beef' then
						animalType = 'cattle';
					end;
					if onCreateObject.StationNr then
						tankTable.name = ('%s (%s #%d)'):format(g_i18n:getText('Manure_storage'), g_i18n:getText('BUNKERSILOS_TANKTYPE_' .. animalType:upper()), onCreateObject.StationNr);
					else
						tankTable.name = ('%s %.2d (%s)'):format(g_i18n:getText('Manure_storage'), manureIdx, g_i18n:getText('BUNKERSILOS_TANKTYPE_' .. animalType:upper()));
					end;
					tankTable.fillLevelTxtPosX = 0;

					table.insert(self.tanks, tankTable);
					-- self.tanksIdentifiedById[triggerId] = true;
					self:debug(('add ManureHeap %d (triggerId %s, name %q) [%s] / total: %d'):format(manureIdx, tostring(triggerId), tostring(tankTable.name), animalType, #self.tanks));
				end;
			end;
		end;
	end;

	--------------------------------------------------------------------------------------------------------------

	local function sortByName(a, b)
		return a.name:lower() < b.name:lower();
	end;

	-- SORT AND REINDEX
	-- BGAs
	self.numBgas = #self.bgas;
	if self.numBgas > 0 then
		self.activeBga = 1;
		if self.numBgas > 1 then
			table.sort(self.bgas, sortByName);
			for k,v in ipairs(self.bgas) do
				v.bgaNum = k;
			end;
			self.gui.changeBgaNegButton = BshButton:new('arrowLeft', 'changeBga', -1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
			self.gui.changeBgaPosButton = BshButton:new('arrowRight', 'changeBga', 1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
		end;
	else
		self.activeBga = false;
	end;

	-- silos
	self.numSilos = #self.silos;
	if self.numSilos > 0 then
		self.activeSilo = 1;

		local imgPath = 'dataS2/menu/white.png';
		self.movingPlanesOverlayId = createImageOverlay(imgPath);
		self.movingPlanesNonCompactedOverlayId = createImageOverlay(imgPath);
		self:setOverlayIdColor(self.movingPlanesOverlayId, 'movingPlanesColor', 'default');
		self:setOverlayIdColor(self.movingPlanesNonCompactedOverlayId, 'movingPlanesNonCompactedColor', 'defaultNonCompacted');


		if self.numSilos > 1 then
			table.sort(self.silos, sortByName);
			for k,v in ipairs(self.silos) do
				v.bunkerSiloNum = k;
			end;

			self.gui.changeSiloNegButton = BshButton:new('arrowLeft', 'changeSilo', -1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
			self.gui.changeSiloPosButton = BshButton:new('arrowRight', 'changeSilo', 1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
		end;
	else
		self.activeSilo = false;
	end;

	-- tanks
	self.numTanks = #self.tanks;
	if self.numTanks > 0 then
		self.activeTank = 1;

		if self.numTanks > 1 then
			table.sort(self.tanks, sortByName);
			for k,v in ipairs(self.tanks) do
				v.tankNum = k;
			end;

			self.gui.changeTankNegButton = BshButton:new('arrowLeft', 'changeTank', -1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
			self.gui.changeTankPosButton = BshButton:new('arrowRight', 'changeTank', 1, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight);
		end;
	else
		self.activeTank = false;
	end;


	-- TOP SECTION SELECTION
	-- BGA button
	local textWidth = getTextWidth(self.gui.fontSize, g_i18n:getText('BUNKERSILOS_BGA'));
	local buttonWidth = self.gui.buttonGfxWidth + textWidth;
	self.gui.topSectionButtonBga = BshButton:new('radioDeselected', 'setTopSection', BunkerSilosHud.TOPSECTION_BGA, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight, buttonWidth, self.gui.buttonGfxHeight);

	-- Silos button
	textWidth = getTextWidth(self.gui.fontSize, g_i18n:getText('BUNKERSILOS_SILOS'));
	buttonWidth = self.gui.buttonGfxWidth + textWidth;
	self.gui.topSectionButtonSilos = BshButton:new('radioSelected', 'setTopSection', BunkerSilosHud.TOPSECTION_SILOS, 0, 0, self.gui.buttonGfxWidth, self.gui.buttonGfxHeight, buttonWidth, self.gui.buttonGfxHeight);

	self:setTopSection(BunkerSilosHud.TOPSECTION_SILOS);


	-- ##### SET GRAPHICS POSITION
	self:setGuiPositions();

	-- stop vehicle/player camera movement if mouse active
	if not VehicleCamera.bshMouseInserted then
		VehicleCamera.mouseEvent = Utils.overwrittenFunction(VehicleCamera.mouseEvent, BunkerSilosHud.cancelMouseEvent);
		VehicleCamera.zoomSmoothly = Utils.overwrittenFunction(VehicleCamera.zoomSmoothly, BunkerSilosHud.cancelZoom);
		VehicleCamera.bshMouseInserted = true;
	end;
	if not Player.bshMouseInserted then
		Player.mouseEvent = Utils.overwrittenFunction(Player.mouseEvent, BunkerSilosHud.cancelMouseEvent);
		Player.bshMouseInserted = true;
	end;

	self.initialized = true;
	print(('## BunkerSilosHud v%s by %s loaded'):format(BunkerSilosHud.version, BunkerSilosHud.author));
end;

function BunkerSilosHud:setGuiPositions()
	self.gui.x2 = self.gui.x1 + self.gui.width;
	self.gui.y2 = self.gui.y1 + self.gui.height;

	self.gui.contentMinX = self.gui.x1 + self.gui.hPadding;
	self.gui.contentMaxX = self.gui.x1 + self.gui.width - self.gui.hPadding;
	self.gui.contentCenterX = self.gui.x1 + self.gui.width * 0.5;

	self.gui.upperLineY = self.gui.y1 + pxToNormal(210, 'y');

	self.gui.lines = {};
	-- Main title
	self.gui.lines[0] = self.gui.y1 + pxToNormal(212, 'y');
	-- Silos / BGA
	self.gui.lines[1] = self.gui.lines[0] - pxToNormal(22, 'y');
	self.gui.lines[2] = self.gui.lines[1] - pxToNormal(20, 'y');
	self.gui.lines[3] = self.gui.lines[2] - pxToNormal(20, 'y');
	self.gui.lines[4] = self.gui.lines[3] - pxToNormal(20, 'y');
	self.gui.lines[5] = self.gui.lines[4] - pxToNormal(20, 'y');
	self.gui.lines[6] = self.gui.y1 + pxToNormal(61, 'y');
	-- Liquid manure tanks
	self.gui.lines[7] = self.gui.y1 + pxToNormal(42, 'y');
	self.gui.lines[8] = self.gui.lines[7] - pxToNormal(20, 'y');

	self.gui.barBorderRightPosX = self.gui.contentMaxX - self.gui.barBorderWidth;
	self.gui.barMaxX = self.gui.contentMaxX - (self.gui.barBorderWidth * 2);

	-- Liquid manure tank bar graph
	self.gui.tankBarBorderLeftPosX = self.gui.contentMinX;
	self.gui.tankBarMinX = self.gui.tankBarBorderLeftPosX + (self.gui.barBorderWidth * 2);
	self.gui.tankBarMaxWidth = self.gui.barMaxX - self.gui.tankBarMinX;

	-- BGA bunker fill level bar graph
	local text = g_i18n:getText('BUNKERSILOS_BGA_BUNKERFILLLEVEL'):format('00,0', '00,0', '100,0');
	if self.complexBgaInstalled then
		self.gui.bgaBunkerFillLevelBarBorderLeftPosX, self.gui.bgaBunkerFillLevelBarMinX, self.gui.bgaBunkerFillLevelBarMaxWidth = self:getBarDimensionsFromPrecedingText(text);
	else
		self.gui.bgaBunkerFillLevelBarBorderLeftPosX, self.gui.bgaBunkerFillLevelBarMinX, self.gui.bgaBunkerFillLevelBarMaxWidth = self.gui.tankBarBorderLeftPosX, self.gui.tankBarMinX, self.gui.tankBarMaxWidth;
	end;

	-- BGA fermenter TS bar graph
	local text = g_i18n:getText('BUNKERSILOS_BGA_FERMENTERTS'):format('00,00');
	self.gui.bgaFermenterDrySubstanceBarBorderLeftPosX, self.gui.bgaFermenterDrySubstanceBarMinX, self.gui.bgaFermenterDrySubstanceBarMaxWidth = self:getBarDimensionsFromPrecedingText(text);
	local maxDS, optimumDS = 0.16, 0.1;
	local optimumRelativePct = optimumDS / maxDS;
	self.gui.bgaFermenterDrySubstanceBarOptimumPosX = self.gui.bgaFermenterDrySubstanceBarMinX + (self.gui.bgaFermenterDrySubstanceBarMaxWidth * optimumRelativePct) - (self.gui.barBorderWidth * 0.5);

	-- BGA bunker bonus fill level bar graph
	local text = ("%s: 100'000/100'000 %s (100.0%%)"):format(g_i18n:getText('BUNKERSILOS_BGA_BUNKERBONUS'), g_i18n:getText('fluid_unit_short'));
	self.gui.bgaBunkerBonusFillLevelBarBorderLeftPosX, self.gui.bgaBunkerBonusFillLevelBarMinX, self.gui.bgaBunkerBonusFillLevelBarMaxWidth = self:getBarDimensionsFromPrecedingText(text);


	self.gui.background:setPosition(self.gui.x1, self.gui.y1);
	self.gui.effects:setPosition(self.gui.x1, self.gui.y1);

	--							x1					  x2					y1				   y2
	self.gui.topSectionArea = { self.gui.contentMinX, self.gui.contentMaxX, self.gui.lines[6], self.gui.lines[1] + self.gui.buttonGfxHeight };
	self.gui.tankArea		= { self.gui.contentMinX, self.gui.contentMaxX, self.gui.lines[8], self.gui.lines[7] + self.gui.buttonGfxHeight };

	self.gui.topIconsPosX = {
		[1] = self.gui.contentMaxX - self.gui.buttonGfxWidth * 3.2;
		[2] = self.gui.contentMaxX - self.gui.buttonGfxWidth * 2.2;
		[3] = self.gui.contentMaxX - self.gui.buttonGfxWidth;
	};

	self.gui.mouseWheel:setPosition(self.gui.topIconsPosX[1], self.gui.upperLineY);
	self.gui.warning:setPosition(self.gui.topIconsPosX[2], self.gui.upperLineY);
	self.gui.closeHudButton:setPosition(self.gui.topIconsPosX[3], self.gui.upperLineY);

	-- set movingPlanes box position
	for _,silo in ipairs(self.silos) do
		for i,mp in ipairs(silo.movingPlanes) do
			mp.boxX = self.gui.contentMinX + (i-1)*(silo.boxWidth + self.gui.boxMargin);
			mp.boxCenterX = mp.boxX + silo.boxWidth * 0.5;
		end;
	end;

	-- set BGAs graph position
	for _,bga in ipairs(self.bgas) do
		if bga.tsGraph then
			bga.tsGraph.left = self.gui.contentMinX;
			bga.tsGraph.bottom = self.gui.lines[6];
		end;

		-- reinitialize fill level bars position calculation
		bga.bunkerCapacity = nil;
		bga.bonusCapacity = nil;
	end;

	-- set liquid manure tanks bar position
	for _,tank in ipairs(self.tanks) do
		tank.fillLevelTxtPosX = self.gui.contentMinX + getTextWidth(self.gui.fontSize, tank.name .. ':') + self.gui.buttonGfxWidth;
	end;

	-- set nav buttons position
	if self.numBgas > 1 then
		self.gui.changeBgaNegButton:setPosition(self.gui.contentMinX, self.gui.lines[1]);
		self.gui.changeBgaPosButton:setPosition(self.gui.contentMaxX - self.gui.buttonGfxWidth, self.gui.lines[1]);
	end;
	if self.numSilos > 1 then
		self.gui.changeSiloNegButton:setPosition(self.gui.contentMinX, self.gui.lines[1]);
		self.gui.changeSiloPosButton:setPosition(self.gui.contentMaxX - self.gui.buttonGfxWidth, self.gui.lines[1]);
	end;
	if self.numTanks > 1 then
		self.gui.changeTankNegButton:setPosition(self.gui.contentMinX, self.gui.lines[7]);
		self.gui.changeTankPosButton:setPosition(self.gui.contentMaxX - self.gui.buttonGfxWidth, self.gui.lines[7]);
	end;

	-- set top section selection buttons position
	local margin = self.gui.buttonGfxWidth;
	-- BGA button
	local textWidth = getTextWidth(self.gui.fontSize, g_i18n:getText('BUNKERSILOS_BGA'));
	self.gui.topSectionBgaTextX = self.gui.topIconsPosX[1] - margin - textWidth;
	local iconX = self.gui.topSectionBgaTextX - self.gui.buttonGfxWidth * 1.25;
	local buttonWidth = self.gui.buttonGfxWidth + textWidth;
	self.gui.topSectionButtonBga:setPosition(iconX, self.gui.upperLineY);

	-- Silos button
	textWidth = getTextWidth(self.gui.fontSize, g_i18n:getText('BUNKERSILOS_SILOS'));
	self.gui.topSectionSilosTextX = iconX - margin * 0.75 - textWidth;
	iconX = self.gui.topSectionSilosTextX - self.gui.buttonGfxWidth * 1.25;
	buttonWidth = self.gui.buttonGfxWidth + textWidth;
	self.gui.topSectionButtonSilos:setPosition(iconX, self.gui.upperLineY);
end;

function BunkerSilosHud:moveGui(dx, dy)
	if dx ~= 0 or dy ~= 0 then
		self.gui.x1 = getFullPx(Utils.clamp(self.gui.x1 + dx, 0, 1 - self.gui.width), 'x');
		self.gui.y1 = getFullPx(Utils.clamp(self.gui.y1 + dy, 0, 1 - self.gui.height), 'y');

		self:setGuiPositions();
	end;

	self.gui.background:setColor(1, 1, 1, 1);
	self.gui.background.hasDragDropColor = false;
	self.gui.background.origPos = nil;
	self.gui.dragDropMouseDown = nil;
end;

function BunkerSilosHud:dragDropUpdateBackground(dx, dy)
	if not self.gui.background.hasDragDropColor then
		self.gui.background:setColor(1, 0, 0, 0.6);
		self.gui.background.hasDragDropColor = true;
	end;
	self.gui.background:setPosition(self.gui.background.origPos[1] + dx, self.gui.background.origPos[2] + dy);
end;

function BunkerSilosHud:cancelMouseEvent(superFunc, posX, posY, isDown, isUp, button)
	if BunkerSilosHud.hasMouseCursorActive then
		local x, y = InputBinding.mouseMovementX, InputBinding.mouseMovementY;
		local origIsUp, origIsDown = isUp, isDown;

		InputBinding.mouseMovementX, InputBinding.mouseMovementY = 0, 0;
		isUp, isDown = false, false;

		superFunc(self, posX, posY, isDown, isUp, button);

		InputBinding.mouseMovementX, InputBinding.mouseMovementY = x, y;
		isUp, isDown = origIsUp, origIsDown;
	else
		superFunc(self, posX, posY, isDown, isUp, button);
	end;
end;
function BunkerSilosHud:cancelZoom(superFunc, offset)
	if BunkerSilosHud.hasMouseCursorActive and BunkerSilosHud.canScroll and (abs(offset) == 0.6 or abs(offset) == 0.75) then -- NOTE: make sure user zoomed with the mouse wheel: 0.6 (default), 0.75 (InteractiveControl)
		return;
	end;
	superFunc(self, offset);
end;

function BunkerSilosHud:deleteMap()
	-- delete overlays
	self:deleteOverlay(self.gui.background);
	self:deleteOverlay(self.gui.effects);
	self:deleteOverlay(self.gui.mouseWheel);
	self:deleteOverlay(self.gui.warning);

	-- delete overlayIds
	for _,o in ipairs( { 'movingPlanesOverlayId', 'movingPlanesNonCompactedOverlayId', 'barOverlayId', 'barSpecialOverlayId', 'barBgOverlayId' } ) do
		if self[o] then
			delete(self[o]);
		end;
	end;

	-- delete buttons
	for _,button in ipairs(self.gui.buttons) do
		button:delete();
	end;
	self.gui.buttons = {};

	-- delete BGA graphs
	for _,data in ipairs(self.bgas) do
		if data.tsGraph then
			data.tsGraph:delete();
		end;
		data.tsGraph = nil;
	end;

	-- delete current colors
	for _,c in ipairs({ 'barColor', 'barSpecialColor', 'barBgColor', 'movingPlanesColor', 'movingPlanesNonCompactedColor' }) do
		self[c] = nil;
	end;

	self.initialized = false;
end;

function BunkerSilosHud:setHudState(state, dontHideMouseCursor)
	self.gui.hudState = state;
	BunkerSilosHud.hasMouseCursorActive = state == BunkerSilosHud.HUDSTATE_INTERACTIVE;

	-- open
	if state == BunkerSilosHud.HUDSTATE_INTERACTIVE then
		InputBinding.setShowMouseCursor(true);
		self.helpButtonText = g_i18n:getText('BUNKERSILOS_HIDEMOUSE');

	-- hide mouse
	elseif state == BunkerSilosHud.HUDSTATE_ACTIVE then
		BunkerSilosHud.canScroll = false;
		InputBinding.setShowMouseCursor(false);
		self.helpButtonText = g_i18n:getText('BUNKERSILOS_HIDEHUD');

	-- close
	elseif state == BunkerSilosHud.HUDSTATE_CLOSED then
		for _,button in pairs(self.gui.buttons) do
			button.isClicked = false;
			button.isHovered = false;
		end;

		if not dontHideMouseCursor then
			InputBinding.setShowMouseCursor(false);
		end;
		BunkerSilosHud.canScroll = false;
		self.gui.warning.curBlinkTime = nil;
		self.helpButtonText = g_i18n:getText('BUNKERSILOS_SHOWHUD');
	end;
end;

function BunkerSilosHud:setTopSection(sectionRef)
	if self.gui.activeTopSection == sectionRef then return; end;

	self.gui.activeTopSection = sectionRef;
	local isSilosSection = sectionRef == BunkerSilosHud.TOPSECTION_SILOS;
	local isBgaSection = sectionRef == BunkerSilosHud.TOPSECTION_BGA;
	if isSilosSection then
		self:setOverlayUVsPx(self.gui.topSectionButtonBga.overlay, self.gui.iconUVs.radioDeselected, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);
		self:setOverlayUVsPx(self.gui.topSectionButtonSilos.overlay, self.gui.iconUVs.radioSelected, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);
	elseif isBgaSection then
		self:setOverlayUVsPx(self.gui.topSectionButtonBga.overlay, self.gui.iconUVs.radioSelected, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);
		self:setOverlayUVsPx(self.gui.topSectionButtonSilos.overlay, self.gui.iconUVs.radioDeselected, self.gui.iconFileSize[1], self.gui.iconFileSize[2]);
	end;

	if self.gui.changeSiloNegButton and self.gui.changeSiloPosButton then
		self.gui.changeSiloNegButton:setVisible(isSilosSection);
		self.gui.changeSiloPosButton:setVisible(isSilosSection);
	end;
	if self.gui.changeBgaNegButton and self.gui.changeBgaPosButton then
		self.gui.changeBgaNegButton:setVisible(isBgaSection);
		self.gui.changeBgaPosButton:setVisible(isBgaSection);
	end;
end;

function BunkerSilosHud:changeBga(move)
	self.activeBga = self:loopNumberSequence(self.activeBga + move, 1, self.numBgas);
end;

function BunkerSilosHud:changeSilo(move)
	self.activeSilo = self:loopNumberSequence(self.activeSilo + move, 1, self.numSilos);
end;

function BunkerSilosHud:changeTank(move)
	self.activeTank = self:loopNumberSequence(self.activeTank + move, 1, self.numTanks);
end;

function BunkerSilosHud:loopNumberSequence(n, minN, maxN)
	if n > maxN then
		return minN;
	elseif n < minN then
		return maxN;
	end;
	return n;
end;

function BunkerSilosHud:update(dt)
	if g_currentMission.paused or g_gui.currentGui ~= nil then return; end;

	if InputBinding.hasEvent(InputBinding.BUNKERSILOS_HUD) then
		self:setHudState(self:loopNumberSequence(self.gui.hudState + 1, BunkerSilosHud.HUDSTATE_INTERACTIVE, BunkerSilosHud.HUDSTATE_CLOSED));
	end;

	if g_currentMission.showHelpText and (self.inputModifier == nil or Input.isKeyPressed(self.inputModifier)) then
		g_currentMission:addHelpButtonText(self.helpButtonText, InputBinding.BUNKERSILOS_HUD);
	end;
end;

function BunkerSilosHud:draw()
	if self.gui.hudState == BunkerSilosHud.HUDSTATE_CLOSED or g_currentMission.paused or g_gui.currentGui ~= nil or g_currentMission.inGameMessage.currentMessage ~= nil then return; end;

	local g = self.gui;

	g.background:render();
	if g.dragDropMouseDown and g.background.hasDragDropColor then -- drag & drop -> only render background
		return;
	end;

	setTextColor(unpack(g.colors.text));
	setTextBold(true);
	renderText(g.contentMinX, g.lines[0], g.fontSizeTitle, g_i18n:getText('BUNKERSILOS_TITLE'));
	setTextBold(false);

	if BunkerSilosHud.canScroll then
		self.gui.mouseWheel:render();
	end;

	self.gui.topSectionButtonSilos:render();
	self.gui.topSectionButtonBga:render();

	-- BGA
	if self.gui.activeTopSection == BunkerSilosHud.TOPSECTION_BGA then
		renderText(g.topSectionSilosTextX, g.lines[0], g.fontSize, g_i18n:getText('BUNKERSILOS_SILOS'));
		setTextBold(true);
		renderText(g.topSectionBgaTextX, g.lines[0], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA'));
		setTextBold(false);

		if self.numBgas > 0 and self.activeBga then
			local data = self.bgas[self.activeBga];
			self:renderBgaData(data);
		else -- no BGAs
			setTextAlignment(RenderText.ALIGN_CENTER);
			renderText(g.contentCenterX, g.lines[2], g.fontSize, g_i18n:getText('BUNKERSILOS_NOBGAS'));
			setTextAlignment(RenderText.ALIGN_LEFT);
		end;


	--###########################################################################


	-- Silos
	elseif self.gui.activeTopSection == BunkerSilosHud.TOPSECTION_SILOS then
		setTextBold(true);
		renderText(g.topSectionSilosTextX, g.lines[0], g.fontSize, g_i18n:getText('BUNKERSILOS_SILOS'));
		setTextBold(false);
		renderText(g.topSectionBgaTextX, g.lines[0], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA'));

		if self.numSilos > 0 and self.activeSilo then
			local data = self.silos[self.activeSilo];
			self:renderSiloData(data);
		else -- no silos
			setTextAlignment(RenderText.ALIGN_CENTER);
			renderText(g.contentCenterX, g.lines[2], g.fontSize, g_i18n:getText('BUNKERSILOS_NOSILOS'));
			setTextAlignment(RenderText.ALIGN_LEFT);
		end;
	end;


	--###########################################################################


	-- Liquid manure tanks
	if self.numTanks > 0 and self.activeTank then
		local data = self.tanks[self.activeTank];
		self:renderTankData(data);
	else -- no tanks
		setTextAlignment(RenderText.ALIGN_CENTER);
		renderText(g.contentCenterX, g.lines[7], g.fontSize, g_i18n:getText('BUNKERSILOS_NOTANKS'));
	end;

	-- warning icon
	if self.displayWarning then
		self:setOverlayBlink(self.gui.warning);
		self.gui.warning:render();
	else
		self.gui.warning.curBlinkTime = nil;
	end;


	self:renderButtons();
	g.effects:render(); -- see TODO #1


	-- Reset text settings for other mods
	setTextAlignment(RenderText.ALIGN_LEFT);
	setTextColor(1, 1, 1, 1);
	setTextBold(false);
end;

function BunkerSilosHud:renderButtons()
	if BunkerSilosHud.hasMouseCursorActive then
		for _,button in ipairs(self.gui.buttons) do
			button:render();
		end;
	end;
end;

function BunkerSilosHud:renderBgaData(data)
	local g = self.gui;

	self.displayWarning = false;

	-- Line 1 ('BGA')
	setTextBold(true);
	setTextAlignment(RenderText.ALIGN_CENTER);
	renderText(g.contentCenterX, g.lines[1], g.fontSize, data.name);
	setTextBold(false);
	setTextAlignment(RenderText.ALIGN_LEFT);

	local realBga = g_currentMission.onCreateLoadedObjects[ data.onCreateIndex ];

	-- Line 2/3 (bunker fill level)
	if not data.bunkerFillLevel or data.bunkerFillLevel ~= realBga.bunkerFillLevel then
		--[[if data.bunkerFillLevel then
			self:debug(('time=%.1f, bunkerUseSpeed=%.1f, fillLevel=%.1f, change=%+.1f'):format(g_currentMission.time, realBga.bunkerUseSpeed, realBga.bunkerFillLevel, realBga.bunkerFillLevel - data.bunkerFillLevel));
		end;]]
		data.bunkerFillLevel = realBga.bunkerFillLevel;
		data.bunkerFillLevelFormatted = self:formatNumber(data.bunkerFillLevel * 0.001, 1);
		data.bunkerFillLevelPct = realBga.bunkerFillLevel / (realBga.bunkerCapacity + 0.000001);
		data.bunkerFillLevelPctFormatted = self:formatNumber(data.bunkerFillLevelPct * 100, 1);

		if not data.isComplexBga then
			local timeLeftMinutes = max(ceil(data.bunkerFillLevel / (realBga.bunkerUseSpeed * 60)), 0);
			if not data.timeLeft or timeLeftMinutes ~= data.timeLeft then
				data.timeLeft = timeLeftMinutes;
				data.timeLeftFormatted = self:getFormattedTime(timeLeftMinutes);
				-- self:debug(('    timeLeft=%.1f, timeLeftFormatted=%q'):format(data.timeLeft, data.timeLeftFormatted));
			end;
		end;
	end;
	self.displayWarning = data.bunkerFillLevel <= 0;

	if not data.bunkerCapacity or data.bunkerCapacity ~= realBga.bunkerCapacity then
		data.bunkerCapacity = realBga.bunkerCapacity;
		data.bunkerCapacityFormatted = self:formatNumber(realBga.bunkerCapacity * 0.001, 1);

		if self.complexBgaInstalled then
			local text = g_i18n:getText('BUNKERSILOS_BGA_BUNKERFILLLEVEL'):format(data.bunkerCapacityFormatted, data.bunkerCapacityFormatted, '100,0');
			g.bgaBunkerFillLevelBarBorderLeftPosX, g.bgaBunkerFillLevelBarMinX, g.bgaBunkerFillLevelBarMaxWidth = self:getBarDimensionsFromPrecedingText(text);
		end;
	end;

	renderText(g.contentMinX, g.lines[2], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA_BUNKERFILLLEVEL'):format(data.bunkerFillLevelFormatted, data.bunkerCapacityFormatted, data.bunkerFillLevelPctFormatted));

	local y = self.complexBgaInstalled and g.lines[2] or g.lines[3];
	renderOverlay(self.barBgOverlayId, g.bgaBunkerFillLevelBarMinX, y, g.bgaBunkerFillLevelBarMaxWidth, g.barHeight);
	renderOverlay(self.barOverlayId, g.bgaBunkerFillLevelBarBorderLeftPosX, y, g.barBorderWidth, g.barHeight);
	renderOverlay(self.barOverlayId, g.barBorderRightPosX, y, g.barBorderWidth, g.barHeight);
	if data.bunkerFillLevel > 0 then
		renderOverlay(self.barOverlayId, g.bgaBunkerFillLevelBarMinX, y, g.bgaBunkerFillLevelBarMaxWidth * data.bunkerFillLevelPct, g.barHeight);
	end;

	-- Line 4 (time left)
	if not data.isComplexBga and data.timeLeftFormatted and data.timeLeft > 0 then
		renderText(g.contentMinX, g.lines[4], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA_BUNKEREMPTYTIME'):format(data.timeLeftFormatted));
	end;

	-- COMPLEX BGA
	if data.isComplexBga then
		-- onCreateObject.fermenterTS;
		-- onCreateObject.fermenter_TS_min;
		-- onCreateObject.fermenter_TS_clog;
		-- onCreateObject.BGA_sizeFx;
		-- onCreateObject.fermenterCapacity;
		-- onCreateObject.fermenter_quality;
		-- onCreateObject.fermenter_TS_opt;
		-- onCreateObject.bunker_quality;
		-- onCreateObject.bunker_TS;
		-- onCreateObject.printPower;
		-- onCreateObject.fermenter_bioOK;

		if realBga.fermenter_bioOK then
			-- Line 3 (fermenter dry substance)
			if not data.fermenterDrySubstance or data.fermenterDrySubstance ~= realBga.fermenterTS then
				data.fermenterDrySubstance = realBga.fermenterTS;
				data.fermenterDrySubstanceFormatted = self:formatNumber(data.fermenterDrySubstance * 100, 2);
				data.fermenterDrySubstanceRelative = data.fermenterDrySubstance / realBga.fermenter_TS_clog;
			end;
			renderText(g.contentMinX, g.lines[3], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA_FERMENTERTS'):format(data.fermenterDrySubstanceFormatted));

			renderOverlay(self.barBgOverlayId, g.bgaFermenterDrySubstanceBarMinX, g.lines[3], g.bgaFermenterDrySubstanceBarMaxWidth, g.barHeight);
			renderOverlay(self.barOverlayId, g.bgaFermenterDrySubstanceBarBorderLeftPosX,  g.lines[3], g.barBorderWidth, g.barHeight);
			renderOverlay(self.barOverlayId, g.barBorderRightPosX, g.lines[3], g.barBorderWidth, g.barHeight);
			if data.fermenterDrySubstance > 0 then
				renderOverlay(self.barOverlayId, g.bgaFermenterDrySubstanceBarMinX, g.lines[3], g.bgaFermenterDrySubstanceBarMaxWidth * data.fermenterDrySubstanceRelative, g.barHeight);
			end;
			renderOverlay(self.barSpecialOverlayId, g.bgaFermenterDrySubstanceBarOptimumPosX, g.lines[3], g.barBorderWidth, g.barHeight);

			-- Line 4 (Bonus fill level)
			if not data.bonusFillLevel or data.bonusFillLevel ~= realBga.BGA_Bonus then
				data.bonusFillLevel = realBga.BGA_Bonus;
				data.bonusFillLevelFormatted = self:formatNumber(g_i18n:getFluid(data.bonusFillLevel));
				data.bonusFillLevelPct = realBga.BGA_Bonus / realBga.BGA_Bonus_Capacity;
				data.bonusFillLevelPctFormatted = self:formatNumber(data.bonusFillLevelPct * 100, 1);
			end;

			if not data.bonusCapacity or data.bonusCapacity ~= realBga.BGA_Bonus_Capacity then
				data.bonusCapacity = realBga.BGA_Bonus_Capacity;
				data.bonusCapacityFormatted = self:formatNumber(g_i18n:getFluid(realBga.BGA_Bonus_Capacity));

				-- TODO #2: bug in BGAextension: bonus fill level can be higher than capacity, that's why the base text has to contain an additional 0 - delete when bug is fixed
				local text = ('%s: %s0/%s %s (100,0%%)'):format(g_i18n:getText('BUNKERSILOS_BGA_BUNKERBONUS'), data.bonusCapacityFormatted, data.bonusCapacityFormatted, g_i18n:getText('fluid_unit_short'));
				g.bgaBunkerBonusFillLevelBarBorderLeftPosX, g.bgaBunkerBonusFillLevelBarMinX, g.bgaBunkerBonusFillLevelBarMaxWidth = self:getBarDimensionsFromPrecedingText(text);
			end;

			renderText(g.contentMinX, g.lines[4], g.fontSize, ('%s: %s/%s %s (%s%%)'):format(g_i18n:getText('BUNKERSILOS_BGA_BUNKERBONUS'), data.bonusFillLevelFormatted, data.bonusCapacityFormatted, g_i18n:getText('fluid_unit_short'), data.bonusFillLevelPctFormatted));

			renderOverlay(self.barBgOverlayId, g.bgaBunkerBonusFillLevelBarMinX, g.lines[4], g.bgaBunkerBonusFillLevelBarMaxWidth, g.barHeight);
			renderOverlay(self.barOverlayId, g.bgaBunkerBonusFillLevelBarBorderLeftPosX,  g.lines[4], g.barBorderWidth, g.barHeight);
			renderOverlay(self.barOverlayId, g.barBorderRightPosX, g.lines[4], g.barBorderWidth, g.barHeight);
			if data.bonusFillLevel > 0 then
				renderOverlay(self.barOverlayId, g.bgaBunkerBonusFillLevelBarMinX, g.lines[4], g.bgaBunkerBonusFillLevelBarMaxWidth * min(data.bonusFillLevelPct, 1), g.barHeight);
			end;

			-- Line 5 (power, feeding rate)
			if not data.kW or data.kW ~= realBga.printPower then
				data.kW = realBga.printPower;
				data.kWFormatted = self:formatNumber(data.kW, 1);
			end;
			if not data.feedingRate or data.feedingRate ~= realBga.bunkerFeedFactor then
				data.feedingRate = realBga.bunkerFeedFactor;
				data.feedingRateFormatted = round(data.feedingRate * 100);
			end;
			renderText(g.contentMinX, g.lines[5], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA_POWER_FEEDINGRATE'):format(data.kWFormatted, data.feedingRateFormatted));

			-- Line 5 (bunker dry substance)
			if not data.bunkerDrySubstance or data.bunkerDrySubstance ~= realBga.bunker_TS then
				data.bunkerDrySubstance = realBga.bunker_TS;
				data.bunkerDrySubstanceFormatted = self:formatNumber(data.bunkerDrySubstance * 100, 1);
			end;
			setTextAlignment(RenderText.ALIGN_RIGHT);
			renderText(g.contentMaxX, g.lines[5], g.fontSize, g_i18n:getText('BUNKERSILOS_BGA_BUNKERTS'):format(data.bunkerDrySubstanceFormatted));
			setTextAlignment(RenderText.ALIGN_LEFT);

			-- Line 6 (kW graph)
			if data.tsGraph then
				data.tsGraph:draw();
			end;

		else -- BGA inoperative
			setTextAlignment(RenderText.ALIGN_CENTER);
			renderText(g.contentCenterX, g.lines[5], g.fontSize, g_i18n:getText('BUNKERSILOS_BGAINACTIVE'));
			setTextAlignment(RenderText.ALIGN_LEFT);
		end;

		-- force power history update (once)
		if self.updateBgaPowerHistoryOnce then
			self:updateBgaPowerHistory(true);
			self.updateBgaPowerHistoryOnce = false;
		end;
	end;
end;

function BunkerSilosHud:renderSiloData(data)
	local g = self.gui;

	self.displayWarning = false;

	-- UPDATE SILO DATA
	local t = g_currentMission.tipTriggers[ self.tempSiloTriggers[data.bunkerSiloIdx] ];

	data.state = tonumber(t.bunkerSilo.state);
	data.stateText = self.bunkerStates[data.state];
	if t.bunkerSilo.fillLevel ~= data.fillLevel then
		data.fillLevel = t.bunkerSilo.fillLevel;
		data.fillLevelFormatted = self:formatNumber(data.fillLevel, 0);
		data.fillLevelPct = data.fillLevel / (data.capacity + 0.000001);
		data.fillLevelPctFormatted = data.fillLevel == 0 and '0' or self:formatNumber(data.fillLevelPct * 100, 1);
		data.toFillFormatted = self:formatNumber(data.capacity - data.fillLevel, 0);
		self:debug(('%s: updated fillLevel: capacity=%d, fillLevelFormatted=%q, fillLevelPctFormatted=%s, toFillFormatted=%q'):format(data.name, data.capacity, data.fillLevelFormatted, data.fillLevelPctFormatted, data.toFillFormatted));
	end;
	if t.bunkerSilo.compactedFillLevel ~= data.compactedFillLevel then
		data.compactedFillLevel = t.bunkerSilo.compactedFillLevel;
		data.compactPct = data.compactedFillLevel / (data.fillLevel + 0.000001);
		data.compactPctFormatted = data.fillLevel == 0 and '0' or self:formatNumber(data.compactPct * 100, 1);
		-- self:debug(string.format('updated compactedFillLevel: compactPctFormatted=%q', data.compactPctFormatted));
	end;
	if t.bunkerSilo.state == BunkerSilo.STATE_CLOSED then
		local fermentingTime = round(t.bunkerSilo.fermentingTime);
		if fermentingTime ~= data.fermentingTime then
			data.fermentingTime = fermentingTime;
			local fermentationPct = round(min(data.fermentingTime / (data.fermentingDuration + 0.00001), 1), 3);
			if fermentationPct ~= data.fermentationPct then
				data.fermentationPct = fermentationPct;
				data.fermentationPctFormatted = data.fermentingTime == 0 and '0' or self:formatNumber(data.fermentationPct * 100, 1);
			end;
			local timeLeftMinutes = max(round((data.fermentingDuration - fermentingTime)/60), 0);
			if not data.timeLeft or timeLeftMinutes ~= data.timeLeft then
				data.timeLeft = timeLeftMinutes;
				data.timeLeftFormatted = self:getFormattedTime(timeLeftMinutes);
			end;
		end;
		self.displayWarning = data.fermentationPct >= 1;
	end;

	-- movingPlane boxes
	local rottenFillLevel = 0;
	if data.fillLevel > 0 then
		for i,mp in pairs(data.movingPlanes) do
			local origMp = t.bunkerSilo.movingPlanes[i];
			if origMp.fillLevel > 0 then
				if not mp.fillLevel or mp.fillLevel ~= origMp.fillLevel then
					mp.fillLevel = origMp.fillLevel;
					mp.fillLevelPct = origMp.fillLevel / origMp.capacity;
					if mp.fillLevelPct < 1 then
						mp.fillLevelPctFormatted = ('%s%%'):format(round(mp.fillLevelPct * 100));
					end;
				end;

				-- single mp's compact fillLevel (ImprovedSilageBunker)
				if origMp.compactFillLevel then
					if not mp.compactFillLevel or mp.compactFillLevel ~= origMp.compactFillLevel then
						mp.compactFillLevel = origMp.compactFillLevel;
						if data.state == BunkerSilo.STATE_FILL then
							mp.compactFillLevelPct = origMp.compactFillLevel / origMp.fillLevel;
							mp.compactFillLevelPctFormatted = ('%s%%'):format(round(mp.compactFillLevelPct * 100));
						end;
					end;
				end;

				if origMp.isRotten then -- single mp rotten (ImprovedSilageBunker)
					rottenFillLevel = rottenFillLevel + mp.fillLevel;

					self:setOverlayIdColor(self.movingPlanesNonCompactedOverlayId, 'movingPlanesNonCompactedColor', 'rottenNonCompacted');
					self:setOverlayIdColor(self.movingPlanesOverlayId, 'movingPlanesColor', 'rotten');
				else
					self:setOverlayIdColor(self.movingPlanesNonCompactedOverlayId, 'movingPlanesNonCompactedColor', 'defaultNonCompacted');
					self:setOverlayIdColor(self.movingPlanesOverlayId, 'movingPlanesColor', 'default');
				end;

				local nonCompactedHeight = mp.fillLevelPct * g.boxMaxHeight;
				local height;
				if mp.compactFillLevel then -- single mp's compact fillLevel (ImprovedSilageBunker)
					if data.state == BunkerSilo.STATE_FILL and mp.fillLevel ~= mp.compactFillLevel then
						renderOverlay(self.movingPlanesNonCompactedOverlayId, mp.boxX, g.lines[6], data.boxWidth, nonCompactedHeight)
						height = origMp.compactFillLevel / origMp.capacity * g.boxMaxHeight;
					else
						height = nonCompactedHeight;
					end;
					renderOverlay(self.movingPlanesOverlayId, mp.boxX, g.lines[6], data.boxWidth, height)

				else
					if data.state == BunkerSilo.STATE_FILL and data.compactPct < 1 then
						renderOverlay(self.movingPlanesNonCompactedOverlayId, mp.boxX, g.lines[6], data.boxWidth, nonCompactedHeight)
						height = nonCompactedHeight * data.compactPct;
					else
						height = nonCompactedHeight;
					end;
					renderOverlay(self.movingPlanesOverlayId, mp.boxX, g.lines[6], data.boxWidth, height)
				end;

				-- MP PCT TEXT
				local text, fontSize = nil, data.movingPlanesNum > 15 and g.fontSizeTiny or g.fontSizeSmall;
				local showFillLevelPct, showCompactPct = false, false;
				-- single mp's compact fillLevel (ImprovedSilageBunker)
				if data.state == BunkerSilo.STATE_FILL and mp.compactFillLevelPct and mp.compactFillLevelPctFormatted then
					showCompactPct = true;
					if mp.compactFillLevelPct >= 1 then
						fontSize = g.fontSizeTiny;
					end;
				end;

				-- single mp's fill level
				if data.state ~= BunkerSilo.STATE_CLOSED and mp.fillLevelPct and mp.fillLevelPctFormatted then
					if data.movingPlanesNum < 10 or not showCompactPct then
						showFillLevelPct = true;
						if mp.fillLevelPct >= 1 then
							fontSize = g.fontSizeTiny;
						end;
					end;
				end;

				if showFillLevelPct then
					text = mp.fillLevelPctFormatted;
				end;
				if showCompactPct then
					if showFillLevelPct then
						text = text .. '/' .. mp.compactFillLevelPctFormatted;
					else
						text = mp.compactFillLevelPctFormatted;
					end;
				end;
				if text then
					setTextAlignment(RenderText.ALIGN_CENTER);
					renderText(mp.boxCenterX, g.lines[5], fontSize, text);
				end;
			end; -- END if mp.fillLevel > 0
		end; -- END for mp in movingPlanes
	end; -- END if data.fillLevel > 0
	if rottenFillLevel ~= data.rottenFillLevel then
		data.rottenFillLevel = rottenFillLevel;
		data.rottenFillLevelPctFormatted = self:formatNumber((data.rottenFillLevel / (data.fillLevel + 0.00001)) * 100, 1);
	end;


	-- RENDER SILO DATA
	-- Line 1 ('Silo')
	setTextAlignment(RenderText.ALIGN_CENTER);
	setTextBold(true);
	renderText(g.contentCenterX, g.lines[1], g.fontSize, data.name);

	setTextBold(false);
	setTextAlignment(RenderText.ALIGN_LEFT);
	-- Line 2
	if data.state < 2 then
		renderText(g.contentMinX, g.lines[2], g.fontSize, ('%s: %s (%s%% %s)'):format(g_i18n:getText('BUNKERSILOS_STATE'), data.stateText, data.compactPctFormatted, g_i18n:getText('BUNKERSILOS_COMPACT')));
	else
		if data.rottenFillLevel > 0 then
			renderText(g.contentMinX, g.lines[2], g.fontSize, ('%s: %s (%s%% %s)'):format(g_i18n:getText('BUNKERSILOS_STATE'), data.stateText, data.rottenFillLevelPctFormatted, g_i18n:getText('BUNKERSILOS_ROTTEN')));
		else
			renderText(g.contentMinX, g.lines[2], g.fontSize, ('%s: %s'):format(g_i18n:getText('BUNKERSILOS_STATE'), data.stateText));
		end;
	end;

	-- Line 3 (fill level)
	renderText(g.contentMinX, g.lines[3], g.fontSize, ('%s: %s / %s (%s%%)'):format(g_i18n:getText('BUNKERSILOS_FILLLEVEL'), data.fillLevelFormatted, data.capacityFormatted, data.fillLevelPctFormatted));

	-- Line 4
	if data.state == BunkerSilo.STATE_FILL and data.fillLevelPct < 100 then
		renderText(g.contentMinX, g.lines[4], g.fontSize, ('%s: %s'):format(g_i18n:getText('BUNKERSILOS_TOBEFILLED'), data.toFillFormatted));
	elseif data.state == BunkerSilo.STATE_CLOSED then
		if data.fermentationPct < 1 then
			renderText(g.contentMinX, g.lines[4], g.fontSize, ('%s: %s%% (%s)'):format(g_i18n:getText('BUNKERSILOS_FERMENTATION_PROGRESS'), data.fermentationPctFormatted, g_i18n:getText('BUNKERSILOS_TIME_LEFT'):format(data.timeLeftFormatted)));
		else
			renderText(g.contentMinX, g.lines[4], g.fontSize, ('%s: %s%%'):format(g_i18n:getText('BUNKERSILOS_FERMENTATION_PROGRESS'), data.fermentationPctFormatted));
		end;
	end;
end;

function BunkerSilosHud:renderTankData(data)
	local g = self.gui;

	-- UPDATE TANK DATA
	local fillLevel;
	if data.isBGA then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].liquidManureSiloTrigger.fillLevel;
	elseif data.isCowsLiquidManure then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].liquidManureTrigger.fillLevel;
	elseif data.isCowsManure then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].manureHeap.fillLevel;
	elseif data.isPigsLiquidManure then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].liquidManureSiloTrigger.fillLevel;
	elseif data.isPigsManure then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].manureHeap.FillLvl;
	elseif data.isManureLager then
		fillLevel = g_currentMission.onCreateLoadedObjects[data.onCreateIndex].fillLevel;
	end;
	if not fillLevel then
		return;
	end;

	if fillLevel ~= data.fillLevel then
		data.fillLevel = fillLevel;
		data.fillLevelFormatted = self:formatNumber(data.fillLevel, 0);
		data.fillLevelPct = data.fillLevel / data.capacity + 0.00001;
		data.fillLevelPctFormatted = self:formatNumber(data.fillLevelPct * 100, 1);
		self:debug(('BSH tank %q: updated fillLevel: fillLevelFormatted=%q, fillLevelPctFormatted=%q'):format(data.name, data.fillLevelFormatted, data.fillLevelPctFormatted));
	end;

	-- RENDER TANK DATA
	local x1, x2 = g.contentMinX, data.fillLevelTxtPosX;
	if g.changeTankNegButton and g.changeTankNegButton.isVisible and g.hudState == BunkerSilosHud.HUDSTATE_INTERACTIVE then
		x1, x2 = x1 + g.buttonGfxWidth, x2 + g.buttonGfxWidth;
	end;
	-- Line 7 (title)
	setTextAlignment(RenderText.ALIGN_LEFT);
	setTextBold(true);
	renderText(x1, g.lines[7], g.fontSize, data.name .. ':');
	setTextBold(false);

	-- Line 7 (fill level)
	renderText(x2, g.lines[7], g.fontSize, ('%s: %s / %s %s (%s%%)'):format(g_i18n:getText('BUNKERSILOS_FILLLEVEL'), data.fillLevelFormatted, data.capacityFormatted, g_i18n:getText('fluid_unit_short'), data.fillLevelPctFormatted));

	-- Line 8 (Bar)
	renderOverlay(self.barBgOverlayId, g.tankBarMinX, g.lines[8], g.tankBarMaxWidth, g.barHeight);
	renderOverlay(self.barOverlayId, g.tankBarBorderLeftPosX,  g.lines[8], g.barBorderWidth, g.barHeight);
	renderOverlay(self.barOverlayId, g.barBorderRightPosX, g.lines[8], g.barBorderWidth, g.barHeight);

	if data.fillLevel > 0 then
		renderOverlay(self.barOverlayId, g.tankBarMinX, g.lines[8], g.tankBarMaxWidth * data.fillLevelPct, g.barHeight);
	end;
end;

function BunkerSilosHud:hourChanged()
	if not self.complexBgaInstalled then return; end;

	self:updateBgaPowerHistory();
end;

function BunkerSilosHud:updateBgaPowerHistory(skipCurrent)
	-- UPDATE BGA POWER GRAPH AND HISTORY

	self.updateBgaPowerHistoryOnce = false; -- no need to run the force update if the data has already been updated by a regular hour change

	for i,data in ipairs(self.bgas) do
		self:debug(('updateBgaPowerHistory(%s) (BGA %d / %q):'):format(tostring(skipCurrent), i, data.name));
		if data.tsGraph then
			local realBga = g_currentMission.onCreateLoadedObjects[ data.onCreateIndex ];

			local kW;
			if not skipCurrent then
				kW = realBga.printPower; -- usage of real power variable as data.kW might not be up to date as the BGA page might not be shown

				data.powerHistory[#data.powerHistory + 1] = kW;
				if #data.powerHistory > data.tsGraphNumValues then
					table.remove(data.powerHistory, 1);
				end;
				self:debug(('    adding current printPower (%.1f) to history'):format(kW));
			end;

			-- update history in realBga, so it can be saved to vehicles.xml
			realBga.bshPowerHistory = data.powerHistory;

			-- update max value
			local maxValue = 0;
			if not skipCurrent and #data.powerHistory < data.tsGraphNumValues then -- we don't have enough data, so let's keep it simple for now and get the highest value so far
				maxValue = max(data.tsGraph.maxValue, kW);
				self:debug(('    #powerHistory < tsGraphNumValues -> maxValue=max(%.1f, %.1f)=%.1f'):format(data.tsGraph.maxValue, kW, maxValue));
			else -- get the highest value from the past 48 hours
				maxValue = max(unpack(data.powerHistory));
				self:debug(('    maxValue = highest in powerHistory list = %.1f'):format(maxValue));
			end;
			if maxValue == 0 then
				maxValue = 200;
			end;
			data.tsGraph.maxValue = maxValue;

			-- finally set values in graph
			for i = 1, data.tsGraphNumValues do
				data.tsGraph:setValue(i, data.powerHistory[i]);
			end;
		end;
	end;
end;

function BunkerSilosHud:addLoadedBgaPowerHistory(bga, powerHistory)
	local data = self.bgaToBshData[bga];
	self:debug(('addLoadedPowerHistory() BGA %q [onCreateIndex %d]: add bshPowerHistory from loaded vehicles.xml to data.powerHistory'):format(data.name, data.onCreateIndex));

	if not data.tsGraph then
		self:debug('    tsGraph == nil -> return');
		return;
	end;

	data.powerHistory = Utils.copyTable(powerHistory);

	self:debug(('    new data.powerHistory=%q (%d values)'):format(table.concat(data.powerHistory, ', '), #data.powerHistory));
end;



function BunkerSilosHud:mouseEvent(posX, posY, isDown, isUp, mouseButton)
	BunkerSilosHud.canScroll = false;
	if self.gui.hudState ~= BunkerSilosHud.HUDSTATE_INTERACTIVE then
		return;
	end;

	local isOnGui = self:mouseIsInArea(posX, posY, self.gui.x1, self.gui.x2, self.gui.y1, self.gui.y2);

	-- CLICKING (up)
	if isUp and mouseButton == Input.MOUSE_BUTTON_LEFT then 
		-- drag & drop release
		if self.gui.dragDropMouseDown then
			local dx, dy = posX - self.gui.dragDropMouseDown[1], posY - self.gui.dragDropMouseDown[2];
			self:moveGui(dx, dy);
			return;
		end;

		-- button click
		if isOnGui then
			for _,button in pairs(self.gui.buttons) do
				button.isClicked = false;
				button.isHovered = false;
				if button.isVisible and self:mouseIsOnButton(posX, posY, button) then
					button.isHovered = true;
					BunkerSilosHud[button.fn](self, button.prm);
					break; --no need to check the rest of the buttons
				end;
			end;
		end;

	-- CLICKING (down)
	elseif isDown and mouseButton == Input.MOUSE_BUTTON_LEFT and isOnGui then
		local hasButtonEvent = false;
		for _,button in pairs(self.gui.buttons) do
			button.isHovered = false;
			button.isClicked = button.isVisible and self:mouseIsOnButton(posX, posY, button);
			if button.isClicked then
				hasButtonEvent = true;
			end;
		end;

		-- click in general area -> drag & drop
		if not hasButtonEvent then
			self.gui.dragDropMouseDown = { posX, posY };
			self.gui.background.origPos = { self.gui.background.x, self.gui.background.y };
		end;

	-- DRAG AND DROP MOVEMENT
	elseif not isUp and not isDown and self.gui.dragDropMouseDown then
		local dx, dy = posX - self.gui.dragDropMouseDown[1], posY - self.gui.dragDropMouseDown[2];
		self:dragDropUpdateBackground(dx, dy);

	-- HOVERING / SCROLLING
	elseif not isDown then
		if isOnGui then
			for _,button in pairs(self.gui.buttons) do
				button.isClicked = false;
				button.isHovered = button.isVisible and self:mouseIsOnButton(posX, posY, button);
			end;

			local fn, upParameter, downParameter;

			-- mouse is in top section area
			if self:mouseIsInArea(posX, posY, unpack(self.gui.topSectionArea)) then
				if self.gui.activeTopSection == BunkerSilosHud.TOPSECTION_SILOS and self.numSilos > 1 then
					BunkerSilosHud.canScroll = true;
					fn, upParameter, downParameter = self.changeSilo, 1, -1;
				elseif self.gui.activeTopSection == BunkerSilosHud.TOPSECTION_BGA and self.numBgas > 1 then
					BunkerSilosHud.canScroll = true;
					fn, upParameter, downParameter = self.changeBga, 1, -1;
				end;

			-- mouse is in tank area
			elseif self.numTanks > 1 and self:mouseIsInArea(posX, posY, unpack(self.gui.tankArea)) then
				BunkerSilosHud.canScroll = true;
				fn, upParameter, downParameter = self.changeTank, 1, -1;
			end;

			local hideHandTool;
			if isUp and mouseButton == Input.MOUSE_BUTTON_WHEEL_UP and fn and upParameter then
				fn(self, upParameter);
				hideHandTool = true;
			elseif isUp and mouseButton == Input.MOUSE_BUTTON_WHEEL_DOWN and fn and downParameter then
				fn(self, downParameter);
				hideHandTool = true;
			end;
			if hideHandTool and g_currentMission.player ~= nil and g_currentMission.player.currentToolId ~= 0 then
				-- print('BSH: setTool(nil)');
				g_currentMission.player:setTool(nil);
			end;
		end;
	end;
end;

function BunkerSilosHud:mouseIsInArea(mouseX, mouseY, areaX1, areaX2, areaY1, areaY2)
	return mouseX >= areaX1 and mouseX <= areaX2 and mouseY >= areaY1 and mouseY <= areaY2;
end;

function BunkerSilosHud:mouseIsOnButton(mouseX, mouseY, button)
	return mouseX >= button.x1 and mouseX <= button.x2 and mouseY >= button.y1 and mouseY <= button.y2;
end;

function BunkerSilosHud:rgba(r, g, b, a)
	return { r/255, g/255, b/255, a };
end;

function BunkerSilosHud:formatNumber(number, precision)
	precision = precision or 0;

	local str = '';
	local firstDigit, rest, decimal = ('%1.' .. precision .. 'f'):format(number):match('^([^%d]*%d)(%d*).?(%d*)');
	str = firstDigit .. rest:reverse():gsub('(%d%d%d)', '%1' .. self.numberSeparator):reverse();
	if decimal:len() > 0 then
		str = str .. self.numberDecimalSeparator .. decimal:sub(1, precision);
	end;
	return str;
end;

function BunkerSilosHud:getBarDimensionsFromPrecedingText(text, fontSize)
	fontSize = fontSize or self.gui.fontSize;
	local textWidth = getTextWidth(fontSize, text);
	local borderLeftX = self.gui.contentMinX + textWidth + self.gui.barBorderWidth;
	local barMinX = borderLeftX + (self.gui.barBorderWidth * 2);
	local barMaxWidth = self.gui.barMaxX - barMinX;

	return borderLeftX, barMinX, barMaxWidth;
end;

-- @src: Decker, compas.lua
function BunkerSilosHud:getKeyIdOfModifier(binding)
	if InputBinding.actions[binding] == nil then
		return nil;  -- Unknown input-binding.
	end;
	if #(InputBinding.actions[binding].keys1) <= 1 then
		return nil; -- Input-binding has only one or zero keys. (Well, in the keys1 - I'm not checking keys2)
	end;
	-- Check if first key in key-sequence is a modifier key (LSHIFT/RSHIFT/LCTRL/RCTRL/LALT/RALT)
	if Input.keyIdIsModifier[ InputBinding.actions[binding].keys1[1] ] then
		return InputBinding.actions[binding].keys1[1]; -- Return the keyId of the modifier key
	end;
	return nil;
end

function BunkerSilosHud:setOverlayBlink(overlay, noFade)
	-- HARD BLINK
	if noFade then
		if overlay.a ~= 1 then
			overlay:setColor(overlay.r, overlay.g, overlay.b, 1);
		end;
		if overlay.curBlinkTime == nil then
			overlay.curBlinkTime = g_currentMission.time + self.blinkLength;
			overlay:setIsVisible(true);
		else
			if g_currentMission.time >= overlay.curBlinkTime then
				overlay.curBlinkTime = overlay.curBlinkTime + self.blinkLength;
				overlay:setIsVisible(not overlay.visible);
			end;
		end;
		return;
	end;

	-- FADE IN/OUT
	local alpha = 1;
	if overlay.curBlinkTime == nil then
		overlay.curBlinkTime = g_currentMission.time + self.blinkLength;
		overlay.fadeDir = 1;
		alpha = 0;
	else
		if g_currentMission.time < overlay.curBlinkTime then
			local alphaRatio = 1 - (overlay.curBlinkTime - g_currentMission.time) / self.blinkLength;
			if overlay.fadeDir == -1 then
				alpha = 1 - alphaRatio;
			else
				alpha = alphaRatio;
			end;
		else
			overlay.curBlinkTime = overlay.curBlinkTime + self.blinkLength;
			alpha = overlay.fadeDir == 1 and 1 or 0;
			overlay.fadeDir = -overlay.fadeDir;
		end;
	end;
	overlay:setColor(overlay.r, overlay.g, overlay.b, alpha);
end;

function BunkerSilosHud:deleteOverlay(overlay)
	if overlay and overlay.overlayId then
		overlay:delete();
		overlay = nil;
	end;
end;

function BunkerSilosHud:setOverlayUVsPx(overlay, UVs, textureSizeX, textureSizeY)
	if overlay.overlayId and overlay.currentUVs == nil or overlay.currentUVs ~= UVs then
		local leftX, bottomY, rightX, topY = unpack(UVs);

		local fromTop = false;
		if topY < bottomY then
			fromTop = true;
		end;
		local leftXNormal = leftX / textureSizeX;
		local rightXNormal = rightX / textureSizeX;
		local bottomYNormal = bottomY / textureSizeY;
		local topYNormal = topY / textureSizeY;
		if fromTop then
			bottomYNormal = 1 - bottomYNormal;
			topYNormal = 1 - topYNormal;
		end;
		setOverlayUVs(overlay.overlayId, leftXNormal,bottomYNormal, leftXNormal,topYNormal, rightXNormal,bottomYNormal, rightXNormal,topYNormal);
		overlay.currentUVs = UVs;
	end;
end;

function BunkerSilosHud:setOverlayColor(overlay, colorName)
	if overlay == nil or overlay.curColor == colorName then
		return;
	end;

	overlay:setColor(unpack(self.gui.colors[colorName]));
	overlay.curColor = colorName;
end;

function BunkerSilosHud:setOverlayIdColor(overlayId, colorAttribute, colorName)
	if overlayId ~= 0 and (self[colorAttribute] == nil or self[colorAttribute] ~= colorName) then
		setOverlayColor(overlayId, unpack(self.gui.colors[colorName]));
		self[colorAttribute] = colorName;
	end;
end;

function BunkerSilosHud:getFormattedTime(minutes)
	return ('%.2d:%.2d'):format(minutes / 60,  minutes % 60);
end;


-- SAVE/LOAD bshNames and powerHistory
function BunkerSilosHud:setSaveAndLoadFunctions()
	self:debug('setSaveAndLoadFunctions()');

	local oldBunkerSilogetSaveAttributesAndNodes = BunkerSilo.getSaveAttributesAndNodes;
	function BunkerSilo:getSaveAttributesAndNodes(nodeIdent)
		local attributes, nodes = oldBunkerSilogetSaveAttributesAndNodes(self, nodeIdent);
		if self.bshName ~= nil then
			attributes = ('%s bshName=%q'):format(attributes, self.bshName);
		end;
		return attributes, nodes;
	end;
	self:debug('    BunkerSilo:getSaveAttributesAndNodes() appended');

	local oldBGAgetSaveAttributesAndNodes = Bga.getSaveAttributesAndNodes;
	function Bga:getSaveAttributesAndNodes(nodeIdent)
		BunkerSilosHud:debug(('Bga.getSaveAttributesAndNodes'));
		local attributes, nodes = oldBGAgetSaveAttributesAndNodes(self, nodeIdent);
		if self.liquidManureSiloTrigger ~= nil and self.liquidManureSiloTrigger.bshName ~= nil then
			attributes = ('%s bshName=%q'):format(attributes, self.liquidManureSiloTrigger.bshName);
		end;

		if BunkerSilosHud.complexBgaInstalled then
			-- save power history
			if self.bshPowerHistory then
				BunkerSilosHud:debug(('    self.bshPowerHistory=%s (#=%d)'):format(tostring(self.bshPowerHistory), #self.bshPowerHistory));
				-- BunkerSilosHud:tableShow(self.bshPowerHistory);
				if #self.bshPowerHistory > 0 then
					local historyText = ('%.1f'):format(self.bshPowerHistory[1]);
					if #self.bshPowerHistory > 1 then
						for i=2,#self.bshPowerHistory do
							historyText = historyText .. (' %.1f'):format(self.bshPowerHistory[i]);
						end;
					end;
					BunkerSilosHud:debug('    ' .. historyText)
					attributes = ('%s bshPowerHistory=%q'):format(attributes, historyText);
				end;
			else
				BunkerSilosHud:debug('    self.bshPowerHistory=nil');
			end;
		end;

		return attributes, nodes;
	end;
	self:debug('    Bga:getSaveAttributesAndNodes() appended');

	if self.complexBgaInstalled then
		local oldBGAloadFromAttributesAndNodes = Bga.loadFromAttributesAndNodes;
		function Bga:loadFromAttributesAndNodes(xmlFile, key)
			local powerHistory = getXMLString(xmlFile, key .. '#bshPowerHistory');
			if powerHistory then
				BunkerSilosHud:debug(('BGA loadFromAttributes: set bshPowerHistory from string %q'):format(tostring(powerHistory)));
				self.bshPowerHistory = Utils.getVectorNFromString(powerHistory);
				BunkerSilosHud:addLoadedBgaPowerHistory(self, self.bshPowerHistory);
			end;

			return oldBGAloadFromAttributesAndNodes(self, xmlFile, key);
		end;
		self:debug('    Bga:loadFromAttributesAndNodes() prepended');
	end;

	BunkerSilosHud.saveAndLoadFunctionsOverwritten = true;
end;

function BunkerSilosHud:keyEvent(unicode, sym, modifier, isDown) end;



-- ################################################################################
-- MULTIPLAYER

local origServerSendObjects = Server.sendObjects;
function Server:sendObjects(connection, x, y, z, viewDistanceCoeff)
	connection:sendEvent(BunkerSilosHudJoinEvent:new());
	return origServerSendObjects(self, connection, x, y, z, viewDistanceCoeff);
end

BunkerSilosHudJoinEvent = {};
BunkerSilosHudJoinEvent_mt = Class(BunkerSilosHudJoinEvent, Event);
InitEventClass(BunkerSilosHudJoinEvent, 'BunkerSilosHudJoinEvent');

function BunkerSilosHudJoinEvent:emptyNew()
	local self = Event:new(BunkerSilosHudJoinEvent_mt);
	self.className = BunkerSilosHud.modName .. '.BunkerSilosHudJoinEvent';
	return self;
end
function BunkerSilosHudJoinEvent:new()
	local self = BunkerSilosHudJoinEvent:emptyNew()
	return self;
end

function BunkerSilosHudJoinEvent:writeStream(streamId, connection)
	if not connection:getIsServer() then
		BunkerSilosHud:debug(('writeStream(%s, %s)'):format(tostring(streamId), tostring(connection)));
		for i,data in pairs(BunkerSilosHud.bgas) do
			-- (1) send the amount of power history values
			local numPowerHistoryValues = data.powerHistory and #data.powerHistory or 0;
			streamWriteInt8(streamId, numPowerHistoryValues);
			BunkerSilosHud:debug(('    BGA %d: write numPowerHistoryValues=%d'):format(i, numPowerHistoryValues));

			-- (2) send the power history values
			if numPowerHistoryValues > 0 then
				for j=1,numPowerHistoryValues do
					streamWriteFloat32(streamId, data.powerHistory[j]);
					BunkerSilosHud:debug(('        write history value %d: %s'):format(j, tostring(data.powerHistory[j])));
				end;
			end;
		end;
	end;
end;
function BunkerSilosHudJoinEvent:readStream(streamId, connection)
	if connection:getIsServer() then
		BunkerSilosHud:debug(('readStream(%s, %s)'):format(tostring(streamId), tostring(connection)));
		for i,data in pairs(BunkerSilosHud.bgas) do
			-- (1) get the amount of power history values
			local numPowerHistoryValues = streamReadInt8(streamId);
			BunkerSilosHud:debug(('    BGA %d: read numPowerHistoryValues=%s'):format(i, tostring(numPowerHistoryValues)));

			-- (2) get the power history values
			if numPowerHistoryValues and numPowerHistoryValues > 0 then
				for j=1,numPowerHistoryValues do
					data.powerHistory[j] = streamReadFloat32(streamId);
					BunkerSilosHud:debug(('        read history value %d: %s'):format(j, tostring(data.powerHistory[j])));
				end;
			end;
		end;
	end;
end;


-- ################################################################################
-- Debug

function BunkerSilosHud:debug(str)
	if self.debugActive then
		print('[BSH lp' .. g_updateLoopIndex .. '] ' .. tostring(str));
	end;
end;

-- ################################################################################
-- BshButton

BshButton = {};
BshButton_mt = Class(BshButton);

function BshButton:new(UVsName, fn, parameter, x, y, width, height, clickWidth, clickHeight)
	local self = setmetatable({}, BshButton_mt);

	if UVsName and BunkerSilosHud.gui.iconUVs[UVsName] then
		self.overlay = Overlay:new(fn, BunkerSilosHud.gui.iconFilePath, x, y, width, height);
		self.overlay.a = 0.7;
		BunkerSilosHud:setOverlayUVsPx(self.overlay, BunkerSilosHud.gui.iconUVs[UVsName], BunkerSilosHud.gui.iconFileSize[1], BunkerSilosHud.gui.iconFileSize[2]);
	end;

	self.fn = fn;
	self.prm = parameter;
	self.clickWidth = clickWidth;
	self.clickHeight = clickHeight;
	self.width = width;
	self.height = height;
	self:setPosition(x, y);
	self:setVisible(true);

	BunkerSilosHud.gui.buttons[#BunkerSilosHud.gui.buttons + 1] = self;

	return self;
end;

function BshButton:setPosition(x, y)
	self.x1 = x;
	self.x2 = x + (self.clickWidth or self.width);
	self.y1 = y;
	self.y2 = y + (self.clickHeight or self.height);

	if self.overlay then
		self.overlay:setPosition(x, y);
	end;
end;

function BshButton:setVisible(visible)
	self.isVisible = visible;
end;

function BshButton:render()
	if self.overlay and self.isVisible then
		if self.isClicked and self.overlay.curColor ~= 'clicked' then
			BunkerSilosHud:setOverlayColor(self.overlay, 'clicked');
		elseif self.isHovered and self.overlay.curColor ~= 'defaultHover' then
			BunkerSilosHud:setOverlayColor(self.overlay, 'defaultHover');
		elseif not self.isClicked and not self.isHovered and self.overlay.curColor ~= 'default' then
			BunkerSilosHud:setOverlayColor(self.overlay, 'default');
		end;
		self.overlay:render();
	end;
end;

function BshButton:delete()
	if self.overlay then
		BunkerSilosHud:deleteOverlay(self.overlay);
	end;
end;
