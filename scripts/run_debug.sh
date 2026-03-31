#!/bin/bash
# Debug launcher for LittleBrother
# Runs the app with visible terminal output for debugging

cd /home/n0v4p4x/DevOps/littlebrother

echo "Starting LittleBrother in debug mode..."
echo "Output will be tee'd to debug.log"
echo "Press Ctrl+C to stop"
echo "========================================"

# Run flutter and capture both stdout and stderr
/home/n0v4p4x/DevOps/flutter/bin/flutter run 2>&1 | tee debug.log

echo "========================================"
echo "LittleBrother stopped. Log saved to debug.log"