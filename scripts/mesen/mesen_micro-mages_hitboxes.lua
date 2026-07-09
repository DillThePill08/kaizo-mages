local HITBOX_COLOR = 0x3FFF0000
local SHOW_ACTOR_ID = false			--display an actor's index above the hitbox
local SHOW_TILE_HITBOXES = true	   --show hitboxes from tiles $02 and $03 (saws and lava)
local EXTEND_TILE_HITBOXES = true    --combine single pixel hitboxes to something more visible and expected

----------------------------------
-- determine memory addresses by game version
-- determine game version by file hash
local ROM_SHA1 = emu.getRomInfo().fileSha1Hash

local LABELS = {}
local GAME_VERSION = 0

local RADIUS_TABLE_SIZE = 0x3B

if ROM_SHA1 == "1411F9009CFA944C23B318620DA72E395070C650"      --iNES
or ROM_SHA1 == "A7B5AB31DB66EC035BCACA35D85317872BF6C698" then --NES 2.0
  emu.log("Detected game: Micro Mages 2019")
  LABELS.Map_worldDigit = 0xBD
  LABELS.Map_scrollY = 0xCC
  LABELS.Actor_px = 0x4A
  LABELS.Actor_py = 0x360
  LABELS.Actor_id = 0x200
  LABELS.Map_map = 0x600

  LABELS.Data_Actor_radius = 0xBEFA
  LABELS.Data_Tileset_addrs = 0xAF10
  LABELS.Map_SHARED__TILE16__ADDRS = 0xF883

elseif ROM_SHA1 == "776C49B353256E086BF794E136C8B5A4FC2F973F"  --iNES
or ROM_SHA1 == "3293101D7BBD9E8D4818CDB02F8323620624A236" then --NES 2.0
  emu.log("Detected game: Micro Mages Second Quest")
  GAME_VERSION = 1
  LABELS.Map_worldDigit = 0xBD
  LABELS.Map_scrollY = 0xCC
  LABELS.Actor_px = 0x4A
  LABELS.Actor_py = 0x360
  LABELS.Actor_id = 0x200
  LABELS.Map_map = 0x600

  LABELS.Data_Actor_radius = 0xBEAB
  LABELS.Data_Tileset_addrs = 0xAEBF
  LABELS.Map_SHARED__TILE16__ADDRS = 0xF85A

else
  GAME_VERSION = 2
  emu.log("Detected game: Micro Mages Custom Quest (v1.0.8)")
  LABELS.Map_worldDigit = 0xBD
  LABELS.Map_scrollY = 0xCB
  LABELS.Actor_px = 0x4A
  LABELS.Actor_py = 0x360
  LABELS.Actor_id = 0x200
  LABELS.Map_map = 0x600

  LABELS.Data_Actor_radius = 0xB753
  LABELS.Data_Tileset_addrs = 0
  LABELS.Map_SHARED__TILE16__ADDRS = 0

  RADIUS_TABLE_SIZE = 0x3d
end

function read8(address)
  return emu.read(address, emu.memType.nesDebug, false)
end

function read16(address)
  return emu.read16(address, emu.memType.nesDebug, false)
end

function tableFind(haystack, needle)
  for i = 1, #haystack do
    if haystack[i] == needle then return i end
  end
  return 0
end

local SHARED_META16_SIZE = read16(LABELS.Map_SHARED__TILE16__ADDRS + 2) - read16(LABELS.Map_SHARED__TILE16__ADDRS)
local ACTOR_TABLE_SIZE = 0x20

local SAW_HITBOX_EXTEND = { --for extending tile $01's single-pixel hitbox to the full metatile
  --[tile8_index] = {drawPosX, drawPosY, drawWidth, drawHeight} 
  {3, 5, 5, 3},
  {0, 5, 4, 3},
  {3, 0, 5, 6},
  {0, 0, 4, 6}
}

local LAVA_HITBOX_EXTEND = { --for extending tile $02's single-pixel hitbox to the tile8 next to it
  --[tile8_index] = {drawPosX, drawWidth} 
  {3, 5},
  {0, 4},
  {3, 5},
  {0, 4},
}

local MAKER_LAVA_TILES = {0x02, 0x93, 0x94, 0xD3, 0xD4, 0xD5, 0xD6, 0xD7}

function startFrame()
  local currentScrollY = read8(LABELS.Map_scrollY)
  emu.clearScreen()

  for actorIndex = 0, ACTOR_TABLE_SIZE - 1 do
    currentActorID = read8(LABELS.Actor_id + actorIndex)
    if currentActorID == 0 or currentActorID > RADIUS_TABLE_SIZE then goto continue end

    --saw hitbox ineffective unless on Micro Mages Maker
    if currentActorID == 0x19 and GAME_VERSION ~= 2 then goto continue end

    currentActorRadius = read8(LABELS.Data_Actor_radius + currentActorID - 1)
    currentActorPosX = read8(LABELS.Actor_px + actorIndex)
    currentActorScreenPosY = (read8(LABELS.Actor_py + actorIndex) - currentScrollY + 0x100) % 0x100

    local hitboxTopLeftX = currentActorPosX - currentActorRadius
    local hitboxTopLeftY = currentActorScreenPosY - currentActorRadius

    emu.drawRectangle(
      hitboxTopLeftX,
      hitboxTopLeftY,
      currentActorRadius * 2,
      currentActorRadius * 2,
      HITBOX_COLOR,
      true
    )

    if SHOW_ACTOR_ID then
      emu.drawString(
        hitboxTopLeftX,
        hitboxTopLeftY - 8,
        string.format('%X', actorIndex),
        0x7FFFFFFF,
        0xFF000000
      )
    end

    ::continue::
  end

  if not SHOW_TILE_HITBOXES then return end

  -- scan Map_map for any Tile8 of ID $01 (invisible saw hitbox) or $02 (lava/water/acid hitbox)
  
  local currentWorld = read8(LABELS.Map_worldDigit)
  local worldTilesetAddress = read16(LABELS.Data_Tileset_addrs + currentWorld*2)
  local worldTilesetQuadrantSize = read8(worldTilesetAddress)
  
  for i = 0, 0xFF do
    local currentTile16 = read8(LABELS.Map_map + i)
    local currentTile8

    for j = 0, 3 do
      if GAME_VERSION == 2 then -- Micro Mages Maker handles metatile tables in cartridge RAM, combining shared tile data with the selected world's tile data
        currentTile8 = read8(0x6000 + (j << 8) + currentTile16)
        if tableFind(MAKER_LAVA_TILES, currentTile8) > 0 then currentTile8 = 0x02 end
      else
        if currentTile16 < SHARED_META16_SIZE then  -- shared tile table
          quadrantAddress = read16(LABELS.Map_SHARED__TILE16__ADDRS + (j * 2))
          currentTile8 = read8(quadrantAddress + currentTile16)
        else -- world-specific tile table
          quadrantAddress = (worldTilesetAddress + 2 + (worldTilesetQuadrantSize * j))
          currentTile8 = read8(quadrantAddress + currentTile16 - SHARED_META16_SIZE)
        end
      end

      if currentTile8 == 0x01 or currentTile8 == 0x02 then
        currentTileX = ((i & 0x0F) << 4) | ((j & 1) << 3)
        currentTileY = (i & 0xF0) | ((j & 2) << 2)
        currentTileY = (currentTileY - currentScrollY + 0x100) % 0x100
        
        local drawPosX = 3
        local drawPosY = 5
        local drawWidth = 1
        local drawHeight = 1
        
        if EXTEND_TILE_HITBOXES then
          if currentTile8 == 0x01 then -- saws
            drawPosX, drawPosY, drawWidth, drawHeight = table.unpack(SAW_HITBOX_EXTEND[j+1])
          else -- lava
            drawPosX, drawWidth = table.unpack(LAVA_HITBOX_EXTEND[j+1])
            drawHeight = 2    --extend further down than actual hitbox for clarity
          end
        end

        -- micro mages maker raised lava hitboxes by two pixels
        if currentTile8 == 0x02 and GAME_VERSION == 2 then drawPosY = drawPosY - 2 end
        
        emu.drawRectangle(
          currentTileX + drawPosX,
          currentTileY + drawPosY,
          drawWidth,
          drawHeight,
          HITBOX_COLOR, 
          true
        )
      end
    end
  end
end

emu.addEventCallback(startFrame, emu.eventType.startFrame)
