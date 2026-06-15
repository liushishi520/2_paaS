#!/bin/bash

echo "Building IPC Framework..."

# Clean and build
./gradlew clean
./gradlew assembleDebug

if [ $? -eq 0 ]; then
    echo "Build successful!"
    echo "Installing to device..."
    ./gradlew installDebug
    
    echo "Starting MainActivity..."
    adb shell am start -n com.ipc.demo/.MainActivity
    
    # Monitor logs
    echo "Monitoring IPC logs..."
    adb logcat | grep -E "SyncService|DataProvider|TaskQueue|Performance|MainActivity"
else
    echo "Build failed!"
    exit 1
fi
