#!/bin/bash

# SyncWave Web - Quick Start Script
# Installs dependencies and starts the server

set -e

echo "╔════════════════════════════════════════╗"
echo "║       SyncWave Web Quick Start         ║"
echo "╚════════════════════════════════════════╝"
echo ""

# Check if Node.js is installed
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed."
    echo "   Please install Node.js 16+ from https://nodejs.org/"
    exit 1
fi

NODE_VERSION=$(node -v)
echo "✅ Node.js detected: $NODE_VERSION"
echo ""

# Install dependencies
echo "📦 Installing dependencies..."
npm install

echo ""
echo "🏗️  Building React frontend..."
npm run build-frontend

echo ""
echo "╔════════════════════════════════════════╗"
echo "║     Starting SyncWave Server...        ║"
echo "╚════════════════════════════════════════╝"
echo ""
echo "Server will start on port 5005"
echo ""
echo "📱 Open in browser:"
echo "   • Sender:   http://localhost:5005"
echo "   • Others:   http://[your-ip]:5005"
echo ""
echo "Press Ctrl+C to stop the server"
echo ""

npm start
