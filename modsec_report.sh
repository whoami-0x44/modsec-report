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
            sed -e 's/\[client [^]]*\]//g' \
                -e 's/\[file.*\[line "[0-9]*"\][[:space:]]*//g' \
                -e 's/\[rev "[0-9]*"\][[:space:]]*//g' \
                -e 's/\[data "[0-9\.]*"\].*\[accuracy "[0-9]*"\]//g' \
                -e 's/[[:space:]]*\[hostname ".*"\]//g' \
                -e 's/\[(tag|ref) "[^"]*"\]//g' \
                -e 's/[[:space:]]*,[[:space:]]*\(server\|referrer\):[^,]*//g')

# Exit if no log lines found
if [ -z "$LOG_LINES" ]; then
    exit 0
fi

# Initialize associative arrays for counting
declare -A UNIQUE_COMBO         # To store unique ID+IP keys
declare -A UNIQUE_COUNT_BY_ID   # Final count per ID
declare -A MSG_ORIG             # Original messages per ID
declare -A IP_HIT_COUNT         # Count of hits per IP address
TOTAL=0
TABLE_ROWS=""

# First pass — count the number of attempts per IP address
while IFS= read -r LINE; do
    CLIENT_IP=$(echo "$LINE" | grep -oP 'client: \K[^\s,]+')
    if [[ -n "$CLIENT_IP" ]]; then
        ((IP_HIT_COUNT["$CLIENT_IP"]++))
    fi
done <<< "$LOG_LINES"

# Extract date, time, ID, message, and client IP
while IFS= read -r LINE; do
    CLEAN_LINE=${LINE#*:}

    LOG_DATE=$(echo "$CLEAN_LINE" | awk '{print $1}')
    LOG_TIME=$(echo "$CLEAN_LINE" | awk '{print $2}')

    ID=$(echo "$CLEAN_LINE" | grep -oP '\[id "\K[0-9]+')
    MSG=$(echo "$CLEAN_LINE" | grep -oP '\[msg "\K[^"]+')

    CLIENT_IP=$(echo "$LINE" | grep -oP 'client: \K[^\s,]+')
    CLIENT_IP=$(echo "$CLIENT_IP" | xargs)

    # Update counts for unique ID+IP combos and store message
    if [[ -n "$CLIENT_IP" && -n "$ID" ]]; then
        COMBO_KEY="${ID}|${CLIENT_IP}"
        if [[ -z "${UNIQUE_COMBO[$COMBO_KEY]}" ]]; then
            UNIQUE_COMBO["$COMBO_KEY"]=1
            ((UNIQUE_COUNT_BY_ID["$ID"]++))
            ((TOTAL++))
        fi
        [[ -z "${MSG_ORIG[$ID]}" ]] && MSG_ORIG["$ID"]="$MSG"
    fi

    # Clean up log text for output
    LOG_TEXT=$(echo "$CLEAN_LINE" \
        | cut -d' ' -f3- \
        | sed -E 's/\[error\] [0-9]+#[0-9]+: \*[0-9]+ //')
    TOOLTIP_HTML=""

    if [[ -n "$CLIENT_IP" && ${IP_HIT_COUNT["$CLIENT_IP"]} -gt 1 ]]; then
        TOOLTIP_HTML="<span class='tooltip-text'>IP: $CLIENT_IP<br>${IP_HIT_COUNT[$CLIENT_IP]} attempts</span>"
    fi

    # Append row to HTML table
    TABLE_ROWS+="<tr class=\"log-row\">
                     <td class=\"date-cell\">$LOG_DATE</td>
                     <td class=\"time-cell\">$LOG_TIME</td>
                     <td><div class=\"tooltip-wrapper\">$LOG_TEXT $TOOLTIP_HTML</div></td>
                 </tr>"
done <<< "$LOG_LINES"

# Exit if no statistics and no log rows
if [[ ${#UNIQUE_COUNT_BY_ID[@]} -eq 0 && -z "$TABLE_ROWS" ]]; then
    exit 0
fi

# Define inline CSS styles
read -r -d '' STYLE <<EOF
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

        td, th {
            text-align: left;
            padding: 8px 10px;
            font-family: monospace;
            color: #3c4f60;
            vertical-align: top;
        }

        td.date-cell, td.time-cell {
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

        .tooltip-wrapper {
            position: relative;
            display: inline-block;
        }

        .tooltip-text {
            visibility: hidden;
            background: #ffffff;
            color: #333;
            padding: 8px 12px;
            border-radius: 8px;
            font-size: 0.9em;
            font-family: sans-serif;
            max-width: 250px;
            white-space: nowrap;
            display: inline-block;
            position: absolute;
            z-index: 1;
            bottom: 110%;
            left: 50%;
            transform: translateX(-50%);
            opacity: 0;
            transition: opacity 0.3s ease, transform 0.3s ease;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.2);
            border-top: 2px solid #67eef3;
            border-right: 2px solid #67eef3;
        }

        .tooltip-wrapper:hover .tooltip-text {
            visibility: visible;
            opacity: 1;
            transform: translateX(-50%) translateY(-10px);
        }

        .tooltip-text::after {
            content: '';
            position: absolute;
            bottom: -10px;
            left: 50%;
            transform: translateX(-50%);
            border-width: 10px;
            border-style: solid;
            border-color: transparent transparent #67eef3 transparent;
        }
    </style>
EOF

# Begin generating the HTML report
cat <<EOF > "$HTML"
<html>
    <head>
        <meta charset="UTF-8">
        $STYLE
    </head>
    <body>
EOF

# Add statistics table only if there is data
if [[ ${#UNIQUE_COUNT_BY_ID[@]} -gt 0 ]]; then
    cat <<EOF >> "$HTML"
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
                    # Progress bar
                    if (p < 5) { w = 20; }
                    else if (p < 10) { w = 25; }
                    else if (p < 15) { w = 28; }
                    else { w = int(30 + (p - 20) * 0.7); }

                    # Color
                    s = 70 + int(p * 0.05);
                    if (s > 80) s = 80;

                    l = 52 - int(p * 0.34);
                    if (l < 35) l = 35;

                    if (p >= 100) {
                        w = 100;
                        color = "hsl(120, 100%, 30%)";
                    } else {
                        color = "hsl(120," s "%," l "%)";
                    }
                    print w, color;
                }')

                MSG=${MSG_ORIG[$ID]}
                cat <<EOF >> "$HTML"
                <tr>
                    <td class="id-cell">${ID}</td>
                    <td>${MSG}</td>
                    <td class="col-qty">${COUNT}</td>
                    <td class="progress-cell">
                        <div class="progress-container">
                            <div class="progress-bar" style="width: ${WIDTH}%; background-color: ${COLOR};">${PERCENT}%</div>
                        </div>
                    </td>
                </tr>
EOF
            done

    cat <<EOF >> "$HTML"
            </tbody>
        </table>
EOF
fi

# Insert detailed log entries table
cat <<EOF >> "$HTML"
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