# purgescript
Written by Todd Frech, 2021 in MySQL, originally Microsoft Access
<br>
<br>
<br>
<p><b>Problem:</b> The existing purge tool for an Access-based accounting system removed more records than it should have, affecting the accuracy of clients' financial reports.</p>
<p>
<b>Goal:</b> To build a new tool using SQL that accurately identifies accounts and all related transactional records that qualify to be purged based on two input parameters. For my own practice, I ported the tool to MySQL as well to utilize more modern functions, like Common Table Expressions to run the data through multiple filters in a single query. 
</p><p>
<b>Process:</b> The current tool takes no input and purges accounts with no active spaces as of two years prior. I wanted to give the client the option to choose the Cut Off Date to match their fiscal year. The other input is the unique ID for the location. This allows the tool to be easily run on databases housing data for multiple locations. The first CTE identifies all accounts at the specified location with a vacant space currently attached. The result set is then filtered for accounts with currently active spaces, accounts with active spaces as of the Cut Off Date, and accounts with transactions posted after the Cut Off Date. The account details for the final result set are saved to a temporary table and shared with the client as an Excel sheet. The accounts in the final result set are used to further identify all related transaction records and purge them. The account details are purged from all other tables as well. 
  </p>
  <p>
<b>Outcome:</b> The script accurately identifies qualifying accounts and purges all related records. This leads to faster reporting and processing times while maintaining accurate records for the time range following the Cut Off Date.
</p>
