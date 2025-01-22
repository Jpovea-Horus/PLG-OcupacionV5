# Plugin de Ocupación - V5 
Este plugin permite gestionar dispositivos relacionados con sensores de puerta y movimiento, y automatizar acciones en función de estos sensores, tales como activar/desactivar luces, controlar un termostato, y más.

## Descripción 
El plugin proporciona una serie de configuraciones para integrar sensores de puerta, sensores de movimiento y dispositivos como actuadores y termostatos. Con este sistema, es posible automatizar tareas como la activación de dispositivos cuando se detecta movimiento o la apertura de una puerta, o incluso controlar la temperatura de un ambiente a través de un termostato.

## Características Sensores de Movimiento: 
Permite configurar sensores de movimiento principales y secundarios. Sensores de Puerta: Detecta la apertura o cierre de puertas para activar o desactivar otros dispositivos. 
### Actuadores: Configura dispositivos que se activan o desactivan cuando se cumplen ciertas condiciones. 
### Termostato: Permite ajustar los SetPoints del termostato para controlar la temperatura del ambiente. 
### Modo Automático: Configura si ciertos dispositivos deben activarse automáticamente con base en el estado de los sensores. ### Configuración El plugin requiere una configuración inicial con varios parámetros que se describen a continuación:

## Parámetros de configuración
- itemId Sensor de Puerta (requerido): El itemId del sensor de puerta.
- itemId Sensor de Movimiento Principal (opcional): El itemId del sensor de movimiento principal. 
- itemId Sensor de Movimiento Secundario (opcional): El itemId del sensor de movimiento secundario. 
- itemId Actuadores On (opcional): El itemId de los dispositivos que se activarán cuando se detecte movimiento. 
- itemId Actuadores Off (opcional): El itemId de los dispositivos que se desactivarán. 
- itemId Actuadores Master Switch (opcional): El itemId del interruptor principal para activar o desactivar dispositivos.

- deviceId Termostato (opcional): El deviceId del termostato para ajustar la temperatura. 
- SetPoint On Termostato (opcional): El valor de SetPoint para cuando el termostato se encienda. 
- SetPoint Off Termostato (opcional): El valor de SetPoint para cuando el termostato se apague. 
- Modo Encendido Termostato (opcional): Indica si se debe activar el termostato al detectar movimiento. 
- Modo SetPoint (opcional): Indica si el SetPoint debe ajustarse cuando se pasa al modo libre. 
- Modo Off Puerta Abierta (opcional): Si se activa, el sistema se apaga al detectar que la puerta está abierta. 
- Modo Disparador Luces (opcional): Indica si las luces deben activarse al detectar movimiento. 
- Modo Disparador Master Switch (opcional): Indica si el Master Switch debe activarse al detectar movimiento. 
- Tiempo Sensor de Scanner (requerido): El tiempo estimado de escaneo después de desactivar el sensor de movimiento.

- Password (requerido): La contraseña para la configuración del plugin.
