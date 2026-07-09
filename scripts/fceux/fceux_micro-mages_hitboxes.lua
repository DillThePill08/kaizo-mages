local HITBOX_COLOR = 0xFF0000BF
local SHOW_ACTOR_ID = false			--display an actor's index above the hitbox
local SHOW_TILE_HITBOXES = true	   --show hitboxes from tiles $02 and $03 (saws and lava)
local EXTEND_TILE_HITBOXES = true    --combine single pixel hitboxes to something more visible and expected

----------------------------------
-- determine memory addresses by game version
-- determine game version by file hash
local ROM_MD5 = rom.gethash("md5")

local LABELS = {}
local GAME_VERSION = 0

local RADIUS_TABLE_SIZE = 0x3B

if ROM_MD5 == "d41d114a45fa20eb5519fded279020be" then
  emu.print("Detected game: Micro Mages 2019")
  LABELS.Map_worldDigit = 0xBD
  LABELS.Map_scrollY = 0xCC
  LABELS.Actor_px = 0x4A
  LABELS.Actor_py = 0x360
  LABELS.Actor_id = 0x200
  LABELS.Map_map = 0x600

  LABELS.Data_Actor_radius = 0xBEFA
  LABELS.Data_Tileset_addrs = 0xAF10
  LABELS.Map_SHARED__TILE16__ADDRS = 0xF883

elseif ROM_MD5 == "8dab6d7f69a7db72684ef296f3a4b5d4" then --NES 2.0
  emu.print("Detected game: Micro Mages Second Quest")
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
  emu.print("Detected game: Micro Mages Custom Quest (v1.0.8)")
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
  return memory.readbyte(address)
end

function read16(address)
  return memory.readword(address)
end

function tableFind(haystack, needle)
  for i = 1, #haystack do
    if haystack[i] == needle then return i end
  end
  return 0
end

function drawRectangle(x, y, width, height, color)
  gui.rect(x-1, y-1, x+width, y+height, color, 0)
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

  for actorIndex = 0, ACTOR_TABLE_SIZE - 1 do
    currentActorID = read8(LABELS.Actor_id + actorIndex)
    local continue = false

    if currentActorID == 0 or currentActorID > RADIUS_TABLE_SIZE then continue = true end

    --saw hitbox ineffective unless on Micro Mages Maker
    if currentActorID == 0x19 and GAME_VERSION ~= 2 then continue = true end

    if not continue then
      currentActorRadius = read8(LABELS.Data_Actor_radius + currentActorID - 1)
      currentActorPosX = read8(LABELS.Actor_px + actorIndex)
      currentActorScreenPosY = (read8(LABELS.Actor_py + actorIndex) - currentScrollY + 0x100) % 0x100

      local hitboxTopLeftX = currentActorPosX - currentActorRadius
      local hitboxTopLeftY = currentActorScreenPosY - currentActorRadius

      drawRectangle(
        hitboxTopLeftX,
        hitboxTopLeftY,
        currentActorRadius * 2,
        currentActorRadius * 2,
        HITBOX_COLOR
      )

      if SHOW_ACTOR_ID then
        gui.text(
          hitboxTopLeftX,
          hitboxTopLeftY - 8,
          string.format('%X', actorIndex),
          0xFFFFFF7F,
          0
        )
      end
    end
    --::continue::
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
        currentTile8 = read8(0x6000 + bit.lshift(j, 8) + currentTile16)
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
        currentTileX = OR(bit.lshift(AND(i, 0x0F), 4), bit.lshift(AND(j, 1), 3))
        currentTileY = OR((AND(i, 0xF0)), bit.lshift(AND(j, 2), 2))
        currentTileY = (currentTileY - currentScrollY + 0x100) % 0x100
        
        local drawPosX = 3
        local drawPosY = 5
        local drawWidth = 1
        local drawHeight = 1
        
        -- micro mages maker raised lava hitboxes by two pixels
        if currentTile8 == 0x02 and GAME_VERSION == 2 then drawPosY = drawPosY - 2 end


        if EXTEND_TILE_HITBOXES then
          if currentTile8 == 0x01 then -- saws
            drawPosX =   SAW_HITBOX_EXTEND[j+1][1]
            drawPosY =   SAW_HITBOX_EXTEND[j+1][2]
            drawWidth =  SAW_HITBOX_EXTEND[j+1][3]
            drawHeight = SAW_HITBOX_EXTEND[j+1][4]
          else -- lava
            drawPosX =  LAVA_HITBOX_EXTEND[j+1][1]
            drawWidth = LAVA_HITBOX_EXTEND[j+1][2]
            drawHeight = 2    --extend further down than actual hitbox for clarity
          end
        end
        
        drawRectangle(
          currentTileX + drawPosX,
          currentTileY + drawPosY,
          drawWidth,
          drawHeight,
          HITBOX_COLOR
        )
      end
    end
  end
end

emu.registerbefore(startFrame)