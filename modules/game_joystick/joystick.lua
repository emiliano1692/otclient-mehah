local overlay
local keypad
local keypadUpdateEvent
local keypadMousePos = { x = 0.5, y = 0.5 }
local firstStep = true
local moveListener

-- Estado exclusivo do gesto do joystick.
-- Nunca use g_mouse.isPressed(), pois esse estado é global e também fica
-- ativo quando outro dedo pressiona uma hotkey.
local joystickTouchId = nil
local joystickPressed = false

local function resetJoystick()
  joystickPressed = false
  joystickTouchId = nil
  firstStep = false

  if keypadUpdateEvent then
    removeEvent(keypadUpdateEvent)
    keypadUpdateEvent = nil
  end

  if keypad and keypad.pointer then
    keypad.pointer:setMarginTop(0)
    keypad.pointer:setMarginLeft(0)
  end
end

local function getTouchId(buttonOrTouchId, explicitTouchId)
  -- Compatível com forks que enviam o ID como quarto argumento e com forks
  -- que o enviam como terceiro argumento nos callbacks onTouch*.
  if explicitTouchId ~= nil then
    return explicitTouchId
  end
  if type(buttonOrTouchId) == 'number' then
    return buttonOrTouchId
  end
  return nil
end

local function getKeypadPosition(widget, pos)
  return {
    x = (pos.x - widget:getPosition().x) / widget:getWidth(),
    y = (pos.y - widget:getPosition().y) / widget:getHeight()
  }
end

function init()
  if not g_platform.isMobile() then return end

  overlay = g_ui.displayUI('joystick')
  keypad = overlay.keypad

  connect(keypad, {
    onTouchPress = onKeypadTouchPress,
    onTouchRelease = onKeypadTouchRelease,
    onTouchMove = onKeypadTouchMove
  })

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })
end

function terminate()
  if not g_platform.isMobile() then return end

  resetJoystick()

  disconnect(keypad, {
    onTouchPress = onKeypadTouchPress,
    onTouchRelease = onKeypadTouchRelease,
    onTouchMove = onKeypadTouchMove
  })

  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  overlay:destroy()
  overlay = nil
  keypad = nil
end

function hide()
  resetJoystick()
  if overlay then overlay:hide() end
end

function show()
  if overlay then overlay:show() end
end

function onGameStart()
  if keypad then
    keypad:raise()
    keypad:show()
  end
end

function onGameEnd()
  resetJoystick()
  if keypad then keypad:hide() end
end

function addOnJoystickMoveListener(callback)
  moveListener = callback
end

-- Pressionar um segundo dedo em uma hotkey não cancela este gesto. O native
-- UIManager precisa encaminhar cada pointerId para o widget que recebeu o
-- respectivo press.
function onKeypadTouchPress(widget, pos, buttonOrTouchId, explicitTouchId)
  local touchId = getTouchId(buttonOrTouchId, explicitTouchId)

  -- Se o fork envia botão, aceite apenas o toque esquerdo.
  if type(buttonOrTouchId) ~= 'number' and buttonOrTouchId ~= nil and buttonOrTouchId ~= MouseLeftButton then
    return false
  end

  -- Um joystick aceita somente um dedo; os demais ficam livres para hotkeys.
  if joystickPressed then
    return false
  end

  joystickPressed = true
  joystickTouchId = touchId
  keypadMousePos = getKeypadPosition(widget, pos)
  firstStep = true
  executeWalk()
  return true
end

function onKeypadTouchMove(widget, pos, buttonOrTouchId, explicitTouchId)
  local touchId = getTouchId(buttonOrTouchId, explicitTouchId)

  if not joystickPressed then
    return false
  end

  -- Se o native fornece IDs, somente o dedo que iniciou o joystick pode
  -- atualizar sua posição. Sem ID, usa o estado legado de um único gesto.
  if joystickTouchId ~= nil and touchId ~= joystickTouchId then
    return false
  end

  keypadMousePos = getKeypadPosition(widget, pos)
  return true
end

function onKeypadTouchRelease(widget, pos, buttonOrTouchId, explicitTouchId)
  local touchId = getTouchId(buttonOrTouchId, explicitTouchId)

  if type(buttonOrTouchId) ~= 'number' and buttonOrTouchId ~= nil and buttonOrTouchId ~= MouseLeftButton then
    return false
  end

  if not joystickPressed then
    return false
  end

  if joystickTouchId ~= nil and touchId ~= joystickTouchId then
    return false
  end

  -- O release do dedo proprietário sempre limpa ID, evento e ponteiro.
  resetJoystick()
  return true
end

function executeWalk()
  if keypadUpdateEvent then
    removeEvent(keypadUpdateEvent)
    keypadUpdateEvent = nil
  end

  -- Não consulte g_mouse.isPressed(): outro dedo pode estar usando uma hotkey.
  if not joystickPressed then
    resetJoystick()
    return
  end

  keypadUpdateEvent = scheduleEvent(executeWalk, 20)

  keypadMousePos.x = math.min(1, math.max(0, keypadMousePos.x))
  keypadMousePos.y = math.min(1, math.max(0, keypadMousePos.y))

  local angle = math.atan2(keypadMousePos.x - 0.5, keypadMousePos.y - 0.5)
  local maxTop = math.abs(math.cos(angle)) * 75
  local marginTop = math.max(-maxTop, math.min(maxTop, (keypadMousePos.y - 0.5) * 150))
  local maxLeft = math.abs(math.sin(angle)) * 75
  local marginLeft = math.max(-maxLeft, math.min(maxLeft, (keypadMousePos.x - 0.5) * 150))

  keypad.pointer:setMarginTop(marginTop)
  keypad.pointer:setMarginLeft(marginLeft)

  local dir
  if keypadMousePos.y < 0.3 and keypadMousePos.x < 0.3 then
    dir = Directions.NorthWest
  elseif keypadMousePos.y < 0.3 and keypadMousePos.x > 0.7 then
    dir = Directions.NorthEast
  elseif keypadMousePos.y > 0.7 and keypadMousePos.x < 0.3 then
    dir = Directions.SouthWest
  elseif keypadMousePos.y > 0.7 and keypadMousePos.x > 0.7 then
    dir = Directions.SouthEast
  end

  if not dir and (math.abs(keypadMousePos.y - 0.5) > 0.1 or math.abs(keypadMousePos.x - 0.5) > 0.1) then
    if math.abs(keypadMousePos.y - 0.5) > math.abs(keypadMousePos.x - 0.5) then
      dir = keypadMousePos.y < 0.5 and Directions.North or Directions.South
    else
      dir = keypadMousePos.x < 0.5 and Directions.West or Directions.East
    end
  end

  if dir and moveListener then
    moveListener(dir, firstStep)
    firstStep = false
  end
end

function getPanel()
  return keypad
end
