#!/bin/bash
input="metadata.toml"
while IFS= read -r line
do
#   echo "$line"
  arrIN=(${line//=/ })
  key=${arrIN[0]}
  value=${arrIN[1]}   
  declare $key=$value
done < "$input"

echo "$dirname"
echo "$version"
echo "$name"
echo "$path"
