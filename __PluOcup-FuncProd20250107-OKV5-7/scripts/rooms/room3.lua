---@diagnostic disable: param-type-mismatch
--    module require
local _core = require("core")
local _logger = require("logging")
local _timer = require("timer")
local _json = require("json")
local _storage = require("storage")
local params = ... or {}

---- Función para registrar mensajes
local function Registro(Mensaje, color)
    local prefix = "[Horus Smart] - " --"[Horus Desarrollo] Energy"
    if color then
        _logger.info(prefix .. "\27[" .. color .. "m" .. Mensaje .. "\27[0m")
    else
        _logger.info(prefix .. Mensaje)
    end
end

--    variable locales
local rojo = 31
local verde = 32
local amarillo = 33

local ACCION_SCAN = 10
local ACCION_LIBRE = 0
local ACCION_OCUPADO = 100
local ACCION_PABIERTA = 40
local ACCION_CICLO_APAGADO = 60

local MODO_APAGADO = "Apagado"
local MODO_AUTO = "Auto"

local PreOffAireDoor = "si"

local thermostat = _storage.get_table("TERMOSTATO_M3")
local SetPointOn = _storage.get_number("SETPOINTON_M3")
local SetPointOff = _storage.get_number("SETPOINTOFF_M3")
local sensor_puerta = _storage.get_string("SENSOR_PUERTA_M3")
local SensorMovbatt = _storage.get_table("SENSOR_MOV_BATT_M3")
local SensorMovElec = _storage.get_table("SENSOR_MOV_ELEC_M3")
local devicesOn = _storage.get_table("ACTUADORES_ON_M3") or {}
local devicesOff = _storage.get_table("ACTUADORES_OFF_M3") or {}
local masterSwitch = _storage.get_table("MASTERSWITCH_ON_M3") or {}
local ModoSetpoint = _storage.get_string("MODOSETPOINT_M3") or false
local ModoDispLuces = _storage.get_string("MODODISPLUCES_M3") or false
local ModoThermoInit = _storage.get_string("MOTIONACTIVATOR_M3") or false
local ModoMasterSwitch = _storage.get_string("MODOMASTERSWITCH_M3") or false
local ModoOffPuertaAbierta = _storage.get_string("OFFPUERTAABIERTA_M3") or false

local ModoPluginStatus = _storage.get_string("ModoId3")
local AccionPluginStatus = _storage.get_string("AccionTextoId3")
local EstadoPluginStatus = _storage.get_string("EstadoTextoId3")
local modeButton = (_core.get_item(ModoPluginStatus))

local data = {}
data.modo = _storage.get_string("Modo3")
data.type = _storage.get_string("type3")
data.accion = _storage.get_number("accion3")
data.TimerID = _storage.get_string("TimerID3")
data.counting = _storage.get_string("Counting3")
data.scancycle = _storage.get_string("scanCycle3")
data.remaining = _storage.get_string("remaining3")
data.statustext = _storage.get_string("statusText3")
data.acciontext = _storage.get_string("accionTexto3")
data.timeraccion = _storage.get_string("timerAccion3")
data.TimerIdTick = _storage.get_string("TimerIdTick3")
data.dueTimestamp = _storage.get_number("dueTimestamp3")
data.timerduration = _storage.get_number("TimerDuration3")
data.Remaining_ant = _storage.get_number("Remaining_ant3")
data.previousTimer = _storage.get_number("previousTimer3")
data.settingAccionId = _storage.get_string("settinAccion3")

--    Tiempos del Plugin Ocupación
local Tiempo_ocupacion = 600    -- (600 * 2) Tiempo total 1200 = 20 minutos
local Tiempo_apagado = 30       -- 10 seg PRODUCCIÓN // se cambia a 30 por error de apagado
local TiempoScanH = 910         -- (30min) libre a scan por sensor movimiento actual: 900+10 seg PRODUCCIÓN
local TiempoLibre = 10          -- 10 seg PRODUCCIÓN

local TiempoScaner = math.floor((_storage.get_number("TIEMPOSCAN_M3"))/2) -- tiempo a la mitad ejecurar los tiempo del programa
local TiempoSenMov =  math.abs(Tiempo_ocupacion-TiempoScaner)             -- Tiempo Real del sensor movimiento parcial
local TiempoScanerLibre = TiempoScaner * 0.2                              -- Tiempo Real de escaner a libre
local TiempoScanLibre = TiempoScanerLibre - Tiempo_apagado - TiempoLibre  -- Tiempo Tomado como Scaner Libre

local Tiempo1 = Tiempo_ocupacion - TiempoScanLibre                        -- Tiempo siguiente al sensor movimiento
local Tiempo2 = TiempoScanLibre                                           -- Ciclo Scan 2 (-Tiempo1)

local umbralTime1 = 0                   -- Luego usado para ecuaciones    
local umbralTime2 = TiempoSenMov + 30   -- Tiempo de sensado _scan1 -- pruebas 35
local umbralTime3 = TiempoSenMov + 30   -- Tiempo sensado PuertaAbierta  -- pruebas 35
local umbralTime4 = 300                 -- 10 min - (305 * 2)+5 - Tiempo de sensado PuertaAbierta Min 10 -- pruebas 25

Registro("----------------------------------")
Registro("Manejo de Tiempos Reales/2 Plg3: ",verde)
Registro("Tiempo plg Tt: ".. ((TiempoSenMov + TiempoScaner)).."   |-| Tiempo Sensor Movimiento " .. (TiempoSenMov))
Registro("Tiempo Scaner: ".. (Tiempo1).." |-| Tiempo Scaner Libre: ".. (Tiempo2))
Registro("Tiempo Scan min: ".. umbralTime2 .. " |-| Tiempo Scan min 10: " .. umbralTime4)
if ModoMasterSwitch and ModoDispLuces ~= nil then
Registro( "Modo Disp Luces: " .. ModoDispLuces .. "  |-| Modo Master Swiches: ".. ModoMasterSwitch.. " |-| Modo Thermostat: " ..ModoThermoInit)
end
Registro("----------------------------------")

local function setItemValue(itemId, value)
    local success, result = xpcall(
        function()
            return _core.set_item_value(itemId, value)
        end,
        function(err)
            Registro("Error al establecer el valor del ítem " .. itemId .. ": " .. (err or "Error desconocido"), rojo)
            return err -- Importante: devolver el error para xpcall
        end
    )
    if not success then
        Registro("Error en el manejador de errores para " .. itemId .. ": " .. (result or "Error desconocido"), rojo)
    else
        Registro("Estado del sistema: " .. _json.encode(value)) -- "device: " .. itemId .. 
    end
end

---- estasdos del plugin (libre, Ocupado)
function Libre()
    Rutina_Apagado()
    CancelTimer()
    Registro("funcion Libre", verde)
    ActualizarAccion(ACCION_LIBRE)
    Validar("timerAccion3", "Libre")
    StartTimer(TiempoLibre)
end
function Occupied()
    Registro("funcion ocupado", verde)
    CancelTimer()
    ActualizarAccion(ACCION_OCUPADO)
    Validar("timerAccion3", "Ocupado")
    Validar("scanCycle3", "Ocupado")
    Rutina_Encendido()
end

-- Funciones Actuadores Dispositivos
function ShutdownActuator(item_id)
    Registro(" evento apagado de actuadores", verde)
    local actuadores_on
    for i in ipairs(item_id) do
        actuadores_on = _core.get_item(item_id[i])
        -- _logger.info("id_actuadores: " .. actuadores_on.name)
        -- _logger.info("id_actuadores: " .. actuadores_on.id)
        Registro("id_actuadores: "..actuadores_on.name.." - Id: "..actuadores_on.id)
        _core.set_item_value(item_id[i], false)
    end
end
function PowerOnActuator(item_id)
    Registro("evento Encendido de actuadores", verde)
    local actuadores_on
    for i in ipairs(item_id) do
        actuadores_on = _core.get_item(item_id[i])
        -- _logger.info("id_actuadores: " .. actuadores_on.name)
        -- _logger.info("id_actuadores: " .. actuadores_on.id)
        Registro("id_actuadores: "..actuadores_on.name.." - Id: "..actuadores_on.id)
        _core.set_item_value(item_id[i], true)
    end
end

function ThermostatPower(item_id, value)
    
    _core.set_item_value(item_id, value)
    _timer.set_timeout(2000, "HUB:plg.plugin_ocupacion/scripts/rooms/thermostat",
    { itemId = item_id, itemValue = value })
end
function SetPointTermostato(item_id, value)
    Registro("Thermostat: " .. thermostat.mode.name .. ": " .. thermostat.setpoint._id, rojo)
    _timer.set_timeout(2000, "HUB:plg.plugin_ocupacion/scripts/rooms/thermostat",
    { itemId = item_id, itemValue = value })
end
function SetFanTermostato(item_id, value)
    Registro("Thermostat: " .. thermostat.mode.name .. ": " .. thermostat.setpoint._id, amarillo)
    _timer.set_timeout(2000, "HUB:plg.plugin_ocupacion/scripts/rooms/thermostat",
    { itemId = item_id, itemValue = value })
end

---- funcion de Rutinas de acciones de encendido y apagado Luces - Thermo y Enc Total/Apag Total
function RoutineOnLuces(item_id)
    local id = {}
    local mode = _storage.get_string("Modo3")
        if mode == MODO_AUTO then
            if ModoDispLuces == "si" or ModoMasterSwitch == "si" then 
                for i in ipairs(item_id) do
                    id = _core.get_item(item_id[i])
                end
                _logger.info("valor de los dispositivos: " .. tostring(id.value))
                if id.value ~= true then
                    PowerOnActuator(item_id)
                end
                return
            end
        end
        if mode ~= MODO_AUTO then
            for i in ipairs(item_id) do
                id = _core.get_item(item_id[i])
            end
            _logger.info("valor de los dispositivos: " .. tostring(id.value))
            Registro("no se enciende ningun dispositivo", amarillo)
            return
        end
    return false
end
function RoutineOffLuces(item_id)
    local id = {}
    local mode = _storage.get_string("Modo3")
    if mode ~= MODO_APAGADO then
        for i in ipairs(item_id) do
            id = _core.get_item(item_id[i])
        end
        _logger.info("valor de los dispositivos: " .. tostring(id.value))
        if id.value == true then
            ShutdownActuator(item_id)
        else
            ShutdownActuator(item_id)
        end
        return
    end
end

function Rutina_On_Thermo()
    local mode = _storage.get_string("Modo3")
    if data.modo == "Auto" then
        if thermostat ~= nil and ModoThermoInit == "si" then
            Registro("Thermo On: ",rojo)
                if thermostat.mode.value ~= "cool" then
                    ThermostatPower(thermostat.mode._id, "cool")
                end
                if thermostat.setpoint.value ~= SetPointOn then
                    SetPointTermostato(thermostat.setpoint._id, SetPointOn)
                end
        else
            Registro("no tiene termostato o no está activo modo thermo inicial", amarillo)
        end
    end
    return mode
end
function Rutina_Off_Thermo()
    local mode = _storage.get_string("Modo3")
    if data.modo ~= "Apagado" then
        if thermostat ~= nil then
            if ModoSetpoint == "si" then
                if thermostat.mode.value ~= "cool" then
                    ThermostatPower(thermostat.mode._id, "cool")
                end
                SetPointTermostato(thermostat.setpoint._id, SetPointOff)
                if thermostat.fanMode.value ~= "auto_low" then
                    SetFanTermostato(thermostat.fanMode._id, "auto_low")
                end
            elseif ModoSetpoint == "no" then
                ThermostatPower(thermostat.mode._id, "off")
            end
            Registro("Thermo: Off")
        else
            Registro("no tiene termostato", amarillo)
        end
    end
    return mode
end

function Rutina_Encendido()
    -- local mode = _storage.get_string("Modo3")
    -- Registro("Rurina Encendido Ttal ON")
        if data.modo ~= "Apagado" then
            RoutineOnLuces(masterSwitch)
            RoutineOnLuces(devicesOn)
            Rutina_On_Thermo()
        end
    -- return mode
end
function Rutina_Apagado()
    -- local mode = _storage.get_string("Modo3")
    -- Registro("Rurina Apagado Ttal Off")
    if data.modo ~= "Apagado" then
        RoutineOffLuces(masterSwitch)
        RoutineOffLuces(devicesOff)
        RoutineOffLuces(devicesOn)
        Rutina_Off_Thermo()
    end
end

--- verification and validation functions of the variables
function Validar(variable, newvalue)
    if newvalue == nil then
        Registro("El nuevo valor es nulo para la variable: " .. variable, amarillo)
        return false
    end

    local currentValue
    local updated = false

    if type(newvalue) == "number" then
        currentValue = _storage.get_number(variable)
        if currentValue ~= newvalue then
            _storage.set_number(variable, newvalue)
            updated = true
            --Registro("Número actualizado en storage: " .. variable .. " -> " .. newvalue, amarillo)
        end
    elseif type(newvalue) == "string" then
        currentValue = _storage.get_string(variable)
        if currentValue ~= newvalue then
            _storage.set_string(variable, newvalue)
            --Registro("Cadena actualizada en storage: " .. variable .. " -> " .. newvalue, amarillo)
            updated = true
        end
    else
        Registro("Tipo de dato no soportado para la variable: " .. variable, amarillo)
        return false
    end

    if not updated then
        Registro("No cambio variable: " .. variable, amarillo)
    end

    return updated
end

function VariablesDeInicio(variable, defaultValue)
    local value
    if (type(defaultValue) == "number") then
        value = _storage.get_number(variable)
        if value == nil then
            _storage.set_number(variable, defaultValue)
            value = _storage.get_number(variable)
            return value
        else
            return value
        end
    end
    if (type(defaultValue) == "string") then
        value = _storage.get_string(variable)
        if value == nil then
            Registro("secarga valor por defaul", amarillo)
            _storage.set_string(variable, defaultValue)
            value = _storage.get_string(variable)
            return value
        else
            return value
        end
    end
end

---- Actualiza el estado y los textos asociados según el valor proporcionado.
function ActualizarAccion(s)
    Registro("ActualizarAccion", verde)

    local AccionTextoId = _storage.get_string("AccionTextoId3")
    local EstadoTextoId = _storage.get_string("EstadoTextoId3")
    local curValue = _storage.get_number("accion3")

    if tonumber(s) ~= tonumber(curValue) then
        Registro("curValue: " .. curValue .. ", s: " .. s, amarillo)
        -- Actualiza la acción según el valor proporcionado
        Validar("accion3", s)
        
        -- Mapeo de valores de acción a textos asociados.
        local textMapping = {
            [ACCION_LIBRE] = "Libre",
            [ACCION_PABIERTA] = "Puerta Abierta",
            [ACCION_SCAN] = "Scan",
            [ACCION_OCUPADO] = "Ocupado"
        }

        -- Obtiene el texto asociado al valor de acción actual.
        local accionText = textMapping[s]

        -- Si hay un texto asociado, actualiza el texto correspondiente.
        if accionText then
            Validar("accionTexto3", accionText)
            setItemValue(AccionTextoId, accionText)
        end
    end

    -- Verifica el valor de acción para actualizar el estado general
    if tonumber(s) ~= -2 then
        local statusText = tonumber(s) == 0 and "Libre" or "Ocupado"

        Validar("statusText3", statusText)
        setItemValue(EstadoTextoId, statusText)
    end

    return true
end

---- Eventos del plugin(puerta, Puerta Abierta Libre, movimineto, )
function EventoPuerta()
    Registro("Evento Puerta ", amarillo)
    local EstadoAccioPlg = _json.encode(data.scancycle)
    local SensorPuerta = _core.get_item(sensor_puerta)
    if SensorPuerta.value == true then
        if _storage.get_number("accion3") == ACCION_LIBRE  or  _storage.get_number("accion3") == ACCION_CICLO_APAGADO then
            Rutina_Encendido()
        end
        CancelTimer()
        ActualizarAccion(ACCION_PABIERTA)
        Validar("timerAccion3", "PrePuertAbiert")
        Validar("scanCycle3", "PrePuertAbiert")
        StartTimer(Tiempo1)
        return true
    end
    if SensorPuerta.value == false then
        if _storage.get_number("accion3") == ACCION_PABIERTA or _storage.get_number("accion3") == ACCION_LIBRE then
            if _storage.get_string("statusText3") == "Libre" then
                Rutina_Encendido()
            end
            CancelTimer()
            ActualizarAccion(ACCION_SCAN)
            Validar("timerAccion3", "Scan")
            Validar("scanCycle3", "scan_One")
            StartTimer(Tiempo1)
            return true
        else
            CancelTimer()
            ActualizarAccion(ACCION_SCAN)
            Validar("timerAccion3", "Scan")
            Validar("scanCycle3", "scan_One")
            StartTimer(Tiempo1)
            return true
        end
    end
end

--Evento Scan por Sensor Mov = On >> Ocupado
function EventTimeMin()
    Registro("Inicio Evento Tiempo Mínimo", rojo)

    local function ProcSensMov(sensoresMovimiento, grupo)
        if sensoresMovimiento ~= nil then
            Registro("Procesando sensores de movimiento del grupo: " .. grupo, amarillo)
            for i in pairs(sensoresMovimiento) do
                Registro("Procesando sensor " .. tostring(i) .. " del grupo: " .. grupo)
                local sensor = _core.get_item(sensoresMovimiento[i])

                if sensor and sensor.value ~= nil then
                    if sensor.value == true then -- Evento cuando el sensor está activo
                        Registro("Evento TimeMin - ON - min 5 (Grupo: " .. grupo .. ")", amarillo)
                        if _storage.get_number("accion3") == ACCION_SCAN then
                            CancelTimer()
                            ActualizarAccion(ACCION_OCUPADO)
                            Validar("timerAccion3", "Ocupado")
                            Validar("scanCycle3", "Ocupado")
                            Registro("Estado Ocupado activado (5 min SM, Grupo: " .. grupo .. ")", verde)
                            return
                        end
                    end
                    if sensor.value == false then -- Evento cuando el sensor está inactivo
                        Registro("Transición detectada: Puerta abierta y sensor inactivo (Grupo: " .. grupo .. ")", verde)
                        if _storage.get_number("accion3") == ACCION_PABIERTA then
                            if ModoOffPuertaAbierta == "si" then
                                Registro("Acción PABIERTA: Termostato Off (Grupo: " .. grupo .. ")", verde)
                                Rutina_Off_Thermo()
                                RoutineOffLuces(masterSwitch)
                            end
                        end
                    end
                else
                    Registro("Advertencia: Sensor inválido o no encontrado (Grupo: " .. grupo .. ", Sensor ID: " .. tostring(sensoresMovimiento[i]) .. ")", rojo)
                end
            end
        else
            Registro("se escluyó sensor tipo: " .. grupo, rojo)
        end
    end

    -- Procesar ambos grupos de sensores de movimiento
    ProcSensMov(SensorMovbatt, "SensorMovbatt")
    ProcSensMov(SensorMovElec, "SensorMovElec")
end

function EventMovimiento(Sensor)
    Registro("Evento de movimiento", amarillo)
    local motion = _storage.get_string("motion3")
    if Sensor ~= nil then
        Registro("sensor: " .. _json.encode(Sensor), amarillo)
        for i in ipairs(Sensor) do -- Rutina FOR : conocer estado de SM
            local sensor_id = _core.get_item(Sensor[i])
            if sensor_id.value == true then
                local tiempoRestante3 = Tiempo1 - math.abs(data.previousTimer or 0)
                Registro("time Restante: " .. tiempoRestante3)
                if motion ~= nil then -- Conocer estado de SM
                    local securityThreat = _storage.get_string("securityThreat3")
                    setItemValue(motion, true)
                    setItemValue(securityThreat, true)
                end

                if _storage.get_number("accion3") == ACCION_SCAN then
                    Registro("Evento Scan >>> Ocupado por movimiento",rojo)
                    CancelTimer()
                    ActualizarAccion(ACCION_OCUPADO)
                    Validar("timerAccion3", "Ocupado")
                    Validar("scanCycle3", "Ocupado")
                    Registro("se paso al la accion 3 ocupado por disparo del sensor de movimiento", verde)
                    return
                end

                if _storage.get_number("accion3") == ACCION_LIBRE then
                    Registro("Evento Libre >>> Scan por movimiento ",rojo)
                    if data.modo == "Auto" then
                        Rutina_On_Thermo()
                        RoutineOnLuces(masterSwitch)
                    end
                    CancelTimer()
                    ActualizarAccion(ACCION_SCAN)
                    Validar("timerAccion3", "Scan")
                    Validar("scanCycle3", "scan_Two")
                    StartTimer(TiempoScanH)
                end

                if _storage.get_number("accion3") == ACCION_PABIERTA then
                    Registro("Sensor Mov not Funt -- Puerta Abierta")
                    return
                end

                if _storage.get_number("accion3") == ACCION_CICLO_APAGADO then
                    CancelTimer()
                    ActualizarAccion(ACCION_OCUPADO)
                    Validar("timerAccion3","Ocupado")
                    Validar("scanCycle3", "Ocupado")
                    if PreOffAireDoor == "si" then
                        Registro("on actuadores", amarillo)
                        RoutineOnLuces(masterSwitch)
                        RoutineOnLuces(devicesOn)
                        Rutina_On_Thermo()
                    end
                    return
                end
            end
            if sensor_id.value == false then
                if motion ~= nil then
                    local securityThreat = _storage.get_string("securityThreat3")
                    setItemValue(motion, false)
                    setItemValue(securityThreat, false)
                end
            end
        end
    end
end

function EventoMovDeLibre()
    CancelTimer()
    ActualizarAccion(ACCION_CICLO_APAGADO)
    Validar("timerAccion3", "CicloApagado")
    Validar("scanCycle3", "CicloApagado")
    Registro("Tiempo_apagado: " .. Tiempo_apagado, amarillo)
    StartTimer(Tiempo_apagado)
    CicloApagado()
end

-- evento dado por accionamiento de movimiento y swiches
function EventoActuadores(Actuador)
    Registro("_______ evento de Actuadores_______", amarillo)
    if not Actuador then return end

    local tiempoRestante3 = Tiempo1 - math.abs(data.previousTimer or 0)
    Registro("time Restante: " .. tiempoRestante3)

    Registro("Divice : " .. _json.encode(Actuador), amarillo)

    for _, id in ipairs(Actuador) do
        local actuador_id = _core.get_item(id)
        Registro("value Actuador: " .. _json.encode(actuador_id.value) .. ", " .. _json.encode(data.modo))

        if actuador_id.value == true then
            if not data.scancycle or (data.scancycle == "Libre") then
                RoutineOnLuces(masterSwitch)
                RoutineOnLuces(devicesOn)
                Rutina_On_Thermo()

                CancelTimer()
                ActualizarAccion(ACCION_OCUPADO)
                Validar("timerAccion3", "Ocupado")
                Validar("scanCycle3", "Ocupado")
                Registro("Pasa a accion 3 OCUPADO por disparo de Actuador true", amarillo)
                return
            end

            -- formula para evitar ocupado al encender Actuadores ON
            if (tiempoRestante3 >= 20 and (data.scancycle == "scan_One" or data.scancycle == "scan_Two" or data.scancycle == "scan_Libre")) then
                Registro("Puerta Abierta Scan Libre")
                if _storage.get_number("accion3") == ACCION_CICLO_APAGADO and PreOffAireDoor == "si" then
                    Registro("on actuadores", amarillo)
                    Rutina_Encendido()
                end
                CancelTimer()
                ActualizarAccion(ACCION_OCUPADO)
                Validar("timerAccion3", "Ocupado")
                Validar("scanCycle3", "Ocupado")
                Registro("se paso a accion3 OCUPADO por disparo de Actuador", verde)
                return
            end
        end
    end
    return true
end

function FunPuertaAbierta()
    CancelTimer()
    ActualizarAccion(ACCION_PABIERTA)
    Validar("timerAccion3", "PuertaAbierta")
    Validar("scanCycle3", "PuertaAbierta")
    Registro("Puerta Abierta: " .. Tiempo2, amarillo)
    StartTimer(Tiempo2)
end

function PuertaAbiertaLibre()
    Registro("prueta Abrierta >> Libre",rojo)
    local contador, contadorDisparos, contadorLibres = 0, 0, 0
    local EstadoTextoId = _storage.get_string("EstadoTextoId3")

    local function contarSensores(sensores)
        if sensores ~= nil then
            for _, sensor in ipairs(sensores) do
                contador = contador + 1
                local sensor_id = _core.get_item(sensor)
                if sensor_id.value == true then
                    contadorDisparos = contadorDisparos + 1
                else
                    contadorLibres = contadorLibres + 1
                end
            end
        end
    end
    
    contarSensores(SensorMovbatt)
    contarSensores(SensorMovElec)
    
    if contador == contadorLibres then        
        Registro("prueta Abrierta + SM==OFF >> Libre",rojo)
        CancelTimer()
        ActualizarAccion(ACCION_LIBRE)
        Validar("statusText3", "Libre")
        Validar("timerAccion3", "Libre")
        setItemValue(EstadoTextoId,"Libre")
        StartTimer(TiempoLibre)

        -- rutina Comentada // Investigar con la org
        if _storage.get_string("Modo3") ~= MODO_APAGADO then
            if ModoOffPuertaAbierta == "si" then
                Rutina_Apagado()
            end
        end
    end
    return true
end

function SMpuertaAb()
    Registro("Inicio de Funcion SMpuertaAb")
    local function ProcSensMov(sensoresMovimiento)
        if sensoresMovimiento ~= nil then
            for i in pairs(sensoresMovimiento) do   
                local sensor = _core.get_item(sensoresMovimiento[i])
                if sensor.value == true then
                    Registro("Evento TimeMin - ON - min 10 ", amarillo)
                    if _storage.get_number("accion3") == ACCION_PABIERTA then
                        CancelTimer()
                        ActualizarAccion(ACCION_PABIERTA)
                        Validar("timerAccion3", "PrePuertAbiert")
                        Validar("scanCycle3", "PrePuertAbiert")
                        StartTimer(Tiempo1)
                        return
                    end
                elseif sensor.value == false then
                    Registro("No Event SMpuerta Abierta", verde)
                end
            end
        elseif sensoresMovimiento == nil then
        Registro("Error Sensor de movimiento")
        end
    end

    -- Procesar ambos grupos de sensores de movimiento
    ProcSensMov(SensorMovbatt)
    ProcSensMov(SensorMovElec)
end

function CicloApagado()
    local contador = 0
    local contadorDisparos = 0
    local contadorLibres = 0

    if SensorMovbatt ~= nil then
        for i in pairs(SensorMovbatt) do
            local id = _core.get_item(SensorMovbatt[i])
            contador = contador + 1
            if id.value == true then
                contadorDisparos = contadorDisparos + 1
            end
            if id.value == false then
                contadorLibres = contadorLibres + 1
            end
        end
    end

    if SensorMovElec ~= nil then
        for i in pairs(SensorMovElec) do
            local id = _core.get_item(SensorMovElec[i])
            contador = contador + 1
            if id.value == true then
                contadorDisparos = contadorDisparos + 1
            end
            if id.value == false then
                contadorLibres = contadorLibres + 1
            end
        end
    end

    if (contador > 0 and contadorDisparos > 0) then
        CancelTimer()    
        Validar("timerAccion3","Ocupado")
        Validar("scanCycle3", "Ocupado")
        ActualizarAccion(ACCION_OCUPADO)
        return
    end

    if (contador == contadorLibres) then
        if data.scancycle == "scan_One" then
            CancelTimer()
            ActualizarAccion(ACCION_SCAN)
            Validar("timerAccion3", "Scan")
            Validar("scanCycle3", "scan_Libre")
            StartTimer(Tiempo2)

        elseif data.scancycle == "scan_Libre" then
            if _storage.get_string("Modo3") ~= MODO_APAGADO then
                if PreOffAireDoor == "si" then
                    RoutineOffLuces(devicesOn)
                    RoutineOffLuces(devicesOff)
                end
            end
            CancelTimer()
            ActualizarAccion(ACCION_CICLO_APAGADO)
            Validar("timerAccion3", "CicloApagado")
            Validar("scanCycle3", "CicloApagado")
            Registro("Tiempo_apagado: " .. Tiempo_apagado, amarillo)
            StartTimer(Tiempo_apagado)
        end
        return
    end
end

---- funciones de tipo timer
function TimerHoy()
    local DateNow = os.date("%H:%M:%S", os.time())
    local currentTime = os.time() -- Obtén el timestamp actual
    local currentHour = tonumber(os.date("%H", currentTime)) -- Extrae la hora (0-23)

    Registro("Hora Actual: " .. DateNow)
    if currentHour >= 6 and currentHour < 18 then
        EstadoDia = "Dia"
    else
        EstadoDia = "Noche"
    end
    -- Registro(EstadoDia)
end

function StartTimer(timerduration)
    local counting = VariablesDeInicio("Counting3", "0")
    if counting == '1' then -- se dejan las comillas para no reemplazar este valor en las demas paginas del code Python
        return false
    end
    Validar("TimerDuration3", timerduration)
    return StartTimeralways()
end

function StartTimeralways()
    local duration = VariablesDeInicio("TimerDuration3", 30)
    local dueTimestamp1 = os.time() + duration
    Validar("dueTimestamp3", dueTimestamp1)
    local status = RemainingUpgrade()
    Validar("Counting3", '1') -- se dejan las comillas para no reemplazar este valor en las demas paginas del code Python
    if data.TimerID ~= "" and status then
        local timerID = data.TimerID
        _storage.set_string("TimerID3", tostring(timerID))
        _timer.set_timeout_with_id(10000, tostring(timerID),
            "HUB:plg.plugin_ocupacion/scripts/rooms/room3",
            { arg_name = "timer" })
        return true
    else
        Registro("timer sin id")
        local timerID = _timer.set_timeout(10000, "HUB:plg.plugin_ocupacion/scripts/rooms/room3",
            { arg_name = "timer" })
        _storage.set_string("TimerID3", tostring(timerID))
        return true
    end
    Registro("----------------------------------",amarillo)
end

function TiempoTranscurrido()
    local Timerload = _storage.get_string("remaining3") or 0

    if Timerload == "0" or Timerload == 0 then
        return 0
    elseif string.len(Timerload) < 12 then
        local minutos = tonumber(string.sub(Timerload, 6, 7))
        local segundo = tonumber(string.sub(Timerload, 9, 10))
        minutos = minutos * 60
        segundo = minutos + segundo
        return segundo
    else
        local horas = tonumber(string.sub(Timerload, 2, 3))
        local minutos = tonumber(string.sub(Timerload, 5, 6))
        local segundos = tonumber(string.sub(Timerload, 8, 9))
        horas = horas * 3600
        minutos = minutos * 60
        segundos = horas + minutos + segundos
        return segundos
    end
end

function CancelTimer()
    local counting = VariablesDeInicio("Counting3", "0")
    if counting == "0" then
        return false
    end
    if data.TimerID ~= "" then
        local timerID = data.TimerID
        _storage.set_string("TimerID3", tostring(timerID))
        if timerID then
            if _timer.exists(tostring(timerID)) then
                _timer.cancel(tostring(timerID))
            end
        else
            Registro("timerID does  not exist", amarillo)
        end
    end
    Remaining_ant = 0
    Validar("Counting3", "0")
    Validar("dueTimestamp3", 0)
    Validar("remaining3", "0")
    Validar("TimerDuration3", 0)
    return true
end

function TimerRemaining(timer)
    local _horas = ""
    local _minutos = ""
    local horas = math.floor(timer / 3600)
    timer = timer - (horas * 3600)
    local minutos = math.floor(timer / 60)
    timer = timer - (minutos * 60)
    local segundos = timer or "0"
    if horas < 10 then
        _horas = "0" .. horas
    end
    if minutos < 10 then
        _minutos = "0" .. minutos
    else
        _minutos = tostring(minutos)
    end
    if segundos < 10 then
        segundos = "0" .. segundos
    else
        segundos = tostring(segundos)
    end
    return (_horas .. ":" .. _minutos .. ":" .. segundos)
end

function RemainingUpgrade()
    local dueTimestamp1 = VariablesDeInicio("dueTimestamp3", 0)
    local remaining = tonumber(dueTimestamp1) - os.time()
    if remaining < 0 then
        remaining = 0
    end
    local restante = TimerRemaining(remaining)
    Remaining_ant = remaining
    Validar("remaining3", "TR" .. restante)
    return remaining > 0
end

---- Main and Tick3 :: Funiciones principales
function Main()
    local TimerRemainingV = TiempoTranscurrido()
    local EstadoAccion = _json.encode(data.scancycle)
    local SensorPuerta = _core.get_item(sensor_puerta)

    local TiempPrevio = _json.encode(data.previousTimer)
    local TiempoRemanente = _json.encode(TimerRemainingV)
    
    Registro("::: Manejos Internos ::: Plg3")
    -- Registro("timerId: " .. _json.encode(data.TimerID),verde)
    TimerHoy()
    Registro("Tiempo Scaner 1= ".. Tiempo1)
    Registro("Tiempo Scaner 2= ".. Tiempo2 + 20)
    Registro("Modo plugin: " .. _json.encode(data.modo).." |-| plugin status and TimerAccion3: " .. data.acciontext,amarillo)
    Registro("ScanCycle1: " .. _json.encode(data.scancycle),verde) --"TimerAccion3: " .. _json.encode(data.timeraccion)..
    Registro("TiempoAnterior_3: " .. _json.encode(data.previousTimer),amarillo)
    Registro("TiempoPosterior_3: " .. _json.encode(TimerRemainingV),amarillo)
    Registro("Tiempo Umbral: " .. math.abs(TiempPrevio - TiempoRemanente),rojo)
    Registro("Tiempo faltante= ".. TimerRemainingV)
    Registro("----------------------------------")

    -- No mover: calculo de tiempos e intervalos
    if TimerRemainingV - data.previousTimer >= 10 then
        Registro("TimerRemainingV: " .. TimerRemainingV, amarillo)
        Registro("plugin status: " .. "acciontext: " .. data.acciontext .. ", statustext: " .. data.statustext,amarillo)
        Registro("timerduration: " .. data.timerduration .. ", timeraccion: " .. data.timeraccion, amarillo)
    end

    Validar("previousTimer3", tonumber(TimerRemainingV))

    if data.accion == 100 or data.accion == 0 then
        Validar("TimerDuration3", 0)
    else
        if TimerRemainingV > 0 then
            CancelTimer()
            StartTimer(TimerRemainingV)
        end
    end

    -- Estados de los tiempos
    if     EstadoAccion == '"scan_One"' then
        umbralTime1 = Tiempo1 - TimerRemainingV
        Registro("Tiempo Scan: " .. (umbralTime1),amarillo)
    elseif EstadoAccion == '"scan_Two"' then
        umbralTime1 = TiempoScanH - TimerRemainingV
        Registro("Tiempo Scan Hora: " .. (umbralTime1),amarillo)
        if umbralTime1 >= (TiempoScanH - 30) then -- pasa a libre en movimiento phanton
            Registro("Ciclo ... 30 min",amarillo)
            EventoMovDeLibre()
        end
    elseif EstadoAccion == '"PrePuertAbiert"' then
        umbralTime1 = Tiempo1 - TimerRemainingV
        Registro("Tiempo Transc Pre Puert Abiert= " .. (umbralTime1),amarillo)
    elseif EstadoAccion == '"Puerta Abierta"' then
        umbralTime1 = Tiempo2 - TimerRemainingV
        Registro("Tiempo Puerta Abierta= " .. (umbralTime1),amarillo)
    elseif EstadoAccion == '"scan_Libre"' then
        umbralTime1 =Tiempo1 - TimerRemainingV
        Registro("Tiempo Scan Libre: ".. umbralTime1,verde)
    end
    Registro("----------------------------------")

        if ((EstadoAccion =='"scan_One"') or (EstadoAccion =='"scan_Two"')) and SensorPuerta.value == false and (umbralTime1 >= (umbralTime2-6)) and umbralTime1 <= (umbralTime2+6) then 
                Registro("Evento: Timer Minimo",amarillo)
                EventTimeMin()
        elseif (EstadoAccion == '"PrePuertAbiert"') and SensorPuerta.value == true and umbralTime1 >= (umbralTime3-6) and umbralTime1 <= (umbralTime3+6) then
                Registro("Evento: Puerta Abierta=On - 5 min = Aire Off", amarillo)
                EventTimeMin()
        elseif (EstadoAccion == '"PrePuertAbiert"') and SensorPuerta.value == true and umbralTime1 >= (umbralTime4-6) and umbralTime1 <= (umbralTime4+6) then
                Registro("Evento: Puerta Abierta==On Sensor Mv==On - 10 min", amarillo)
                SMpuertaAb()
        end
end

function Tick3()
    local counting = VariablesDeInicio("Counting3", "0")
    local timerAccion = VariablesDeInicio("timerAccion3", "0")

    if counting == "0" then
        Registro("contador es false")
        return false
    end
    local status = RemainingUpgrade()
    if (status == true) then
        if params.timerId ~= nil then
            local timerID = tostring(params.timerId)
            _timer.set_timeout_with_id(10000, tostring(params.timerId),
                "HUB:plg.plugin_ocupacion/scripts/rooms/room3",
                { arg_name = "main" })
            if (timerID ~= "") then
                _logger.info("TimerID: " .. timerID)
                _storage.set_string("TimerID3", tostring(timerID))
                return true
            end
            return
        end
    end
    -- tiempo finalizado
    Remaining_ant = 0
    Validar("Counting3", "0")
    Validar("dueTimestamp3", "0")
    Validar("remaining3", "0")
    Registro("timerAccion: " .. _json.encode(timerAccion))

    if timerAccion == "PrePuertAbiert" then
        FunPuertaAbierta()
    elseif timerAccion == "PuertaAbierta" then
        PuertaAbiertaLibre()
    elseif timerAccion == "Scan" then
        CicloApagado()
    elseif timerAccion == "CicloApagado" then
        Libre()
    elseif timerAccion == "Libre" then
        Validar("scanCycle3", "Libre")
        CancelTimer()
    end

    return true
end

-- funcion principal
if ModoPluginStatus then
    if modeButton.value ~= "" and modeButton.value ~= data.modo then
    Registro("Modo Int: " .. data.modo)
    Registro("Modo Button Inicial: " .. modeButton.value)
    CancelTimer()
    ActualizarAccion(ACCION_SCAN)
    Validar("Modo3", tostring(modeButton.value)) --Actualiza estado del Plg con respecto al cambio de estado en web
    Validar("scanCycle3", "scan_One")
    Validar("timerAccion3", "Scan")
    Registro(("Actualizado Modo plugin modeButt: " .. modeButton.value),verde)
    Registro(("Actualizado Modo plugin Data Int: " .. data.modo),verde)
    Registro("Modo successful change ",verde)
    StartTimer(Tiempo1)
    Registro("----------------------------------")
    end
end
if AccionPluginStatus then
    local EstadoTexto = _core.get_item(tostring(EstadoPluginStatus))
    local AccionButton = _core.get_item(tostring(AccionPluginStatus))

    if EstadoTexto and EstadoTexto.value and AccionButton and AccionButton.value then
        if AccionButton.value == "Libre" and EstadoTexto.value == "Ocupado" then
            Registro("Acción cambió con éxito", "verde")
            Validar("scanCycle3", "LibreForzado")
            Libre()
        end
    else
        Registro("Error: EstadoTexto o AccionButton no tienen valores válidos.", "rojo")
    end
end
if sensor_puerta ~= nil then
    if params._id == sensor_puerta and params.event == "item_updated" then
        EventoPuerta()
    end
end
if SensorMovbatt ~= nil then
for i in pairs(SensorMovbatt) do
        if params._id == SensorMovbatt[i] and params.event == "item_updated" then
            EventMovimiento(SensorMovbatt)
            -- params.event = "item_updated"
        end
    end
end
if SensorMovElec ~= nil then
    for i in pairs(SensorMovElec) do
        if params._id == SensorMovElec[i] and params.event == "item_updated" then
            EventMovimiento(SensorMovElec)
        end
    end
end
if devicesOn ~= nil then
    for i in pairs(devicesOn) do
        -- local type = _core.get_item(devicesOn[i])
        if params._id == devicesOn[i] and params.event == "item_updated" then
            Registro("Evento Act por Pulsador On")
            EventoActuadores(devicesOn)
        end
    end
end
if devicesOff ~= nil then
    for i in pairs(devicesOff) do
        -- local type = _core.get_item(devicesOff[i])
        if params._id == devicesOff[i] and params.event == "item_updated" then
            Registro("Evento Act por Pulsador Off")
            EventoActuadores(devicesOff)
        end
    end
end 
if masterSwitch ~= nil then
    for i in pairs(masterSwitch) do
        -- local type = _core.get_item(masterSwitch[i])
        if params._id == masterSwitch[i] and params.event == "item_updated" then
            Registro("Evento Act por Master Switch")
            EventoActuadores(masterSwitch)
        end
    end
end
if params.arg_name == "timer" then
    Tick3()
else
    Main()
end