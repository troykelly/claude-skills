#!/bin/bash
# Create required labels for compliance tracking
# Run this script in the target repository

set -euo pipefail

echo "Creating required labels..."

# Status labels
gh label create "status:pending" --color "0E8A16" --description "Ready for work" --force 2>/dev/null || true
gh label create "status:in-progress" --color "1D76DB" --description "Worker assigned" --force 2>/dev/null || true
gh label create "status:awaiting-dependencies" --color "FBCA04" --description "Blocked on child issues" --force 2>/dev/null || true
gh label create "status:in-review" --color "5319E7" --description "PR created, awaiting CI" --force 2>/dev/null || true
gh label create "status:blocked" --color "D93F0B" --description "Truly blocked, needs human" --force 2>/dev/null || true

# Review finding labels
gh label create "review-finding" --color "F9D0C4" --description "Created from code review" --force 2>/dev/null || true

# Depth labels
gh label create "depth:1" --color "E6E6E6" --description "First-level finding" --force 2>/dev/null || true
gh label create "depth:2" --color "D4D4D4" --description "Second-level finding" --force 2>/dev/null || true
gh label create "depth:3" --color "BFBFBF" --description "Third-level finding (review recommended)" --force 2>/dev/null || true

# Category labels
gh label create "security" --color "B60205" --description "Security-related" --force 2>/dev/null || true

# Severity labels
gh label create "critical" --color "B60205" --description "Critical severity" --force 2>/dev/null || true
gh label create "high" --color "D93F0B" --description "High severity" --force 2>/dev/null || true
gh label create "medium" --color "FBCA04" --description "Medium severity" --force 2>/dev/null || true
gh label create "low" --color "0E8A16" --description "Low severity" --force 2>/dev/null || true

echo "Labels created successfully"
echo ""
echo "Note: 'spawned-from:#N' labels are created dynamically when review findings are created."
echo "They follow the pattern: spawned-from:#<issue-number>"
