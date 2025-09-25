#!/bin/bash

if ! grep -q '/swapfile' /etc/fstab; then
  fallocate -l 2G /swapfile || true
  chmod 600 /swapfile || true
  mkswap /swapfile || true
  swapon /swapfile || true
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi
