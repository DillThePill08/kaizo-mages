--display mode
--0 - hex values (80.9D)
--1 - decimal values (128.157)
--2 - decimal with corrected fractions (128.613) 
local DISPLAY_MODE = 0

local TEXT_POS_X = 0
local TEXT_POS_Y = 8

-----------------------------------

--all three versions of the micro mages engine use the same addresses luckily

LABELS = {
  0x4A, -- Actor_px
  0x220, -- Actor_pxFrac
  0x360, -- Actor_py
  0x240, -- Actor_py
  0x260, -- Actor_vx
  0x280, -- Actor_vxFrac
  0x2A0, -- Actor_vy
  0x2C0, -- Actor_vyFrac
}

local HEX_CHARS = {'0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F'}
function toHexByte(v)
  return HEX_CHARS[AND(bit.rshift(v, 4), 0xF) + 1]..HEX_CHARS[AND(v, 0xF) + 1]
end

function read8(address)
  return memory.readbyte(address)
end


--treat hi as the whole number and lo as its decimal
--and sign if necessary 
function formatByteFrac(hi, lo, signed)
  local word = OR(bit.lshift(hi, 8), lo)
  local sign = ''
  if AND(hi, 0x80) ~= 0 and signed then
    word = XOR(word, 0xFFFF) + 1
    sign = '-'
  end
  
  if DISPLAY_MODE == 0 then --hex values
    return sign..toHexByte(bit.rshift(word, 8))..'.'..toHexByte(AND(word, 0xFF))
  elseif DISPLAY_MODE == 1 then --decimal values
    return sign..bit.rshift(word, 8)..'.'..AND(word, 0xFF)
  else  --decimals with correct fractions
    local decimalNum = bit.rshift(word, 8) + AND(word, 0xFF)/0x100 
    return sign..math.floor(decimalNum*1000)/1000
  end
end

function endFrame()
  local memValues = {}
  for i, v in ipairs(LABELS) do
    table.insert(memValues, read8(v))
  end
  local posX, subPosX, posY, subPosY, velX, subVelX, velY, subVelY = unpack(memValues)
  
  gui.text(TEXT_POS_X, TEXT_POS_Y, "pos x: "..formatByteFrac(posX, subPosX, false))
  gui.text(TEXT_POS_X, TEXT_POS_Y+8, "pos y: "..formatByteFrac(posY, subPosY, false))
  gui.text(TEXT_POS_X, TEXT_POS_Y+8+12, 'vel x: '..formatByteFrac(velX, subVelX, true))
  gui.text(TEXT_POS_X, TEXT_POS_Y+8+12+8, 'vel y: '..formatByteFrac(velY, subVelY, true))
end

emu.registerafter(endFrame)