<form version="1.1">
  <label>Security Monitoring - CIM (Overview)</label>
  <description>Security monitoring dashboard using CIM data models (tstats). Requires CIM-aligned data and (ideally) accelerated data models.</description>

  <fieldset submitButton="false">
    <input type="time" token="time_tok">
      <label>Time Range</label>
      <default>
        <earliest>-24h@h</earliest>
        <latest>now</latest>
      </default>
    </input>

    <input type="dropdown" token="env_tok" searchWhenChanged="true">
      <label>Environment</label>
      <choice value="*">All</choice>
      <choice value="prod">prod</choice>
      <choice value="dev">dev</choice>
      <choice value="test">test</choice>
      <default>*</default>
    </input>

    <input type="text" token="user_tok" searchWhenChanged="true">
      <label>User (optional)</label>
      <default>*</default>
    </input>

    <input type="text" token="src_tok" searchWhenChanged="true">
      <label>Source IP (optional)</label>
      <default>*</default>
    </input>
  </fieldset>

  <!-- ========================= -->
  <!-- KPIs -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>Auth Failures (Distinct Users)</title>
      <single>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t dc(Authentication.user) as dc_users
            from datamodel=Authentication
            where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$ Authentication.dest_category=$env_tok$
            by _time span=1h
            | stats sum(dc_users) as dc_users
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Users with failures</option>
        <option name="refresh.display">progressbar</option>
      </single>
    </panel>

    <panel>
      <title>Authentication Failures (Events)</title>
      <single>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as failures
            from datamodel=Authentication
            where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$ Authentication.dest_category=$env_tok$
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Failed logins</option>
        <option name="refresh.display">progressbar</option>
      </single>
    </panel>

    <panel>
      <title>Malware / Detections (Events)</title>
      <single>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as detections
            from datamodel=Malware
            where Malware.dest_category=$env_tok$
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Malware events</option>
      </single>
    </panel>

    <panel>
      <title>Notable Traffic: Blocked / Denied</title>
      <single>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as blocked
            from datamodel=Network_Traffic
            where (Network_Traffic.action=blocked OR Network_Traffic.action=deny OR Network_Traffic.action=denied)
              Network_Traffic.src=$src_tok$ Network_Traffic.dest_category=$env_tok$
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="underLabel">Denied / Blocked flows</option>
      </single>
    </panel>
  </row>

  <!-- ========================= -->
  <!-- Auth Trends + Top Offenders -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>Authentication Failures Over Time</title>
      <chart>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as failures
            from datamodel=Authentication
            where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$ Authentication.dest_category=$env_tok$
            by _time span=15m
            | timechart span=15m sum(failures) as failures
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="charting.chart">line</option>
        <option name="charting.legend.placement">right</option>
      </chart>
    </panel>

    <panel>
      <title>Top Users by Auth Failures</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as failures
            from datamodel=Authentication
            where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$ Authentication.dest_category=$env_tok$
            by Authentication.user
            | rename Authentication.user as user
            | sort - failures
            | head 20
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">20</option>
        <option name="wrap">true</option>
      </table>
    </panel>
  </row>

  <row>
    <panel>
      <title>Top Source IPs by Auth Failures</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as failures
            from datamodel=Authentication
            where Authentication.action=failure Authentication.user=$user_tok$ Authentication.src=$src_tok$ Authentication.dest_category=$env_tok$
            by Authentication.src
            | rename Authentication.src as src
            | sort - failures
            | head 20
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">20</option>
      </table>
    </panel>

    <panel>
      <title>Possible Password Spray (Many Users from One IP)</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as failures dc(Authentication.user) as distinct_users
            from datamodel=Authentication
            where Authentication.action=failure Authentication.dest_category=$env_tok$
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
      </table>
    </panel>
  </row>

  <!-- ========================= -->
  <!-- Network -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>Top Destinations by Outbound Bytes</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t sum(Network_Traffic.bytes_out) as bytes_out
            from datamodel=Network_Traffic
            where Network_Traffic.dest_category=$env_tok$
            by Network_Traffic.dest
            | rename Network_Traffic.dest as dest
            | sort - bytes_out
            | head 20
            | eval bytes_out=round(bytes_out/1024/1024,2)
            | rename bytes_out as MB_out
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">20</option>
      </table>
    </panel>

    <panel>
      <title>Top Sources by Outbound Bytes</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t sum(Network_Traffic.bytes_out) as bytes_out
            from datamodel=Network_Traffic
            where Network_Traffic.src=$src_tok$ Network_Traffic.dest_category=$env_tok$
            by Network_Traffic.src
            | rename Network_Traffic.src as src
            | sort - bytes_out
            | head 20
            | eval bytes_out=round(bytes_out/1024/1024,2)
            | rename bytes_out as MB_out
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">20</option>
      </table>
    </panel>
  </row>

  <!-- ========================= -->
  <!-- Endpoint / Processes -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>New/Unusual Processes (By Host)</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as executions
            from datamodel=Endpoint.Processes
            where Processes.dest_category=$env_tok$
            by Processes.dest Processes.process_name
            | rename Processes.dest as host Processes.process_name as process
            | sort - executions
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
      <title>Rare Process Names (Low Frequency)</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as executions
            from datamodel=Endpoint.Processes
            where Processes.dest_category=$env_tok$
            by Processes.process_name
            | rename Processes.process_name as process
            | where executions &lt;= 5
            | sort executions
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
      </table>
    </panel>
  </row>

  <!-- ========================= -->
  <!-- Malware + Changes -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>Malware Detections (Top Signatures)</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as detections
            from datamodel=Malware
            where Malware.dest_category=$env_tok$
            by Malware.signature Malware.dest Malware.file_name
            | rename Malware.signature as signature Malware.dest as host Malware.file_name as file
            | sort - detections
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
      <title>Privileged Changes (Accounts / Groups)</title>
      <table>
        <search>
          <query>
            | tstats summariesonly=t allow_old_summaries=t count as changes
            from datamodel=Change
            where Change.dest_category=$env_tok$
              (Change.object_category=account OR Change.object_category=group OR Change.object_category=privilege)
            by Change.user Change.object Change.action Change.dest
            | rename Change.user as actor Change.object as object Change.action as action Change.dest as target
            | sort - changes
            | head 50
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">50</option>
        <option name="wrap">true</option>
      </table>
    </panel>
  </row>

  <!-- ========================= -->
  <!-- Drilldowns -->
  <!-- ========================= -->
  <row>
    <panel>
      <title>Raw Authentication Events (For Drilldown)</title>
      <table>
        <search>
          <query>
            | from datamodel:Authentication.Authentication
            | search action=* user=$user_tok$ src=$src_tok$ dest_category=$env_tok$
            | table _time user src dest app action signature vendor_product
            | sort - _time
            | head 200
          </query>
          <earliest>$time_tok.earliest$</earliest>
          <latest>$time_tok.latest$</latest>
        </search>
        <option name="count">200</option>
        <option name="wrap">true</option>

        <drilldown>
          <set token="user_tok">$row.user$</set>
          <set token="src_tok">$row.src$</set>
        </drilldown>
      </table>
    </panel>
  </row>

</form>
