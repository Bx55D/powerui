<form version="1.1">
  <label>End User Security Storyboard (CIM)</label>
  <description>
    A polished end-user security monitoring view (laptops/workstations + user accounts) using CIM data models.
    Tip: click a user/host in tables to focus the Deep Dive section.
  </description>

  <fieldset submitButton="false">
    <input type="time" token="time_tok">
      <label>Time Range</label>
      <default>
        <earliest>-24h@h</earliest>
        <latest>now</latest>
      </default>
    </input>

    <input type="dropdown" token="asset_category" searchWhenChanged="true">
      <label>Endpoint Category</label>
      <choice value="*">All</choice>
      <choice value="workstation">workstation</choice>
      <choice value="laptop">laptop</choice>
      <choice value="desktop">desktop</choice>
      <default>workstation</default>
    </input>

    <input type="text" token="user_tok" searchWhenChanged="true">
      <label>User (filter)</label>
      <default>*</default>
    </input>

    <input type="text" token="host_tok" searchWhenChanged="true">
      <label>Host (filter)</label>
      <default>*</default>
    </input>

    <input type="text" token="src_tok" searchWhenChanged="true">
      <label>Source IP (filter)</label>
      <default>*</default>
    </input>

    <input type="text" token="focus_user" searchWhenChanged="true">
      <label>Focus User</label>
      <default>*</default>
    </input>

    <input type="text" token="focus_host" searchWhenChanged="true">
      <label>Focus Host</label>
      <default>*</default>
    </input>
  </fieldset>

  <!-- ===================== -->
  <!-- HERO / STORY INTRO -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:18px 18px 16px 18px;border-radius:14px;background:linear-gradient(90deg,#111827,#1f2937);color:#fff;">
            <div style="display:flex;align-items:flex-end;justify-content:space-between;gap:16px;flex-wrap:wrap;">
              <div>
                <div style="font-size:22px;font-weight:800;letter-spacing:.2px;">🛡️ End User Security — Storyboard View</div>
                <div style="margin-top:6px;opacity:.92;font-size:13.5px;max-width:980px;">
                  A narrative dashboard for laptops/workstations and user accounts.
                  Start at the top for pressure + signals, then follow the story down.
                  <b>Pro move:</b> click a user/host in any table to pivot the Deep Dive.
                </div>
              </div>
              <div style="padding:8px 10px;border-radius:10px;background:rgba(255,255,255,.08);font-size:12.5px;">
                Scope: <b>$asset_category$</b> endpoints • User filter: <b>$user_tok$</b> • Host filter: <b>$host_tok$</b>
              </div>
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- “RIGHT NOW” KPIs -->
  <!-- ===================== -->
  <row>
    <panel>
      <title>🔐 Credential Pressure (Auth Failures)</title>
      <single>
        <search>
          <query>
            | tstats allow_old_summaries=t count as c
              from datamodel=Authentication
              where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$
              by _time span=1h
            | stats sum(c) as value sparkline(sum(c)) as trend
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Failures (with trend)</option>
        <option name="trendDisplayMode">sparkline</option>
        <option name="useThousandSeparators">true</option>
        <option name="colorMode">block</option>
        <option name="rangeValues">200,1000,5000</option>
        <option name="rangeColors">0x22c55e,0xf59e0b,0xef4444,0x991b1b</option>
      </single>
    </panel>

    <panel>
      <title>🎯 Spray-like Sources (IPs w/ Many Users)</title>
      <single>
        <search>
          <query>
            | tstats allow_old_summaries=t count as failures dc(Authentication.user) as du
              from datamodel=Authentication
              where Authentication.action=failure Authentication.src=$src_tok$
              by Authentication.src
            | rename Authentication.src as src
            | where du &gt;= 10 AND failures &gt;= 50
            | stats count as value
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Candidate spray IPs</option>
        <option name="colorMode">block</option>
        <option name="rangeValues">1,3,8</option>
        <option name="rangeColors">0xf59e0b,0xef4444,0x991b1b,0x7f1d1d</option>
      </single>
    </panel>

    <panel>
      <title>🧫 Endpoint Detections (Malware DM)</title>
      <single>
        <search>
          <query>
            | tstats allow_old_summaries=t count as c
              from datamodel=Malware
              where Malware.dest=$host_tok$ Malware.dest_category=$asset_category$
            | eval value=c
            | fields value
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Detections</option>
        <option name="colorMode">block</option>
        <option name="rangeValues">1,10,50</option>
        <option name="rangeColors">0x22c55e,0xf59e0b,0xef4444,0x991b1b</option>
      </single>
    </panel>

    <panel>
      <title>⚙️ Suspicious Script Activity (LOLbins)</title>
      <single>
        <search>
          <query>
            | tstats allow_old_summaries=t count as c
              from datamodel=Endpoint.Processes
              where Processes.dest=$host_tok$ Processes.user=$user_tok$ Processes.dest_category=$asset_category$
                (Processes.process_name=powershell.exe OR Processes.process_name=cmd.exe OR Processes.process_name=wscript.exe OR Processes.process_name=cscript.exe OR Processes.process_name=mshta.exe OR Processes.process_name=rundll32.exe OR Processes.process_name=regsvr32.exe)
              by _time span=1h
            | stats sum(c) as value sparkline(sum(c)) as trend
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Executions (with trend)</option>
        <option name="trendDisplayMode">sparkline</option>
        <option name="colorMode">block</option>
        <option name="rangeValues">50,250,1000</option>
        <option name="rangeColors">0x22c55e,0xf59e0b,0xef4444,0x991b1b</option>
      </single>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- CHAPTER 1: IDENTITY PRESSURE -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:12px 14px;border-radius:12px;background:#0b1220;color:#e5e7eb;border:1px solid rgba(255,255,255,.08);">
            <div style="font-size:16px;font-weight:800;">Chapter 1 — Identity Pressure</div>
            <div style="margin-top:4px;opacity:.9;font-size:13px;">
              Where attacks start: failed logins, sprays, and “failure → success” patterns that suggest guessing or MFA fatigue.
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <row>
    <panel>
      <title>Auth Failures Over Time</title>
      <chart>
        <search>
          <query>
            | tstats allow_old_summaries=t count as failures
              from datamodel=Authentication
              where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$
              by _time span=15m
            | timechart span=15m sum(failures) as failures
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="charting.chart">area</option>
        <option name="charting.legend.placement">right</option>
      </chart>
    </panel>

    <panel>
      <title>Failure Heatmap (Day × Hour)</title>
      <chart>
        <search>
          <query>
            | tstats allow_old_summaries=t count as failures
              from datamodel=Authentication
              where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$
              by _time span=1h
            | eval dow=strftime(_time,"%a"), hour=strftime(_time,"%H")
            | stats sum(failures) as failures by dow hour
            | xyseries hour dow failures
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="charting.chart">heatmap</option>
      </chart>
    </panel>
  </row>

  <row>
    <panel>
      <title>Top Users by Failures (Click to Focus User)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as failures dc(Authentication.src) as src_ips
              from datamodel=Authentication
              where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$
              by Authentication.user
            | rename Authentication.user as user
            | where user!="unknown" AND user!="-" AND NOT like(user,"%$") 
            | sort - failures
            | head 25
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">25</option>
        <option name="wrap">true</option>
        <drilldown>
          <set token="focus_user">$row.user$</set>
        </drilldown>
      </table>
    </panel>

    <panel>
      <title>Password Spray Candidates (Many Users per Source IP)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as failures dc(Authentication.user) as distinct_users
              from datamodel=Authentication
              where Authentication.action=failure Authentication.src=$src_tok$
              by Authentication.src
            | rename Authentication.src as src
            | where distinct_users &gt;= 10 AND failures &gt;= 50
            | eval severity=case(distinct_users&gt;=50,"critical", distinct_users&gt;=25,"high", distinct_users&gt;=10,"medium", 1=1,"low")
            | sort - distinct_users - failures
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <drilldown>
          <set token="src_tok">$row.src$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <row>
    <panel>
      <title>Failure → Success Pairs (Suggest Guessing / Fatigue)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as c
              from datamodel=Authentication
              where (Authentication.action=failure OR Authentication.action=success)
                Authentication.user=$user_tok$ Authentication.src=$src_tok$
              by Authentication.user Authentication.src Authentication.action
            | rename Authentication.user as user Authentication.src as src Authentication.action as action
            | stats sum(eval(action="failure")*c) as failures sum(eval(action="success")*c) as successes by user src
            | where failures &gt;= 5 AND successes &gt;= 1
            | eval note="Failures followed by success from same src"
            | sort - failures - successes
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <drilldown>
          <set token="focus_user">$row.user$</set>
          <set token="src_tok">$row.src$</set>
        </drilldown>
      </table>
    </panel>

    <panel>
      <title>First-Time Source IPs for Users (Last 24h vs Prior 7d)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as hits
              from datamodel=Authentication
              where Authentication.action=success Authentication.user=$user_tok$
              by Authentication.user Authentication.src
            | rename Authentication.user as user Authentication.src as src
            | eval window="current"
            | fields user src window
            | append [
                | tstats allow_old_summaries=t count as hits
                  from datamodel=Authentication
                  where Authentication.action=success earliest=-8d@d latest=-1d@d
                  by Authentication.user Authentication.src
                | rename Authentication.user as user Authentication.src as src
                | eval window="baseline"
                | fields user src window
              ]
            | stats max(eval(window="baseline")) as seen_before by user src
            | where seen_before!=1
            | sort user src
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <drilldown>
          <set token="focus_user">$row.user$</set>
          <set token="src_tok">$row.src$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- CHAPTER 2: ENDPOINT HEALTH -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:12px 14px;border-radius:12px;background:#0b1220;color:#e5e7eb;border:1px solid rgba(255,255,255,.08);">
            <div style="font-size:16px;font-weight:800;">Chapter 2 — Endpoint Health</div>
            <div style="margin-top:4px;opacity:.9;font-size:13px;">
              What’s running on client machines: detections, suspicious chains, and rare executions worth a second look.
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <row>
    <panel>
      <title>Malware Detections by Host (Click to Focus Host)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as detections
              from datamodel=Malware
              where Malware.dest=$host_tok$ Malware.dest_category=$asset_category$
              by Malware.dest Malware.signature
            | rename Malware.dest as host Malware.signature as signature
            | sort - detections
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <option name="wrap">true</option>
        <drilldown>
          <set token="focus_host">$row.host$</set>
        </drilldown>
      </table>
    </panel>

    <panel>
      <title>Office → Script Chain (Common Phish/Macro Pattern)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as executions
              from datamodel=Endpoint.Processes
              where Processes.dest=$host_tok$ Processes.user=$user_tok$ Processes.dest_category=$asset_category$
                (Processes.parent_process_name=winword.exe OR Processes.parent_process_name=excel.exe OR Processes.parent_process_name=powerpnt.exe OR Processes.parent_process_name=outlook.exe)
                (Processes.process_name=powershell.exe OR Processes.process_name=cmd.exe OR Processes.process_name=wscript.exe OR Processes.process_name=cscript.exe OR Processes.process_name=mshta.exe OR Processes.process_name=rundll32.exe OR Processes.process_name=regsvr32.exe)
              by Processes.dest Processes.user Processes.parent_process_name Processes.process_name
            | rename Processes.dest as host Processes.user as user Processes.parent_process_name as parent Processes.process_name as child
            | sort - executions
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <drilldown>
          <set token="focus_host">$row.host$</set>
          <set token="focus_user">$row.user$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <row>
    <panel>
      <title>Rare Process Names (Low Frequency Across Fleet)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as executions
              from datamodel=Endpoint.Processes
              where Processes.dest=$host_tok$ Processes.user=$user_tok$ Processes.dest_category=$asset_category$
              by Processes.process_name
            | rename Processes.process_name as process
            | where executions &lt;= 5
            | sort executions
            | head 60
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">60</option>
      </table>
    </panel>

    <panel>
      <title>Coverage Gaps: Endpoints Not Seen Recently (Processes DM)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t latest(_time) as last_seen
              from datamodel=Endpoint.Processes
              where Processes.dest_category=$asset_category$
              by Processes.dest
            | rename Processes.dest as host
            | eval minutes_since=round((now()-last_seen)/60,0)
            | where minutes_since &gt;= 360
            | eval last_seen=strftime(last_seen,"%Y-%m-%d %H:%M:%S")
            | sort - minutes_since
            | head 50
          </query>
          <earliest>-30d@d</earliest>
          <latest>now</latest>
        </search>
        <option name="count">50</option>
        <drilldown>
          <set token="focus_host">$row.host$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- CHAPTER 3: PHISHING / WEB PRESSURE -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:12px 14px;border-radius:12px;background:#0b1220;color:#e5e7eb;border:1px solid rgba(255,255,255,.08);">
            <div style="font-size:16px;font-weight:800;">Chapter 3 — Phishing & Web Pressure</div>
            <div style="margin-top:4px;opacity:.9;font-size:13px;">
              The two biggest end-user entry points: inbox + browser. These panels surface blocked/quarantined email and risky web patterns.
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <row>
    <panel>
      <title>Email Quarantine / Blocked (Top Senders & Subjects)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as events
              from datamodel=Email
              where (Email.action=blocked OR Email.action=quarantine OR Email.action=quarantined)
              by Email.sender Email.subject
            | rename Email.sender as sender Email.subject as subject
            | sort - events
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <option name="wrap">true</option>
      </table>
    </panel>

    <panel>
      <title>New Web Domains (Last 24h vs Prior 7d)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as hits
              from datamodel=Web
              where Web.dest=$host_tok$ Web.user=$user_tok$ Web.dest_category=$asset_category$
              by Web.url_domain
            | rename Web.url_domain as domain
            | eval window="current"
            | fields domain window
            | append [
                | tstats allow_old_summaries=t count as hits
                  from datamodel=Web
                  where earliest=-8d@d latest=-1d@d Web.dest_category=$asset_category$
                  by Web.url_domain
                | rename Web.url_domain as domain
                | eval window="baseline"
                | fields domain window
              ]
            | stats max(eval(window="baseline")) as seen_before by domain
            | where seen_before!=1 AND domain!="" AND domain!="unknown"
            | sort domain
            | head 80
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">80</option>
      </table>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- CHAPTER 4: ACCOUNT/PRIV CHANGE SIGNALS -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:12px 14px;border-radius:12px;background:#0b1220;color:#e5e7eb;border:1px solid rgba(255,255,255,.08);">
            <div style="font-size:16px;font-weight:800;">Chapter 4 — Privilege & Change Signals</div>
            <div style="margin-top:4px;opacity:.9;font-size:13px;">
              Compromises often show up as “quiet” changes: group membership, privilege changes, new accounts, or policy tweaks.
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <row>
    <panel>
      <title>High-Impact Changes (Accounts / Groups / Privileges)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as changes
              from datamodel=Change
              where Change.user=$user_tok$ Change.dest=$host_tok$ Change.dest_category=$asset_category$
                (Change.object_category=account OR Change.object_category=group OR Change.object_category=privilege)
              by Change.user Change.object Change.action Change.dest
            | rename Change.user as actor Change.object as object Change.action as action Change.dest as target
            | sort - changes
            | head 60
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">60</option>
        <option name="wrap">true</option>
        <drilldown>
          <set token="focus_user">$row.actor$</set>
          <set token="focus_host">$row.target$</set>
        </drilldown>
      </table>
    </panel>

    <panel>
      <title>User Risk Leaderboard (Simple Composite)</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as v
              from datamodel=Authentication
              where Authentication.action=failure
              by Authentication.user
            | rename Authentication.user as user
            | where user!="unknown" AND user!="-" AND NOT like(user,"%$")
            | eval auth_fail=v
            | fields user auth_fail
            | append [
                | tstats allow_old_summaries=t count as v
                  from datamodel=Endpoint.Processes
                  where Processes.dest_category=$asset_category$
                    (Processes.process_name=powershell.exe OR Processes.process_name=cmd.exe OR Processes.process_name=wscript.exe OR Processes.process_name=cscript.exe OR Processes.process_name=mshta.exe OR Processes.process_name=rundll32.exe OR Processes.process_name=regsvr32.exe)
                  by Processes.user
                | rename Processes.user as user
                | eval lolbin_exec=v
                | fields user lolbin_exec
              ]
            | append [
                | tstats allow_old_summaries=t count as v
                  from datamodel=Malware
                  where Malware.dest_category=$asset_category$
                  by Malware.user
                | rename Malware.user as user
                | eval malware=v
                | fields user malware
              ]
            | stats sum(auth_fail) as auth_fail sum(lolbin_exec) as lolbin_exec sum(malware) as malware by user
            | eval risk=round((auth_fail/50) + (lolbin_exec*0.5) + (malware*3), 2)
            | where risk &gt; 0
            | sort - risk
            | head 25
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">25</option>
        <drilldown>
          <set token="focus_user">$row.user$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <!-- ===================== -->
  <!-- DEEP DIVE (AUTO-PIVOT) -->
  <!-- ===================== -->
  <row>
    <panel>
      <html>
        <![CDATA[
          <div style="padding:14px 14px;border-radius:12px;background:linear-gradient(90deg,#0b1220,#111827);color:#e5e7eb;border:1px solid rgba(255,255,255,.08);">
            <div style="font-size:16px;font-weight:900;">🔎 Deep Dive — Pivot View</div>
            <div style="margin-top:4px;opacity:.9;font-size:13px;">
              Focus User: <b>$focus_user$</b> • Focus Host: <b>$focus_host$</b>
              <span style="opacity:.8;">(Set via clicks above, or type into the Focus fields.)</span>
            </div>
          </div>
        ]]>
      </html>
    </panel>
  </row>

  <row>
    <panel>
      <title>Focused User: Auth Timeline</title>
      <chart>
        <search>
          <query>
            | tstats allow_old_summaries=t count as c
              from datamodel=Authentication
              where Authentication.user=$focus_user$ (Authentication.action=failure OR Authentication.action=success) Authentication.src=$src_tok$
              by _time span=30m Authentication.action
            | rename Authentication.action as action
            | timechart span=30m sum(c) by action
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="charting.chart">column</option>
        <option name="charting.legend.placement">right</option>
      </chart>
    </panel>

    <panel>
      <title>Focused Host: Top Processes</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as executions
              from datamodel=Endpoint.Processes
              where Processes.dest=$focus_host$ Processes.dest_category=$asset_category$ Processes.user=$focus_user$
              by Processes.process_name Processes.user
            | rename Processes.process_name as process Processes.user as user
            | sort - executions
            | head 30
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">30</option>
        <drilldown>
          <set token="focus_user">$row.user$</set>
        </drilldown>
      </table>
    </panel>
  </row>

  <row>
    <panel>
      <title>Focused Host/User: “Interesting” Executions</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as executions
              from datamodel=Endpoint.Processes
              where Processes.dest=$focus_host$ Processes.user=$focus_user$ Processes.dest_category=$asset_category$
                (Processes.process_name=powershell.exe OR Processes.process_name=cmd.exe OR Processes.process_name=wscript.exe OR Processes.process_name=cscript.exe OR Processes.process_name=mshta.exe OR Processes.process_name=rundll32.exe OR Processes.process_name=regsvr32.exe)
              by _time span=10m Processes.dest Processes.user Processes.parent_process_name Processes.process_name
            | rename Processes.dest as host Processes.user as user Processes.parent_process_name as parent Processes.process_name as child
            | eval time=strftime(_time,"%Y-%m-%d %H:%M:%S")
            | table time host user parent child executions
            | sort - time
            | head 120
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">120</option>
        <option name="wrap">true</option>
      </table>
    </panel>

    <panel>
      <title>Focused Host: Outbound Heavy Destinations</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t sum(Network_Traffic.bytes_out) as bytes_out count as flows
              from datamodel=Network_Traffic
              where Network_Traffic.src=$focus_host$ Network_Traffic.dest_category=$asset_category$
              by Network_Traffic.dest
            | rename Network_Traffic.dest as dest
            | eval MB_out=round(bytes_out/1024/1024,2)
            | fields dest flows MB_out
            | sort - MB_out
            | head 25
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">25</option>
      </table>
    </panel>
  </row>

  <row>
    <panel>
      <title>Focused Host: Malware Details</title>
      <table>
        <search>
          <query>
            | tstats allow_old_summaries=t count as detections
              from datamodel=Malware
              where Malware.dest=$focus_host$ Malware.dest_category=$asset_category$
              by Malware.signature Malware.file_name Malware.user
            | rename Malware.signature as signature Malware.file_name as file Malware.user as user
            | sort - detections
            | head 80
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">80</option>
        <option name="wrap">true</option>
      </table>
    </panel>
  </row>

</form>
