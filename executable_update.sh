#!/usr/bin/env bash
sudo apt-get update && sudo apt-get dist-upgrade -y && sudo apt-get autoremove -y
ssh garfio 'sudo apt-get update && sudo apt-get dist-upgrade -y && sudo apt-get autoremove -y'