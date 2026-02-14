#!/bin/bash
# Remove Co-Authored-By Claude lines and "Remove AI assistant configuration file" bullet
sed '/Co-Authored-By: Claude/d' | sed '/- Remove AI assistant configuration file/d' | sed -e :a -e '/^[[:space:]]*$/{ $d; N; ba; }'
