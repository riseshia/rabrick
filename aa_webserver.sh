#!/bin/bash

bundle exec ruby sample_server.rb &
server_pid=$!

sleep 1

curl http://localhost:8080

kill $server_pid
