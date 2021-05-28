#!/bin/sh
NAME=$(cat /app/config/name.txt)
while sleep 5; do echo "Hello World! Hello $NAME"; done
