# Nginx ModSecurity Log Parser with Email Report
This is a lightweight bash script designed to parse Nginx's ModSecurity logs, generate a detailed HTML report, and send it via email. The script offers an easy-to-read overview of ModSecurity events, complete with graphical representations of event statistics and a detailed log list.

![Add script](<screen.png>)

---

## :gear: Features

**Generate an HTML report** with:
- Statistics on event frequency.
- A progress bar showing the percentage of each event type.
- A detailed table of ModSecurity logs for the given date.

**Email the report** as an HTML document.

---

## :gear: Requirements 
- mailx for sending email reports.
- Nginx server with ModSecurity.

---

## :package: Installation

Clone the repository:
```bash 
git clone https://github.com/whoami-0x44/modsec-report.git

cd modsec-report
```

**Update the email address** in the script. 
Replace `info@example.com` with your actual email address.

Make the Script Executable:
```bash 
chmod 700 modsec_report.sh
```

Edit the crontab:
```bash 
vi crontab -e
```

Add to crontab to run the script and adjust the time as needed:
```bash 
10  10  *  *  *   /path/to/modsec_report.sh   >  /dev/null 2>&1
```

:wrench: Optional: You can handle Nginx error log entries into a detailed log list.

Updated the `grep` on the `LOG_LINES` line to:  
```bash 
grep -E 'ModSecurity|access forbidden by rule|No such file or directory|SSL_do_handshake' | \`
```
Updated the `sed` on the `LOG_TEXT` line to:
```bash 
sed -E 's/\[(error|crit)\] [0-9]+#[0-9]+: \*[0-9]+ //'
```

## :page_facing_up: License:
MIT License
