#!/bin/bash

echo "Cleaning unused Docker resources..."

docker system prune -af

echo "Removing dangling volumes..."

docker volume prune -f

echo "Cleanup completed successfully."