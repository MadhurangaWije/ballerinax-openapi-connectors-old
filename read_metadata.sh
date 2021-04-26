#!/bin/bash
input="metadata.toml"
while IFS= read -r line
do
  echo "$line"
done < "$input"
