#!/bin/bash

# Path to the Nginx error logs
ERROR_LOG=/var/log/nginx/error.log.*
# Target date: yesterday's date in YYYY/MM/DD format
DATE=$(date "+%Y/%m/%d" -d '1 day ago')
# Temporary file to store the generated HTML report
HTML=/tmp/modsec_report.html

# Extract and clean relevant ModSecurity log lines for the target date
LOG_LINES=$(grep "$DATE" $ERROR_LOG 2>/dev/null | \
            grep -E 'ModSecurity' | \
            sed -e 's/\[file.*\[line "[0-9]*"\][[:space:]]*//g' \
                -e 's/\[rev "[0-9]*"\][[:space:]]*//g' \
                -e 's/\[data "[0-9\.]*"\].*\[accuracy "[0-9]*"\]//g' \
                -e 's/\[hostname ".*"\]//g' \
                -e 's/\[tag "[^"]*"\]//g' \
                -e 's/\[ref "[^"]*"\]//g' \
                -e 's/[[:space:]]*,[[:space:]]*\(client\|server\|referrer\):[^,]*//g')

# Exit if no log lines found
if [ -z "$LOG_LINES" ]; then
    exit 0
fi

# Initialize associative arrays for counting
declare -A UNIQUE_COMBO         # To store unique ID+IP keys
declare -A UNIQUE_COUNT_BY_ID   # Final count per ID
declare -A MSG_ORIG             # Original messages per ID
TOTAL=0
TABLE_ROWS=""

# Extract time, rule ID, IP, and message from log lines
while IFS= read -r LINE; do
    CLEAN_LINE=${LINE#*:}

    LOG_DATE=$(echo "$CLEAN_LINE" | awk '{print $1}')
    LOG_TIME=$(echo "$CLEAN_LINE" | awk '{print $2}')

    ID=$(echo "$CLEAN_LINE" | grep -oP '\[id "\K[0-9]+')
    MSG=$(echo "$CLEAN_LINE" | grep -oP '\[msg "\K[^"]+')
    CLIENT_IP=$(echo "$LINE" | grep -oP '\[client \K[^\]]+')

    if [[ -n "$ID" && -n "$CLIENT_IP" ]]; then
        COMBO_KEY="${ID}|${CLIENT_IP}"
        if [[ -z "${UNIQUE_COMBO[$COMBO_KEY]}" ]]; then
            UNIQUE_COMBO["$COMBO_KEY"]=1
            ((UNIQUE_COUNT_BY_ID["$ID"]++))
            ((TOTAL++))
        fi

        if [[ -z "${MSG_ORIG[$ID]}" ]]; then
            MSG_ORIG["$ID"]="$MSG"
        fi
    fi

    # Clean up log text for output
    LOG_TEXT=$(echo "$CLEAN_LINE" \
        | cut -d' ' -f3- \
        | sed -E 's/\[error\] [0-9]+#[0-9]+: \*[0-9]+ //')

    TABLE_ROWS+="<tr><td class=\"date-cell\">$LOG_DATE</td><td class=\"time-cell\">$LOG_TIME</td><td>$LOG_TEXT</td></tr>"
done <<< "$LOG_LINES"

# Define inline CSS styles for progress bars
read -r -d '' STYLE_PROGRESS <<EOF
    <style>
        .progress-bar {
            height: 18px;
            line-height: 20px;
            border-radius: 8px;
            max-width: 100%;
            text-align: center;
            padding: 0 4px;
            color: white;
            font-weight: bold;
            white-space: nowrap;
        }

        .progress-container {
            width: 100%;
            background-color: #ddd;
            border-radius: 8px;
            overflow: hidden;
        }
    </style>
EOF

# Begin generating the HTML report
cat <<EOF > "$HTML"
<html>
<head>
    <meta charset="UTF-8">
    $STYLE_PROGRESS
    <style>
        table {
            border-collapse: separate;
            border-spacing: 0;
            border: 1px ridge #9ac0ce;
            border-radius: 6px;
            overflow: hidden;
            width: 100%;
            font-family: Arial, sans-serif;
            margin-bottom: 30px;
        }

        thead tr.title-row th {
            background-color: #67eef3;
            color: #004b63;
            font-size: 1.3em;
            padding: 10px;
            border-radius: 6px 6px 0 0;
            border: 1px #6795af;
        }

        thead tr.header-row th {
            background-color: #c5dbee;
            padding: 8px;
            border: 1px solid #a3bed9;
            color: #6a89f0;
        }

        tbody tr:nth-child(odd) {
            background-color: #ececec;
        }

        tbody tr:nth-child(even) {
            background-color: #ffffff;
        }

        tbody tr:hover {
            background-color: #ddeeff;
        }

        td,
        th {
            text-align: left;
            padding: 8px 10px;
            font-family: monospace;
            color: #3c4f60;
            vertical-align: top;
        }

        td.date-cell,
        td.time-cell {
            white-space: nowrap;
        }

        td {
            word-break: break-word;
        }

        td.id-cell {
            min-width: 40px;
            font-weight: bold;
        }

        td.progress-cell {
            width: 120px;
        }

        .col-qty {
            text-align: center;
        }
    </style>
</head>
<body>
    <table>
        <thead>
            <tr class="title-row">
                <th colspan="5">📊 Statistics of Events for $DATE</th>
            </tr>
            <tr class="header-row">
                <th>ID</th>
                <th>Message</th>
                <th class="col-qty">Qty</th>
                <th>Chart</th>
            </tr>
        </thead>
        <tbody>
EOF
            # Populate statistics table with counts and percentage bars
            for ID in "${!UNIQUE_COUNT_BY_ID[@]}"; do
                COUNT=${UNIQUE_COUNT_BY_ID[$ID]}
                PERCENT=$(awk "BEGIN {printf \"%.1f\", $COUNT * 100 / $TOTAL}")

                # Set width based on percent
                read WIDTH COLOR <<<$(awk -v p="$PERCENT" 'BEGIN {
                    if (p < 5) { w = 20; }
                    else if (p < 10) { w = 25; }
                    else if (p < 15) { w = 28; }
                    else { w = int(30 + (p - 20) * 0.5); }

                    s = 70 + int(p * 0.05);
                    if (s > 80) s = 80;

                    l = 52 - int(p * 0.34);
                    if (l < 35) l = 35;

                    color = "hsl(120," s "%," l "%)";
                    print w, color;
                }')

                MSG=${MSG_ORIG[$ID]}
                echo "<tr>
                    <td class=\"id-cell\">${ID}</td>
                    <td>${MSG}</td>
                    <td class=\"col-qty\">${COUNT}</td>
                    <td class=\"progress-cell\">
                        <div class=\"progress-container\">
                            <div class=\"progress-bar\" style=\"width: ${WIDTH}%; background-color: ${COLOR};\">${PERCENT}%</div>
                        </div>
                    </td>
                </tr>" >> "$HTML"
            done

# Insert detailed log entries table
cat <<EOF>> "$HTML"
        </tbody>
    </table>
    <table>
        <thead>
            <tr class="title-row">
                <th colspan="3">📝 ModSecurity Detailed Log Entries for $DATE</th>
            </tr>
            <tr class="header-row">
                <th>Date</th>
                <th>Time</th>
                <th>Log</th>
            </tr>
        </thead>
        <tbody>
            $TABLE_ROWS
        </tbody>
    </table>
</body>
</html>
EOF

# Send the report via email (HTML content)
mail -a "Content-Type: text/html; charset=UTF-8" \
     -a "From:ModSecurity <modsec@localhost>" \
     -s "📋 ModSecurity Daily Report" \
     info@example.com < "$HTML"

# Cleanup temporary file
unlink "$HTML"