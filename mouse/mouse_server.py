#!/usr/bin/env python3
"""
Mobile Mouse Server - Python Version
Controls actual computer mouse using PyAutoGUI
"""

import asyncio
import websockets
import json
import pyautogui
import time
from datetime import datetime

# Configure PyAutoGUI
pyautogui.FAILSAFE = True  # Move mouse to corner to stop
pyautogui.PAUSE = 0.01     # Minimal delay for smooth movement

# Server settings
PORT = 8081
HOST = '0.0.0.0'

# Mouse settings
sensitivity = 12
deadzone = 0.08
mouse_enabled = True

# Get screen size
screen_width, screen_height = pyautogui.size()
print(f"🖥️  Screen size: {screen_width}x{screen_height}")

class MouseServer:
    def __init__(self):
        self.clients = set()
        
    async def register_client(self, websocket):
        """Register a new client"""
        self.clients.add(websocket)
        print(f"📱 Mobile device connected from {websocket.remote_address}")
        
        # Send welcome message
        welcome_msg = {
            'type': 'welcome',
            'message': 'Connected to Python Mobile Mouse Server',
            'screenSize': {'width': screen_width, 'height': screen_height},
            'sensitivity': sensitivity,
            'deadzone': deadzone,
            'mouseEnabled': mouse_enabled
        }
        await websocket.send(json.dumps(welcome_msg))
        
    async def unregister_client(self, websocket):
        """Unregister a client"""
        self.clients.discard(websocket)
        print("📱 Mobile device disconnected")
        
    async def handle_message(self, websocket, message):
        """Handle incoming messages from mobile app"""
        try:
            data = json.loads(message)
            message_type = data.get('type', 'unknown')
            
            print(f"📨 Received: {message_type}")
            
            if message_type == 'motion':
                await self.handle_movement(data)
            elif message_type == 'click':
                await self.handle_click(data)
            elif message_type == 'scroll':
                await self.handle_scroll(data)
            elif message_type == 'test':
                print(f"🧪 Test message: {data.get('message', 'No message')}")
            else:
                print(f"❓ Unknown message type: {message_type}")
                
        except json.JSONDecodeError:
            print("❌ Invalid JSON received")
        except Exception as e:
            print(f"❌ Error handling message: {e}")
            
    async def handle_movement(self, data):
        """Handle mouse movement"""
        if not mouse_enabled:
            return
            
        movement_x = data.get('movementX', 0)
        movement_y = data.get('movementY', 0)
        
        # Apply deadzone to filter jitter
        if abs(movement_x) < deadzone and abs(movement_y) < deadzone:
            return  # Ignore small movements
            
        # Calculate mouse movement
        delta_x = 0
        delta_y = 0
        
        if abs(movement_x) > deadzone:
            delta_x = movement_x * sensitivity
            
        if abs(movement_y) > deadzone:
            delta_y = -movement_y * sensitivity  # Inverted for natural feel
            
        # Get current mouse position
        current_x, current_y = pyautogui.position()
        
        # Calculate new position
        new_x = current_x + delta_x
        new_y = current_y + delta_y
        
        # Keep within screen bounds
        new_x = max(0, min(screen_width - 1, new_x))
        new_y = max(0, min(screen_height - 1, new_y))
        
        # Move the mouse
        if abs(delta_x) > 0.1 or abs(delta_y) > 0.1:
            pyautogui.moveTo(new_x, new_y)
            print(f"🖱️  Mouse moved by ({delta_x:.1f}, {delta_y:.1f}) to ({new_x:.0f}, {new_y:.0f})")
            
    async def handle_click(self, data):
        """Handle mouse clicks"""
        button = data.get('button', 'left')
        action = data.get('action', 'click')
        
        print(f"🖱️  {action} {button} click")
        
        try:
            if action == 'click':
                pyautogui.click(button=button)
            elif action == 'double':
                pyautogui.doubleClick(button=button)
            elif action == 'down':
                pyautogui.mouseDown(button=button)
            elif action == 'up':
                pyautogui.mouseUp(button=button)
        except Exception as e:
            print(f"❌ Click error: {e}")
            
    async def handle_scroll(self, data):
        """Handle mouse scrolling"""
        direction = data.get('direction', 'up')
        amount = data.get('amount', 3)
        
        print(f"🖱️  Scroll {direction} by {amount}")
        
        try:
            if direction == 'up':
                pyautogui.scroll(amount)
            elif direction == 'down':
                pyautogui.scroll(-amount)
        except Exception as e:
            print(f"❌ Scroll error: {e}")

# Global server instance
mouse_server = MouseServer()

async def handle_client(websocket, path):
    """Handle WebSocket client connection"""
    await mouse_server.register_client(websocket)
    try:
        async for message in websocket:
            await mouse_server.handle_message(websocket, message)
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        await mouse_server.unregister_client(websocket)

def main():
    """Start the mouse server"""
    print("🖱️  Python Mobile Mouse Server")
    print("=" * 40)
    print(f"🖥️  Screen size: {screen_width}x{screen_height}")
    print(f"⚙️  Sensitivity: {sensitivity}")
    print(f"⚙️  Deadzone: {deadzone}")
    print(f"🌐 Server starting on {HOST}:{PORT}")
    print(f"📱 Connect your mobile app to: ws://YOUR_IP:{PORT}")
    print("=" * 40)
    print("🛑 Move mouse to top-left corner to emergency stop")
    print("📋 Ready to receive mobile commands...")
    print()
    
    # Start WebSocket server
    start_server = websockets.serve(handle_client, HOST, PORT)
    
    try:
        asyncio.get_event_loop().run_until_complete(start_server)
        asyncio.get_event_loop().run_forever()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
    except Exception as e:
        print(f"❌ Server error: {e}")

if __name__ == "__main__":
    main()