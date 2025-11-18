#!/bin/bash

# Fetch GitHub issue data for analysis
echo "Issue,Title,Body_Length,Has_Checklist,Has_Acceptance_Criteria,Has_Phase_Breakdown,Label_Count,Created_At,Closed_At"

# List of issue numbers from PR mapping
issues=(10 12 15 38 39 40 45 53 66 74 75 81 97 98 104 107 109 110 111 112 113 125 128 130 137 139 144 153 154 156 159)

for issue_num in "${issues[@]}"; do
    # Fetch issue data
    issue_data=$(gh issue view "$issue_num" --json number,title,body,labels,createdAt,closedAt 2>/dev/null)

    if [ $? -ne 0 ]; then
        echo "$issue_num,ERROR,0,false,false,false,0,N/A,N/A" >&2
        continue
    fi

    # Extract fields using jq
    title=$(echo "$issue_data" | jq -r '.title' | tr ',' ' ')
    body=$(echo "$issue_data" | jq -r '.body // ""')
    body_length=${#body}
    label_count=$(echo "$issue_data" | jq '.labels | length')
    created_at=$(echo "$issue_data" | jq -r '.createdAt')
    closed_at=$(echo "$issue_data" | jq -r '.closedAt // "N/A"')

    # Check for quality indicators in body
    has_checklist=false
    has_acceptance=false
    has_phase=false

    if echo "$body" | grep -q '\- \[[ x]\]'; then
        has_checklist=true
    fi

    if echo "$body" | grep -iq 'acceptance criteria\|definition of done\|success criteria'; then
        has_acceptance=true
    fi

    if echo "$body" | grep -iq 'phase \d\|step \d\|stage \d'; then
        has_phase=true
    fi

    echo "$issue_num,\"$title\",$body_length,$has_checklist,$has_acceptance,$has_phase,$label_count,$created_at,$closed_at"
done
