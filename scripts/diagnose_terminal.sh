#!/bin/bash

# Diagnostic script to check terminal output issues
# Run: ./diagnose_terminal.sh

echo "=== Terminal Diagnostic ==="
echo "Date: $(date)"
echo "Shell: $SHELL"
echo "PWD: $(pwd)"
echo ""

echo "=== Testing Basic Commands ==="
echo "Test 1: echo"
echo "SUCCESS: echo works"
echo ""

echo "Test 2: pwd"
pwd
echo ""

echo "Test 3: ls"
ls -la | head -3
echo ""

echo "Test 4: git"
if command -v git &> /dev/null; then
    echo "Git is installed: $(git --version)"
    if [ -d .git ]; then
        echo "Git is initialized"
        git status --short | head -5
    else
        echo "Git is NOT initialized"
    fi
else
    echo "Git is NOT installed"
fi
echo ""

echo "=== Environment Variables ==="
echo "TERM: $TERM"
echo "LANG: $LANG"
echo ""

echo "=== Output Redirection Test ==="
echo "stdout test" > /tmp/test_stdout.txt 2>&1
echo "stderr test" 2> /tmp/test_stderr.txt
cat /tmp/test_stdout.txt
cat /tmp/test_stderr.txt
echo ""

echo "=== Diagnostic Complete ==="







