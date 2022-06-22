-- Written by Todd Frech, 2021 in MySQL, originally Microsoft Access

CREATE TABLE PurgeParameters (SiteID Text(3), CutOff Date);

CREATE TABLE AccountsToPurgeFinalReport (
	SiteID Text
    , Account Int
    , FirstName Text
    , LastName Text
    , Space Text
    , StartDate Date
    , EndDate Date
    );
CREATE TABLE ResultsCheck (
	SiteID Text
    , Account Int
    , FirstName Text
    , LastName Text
    , Space Text
    , CustAccountsStatus Text
    , StartDate Date
    , EndDate Date
    , PurgeStatus Text
    , Qualify Text
    );

-- Building the report of accounts to be purged
INSERT INTO AccountsToPurgeFinalReport
WITH 
	-- Select all vacant accounts
	VacantAccounts AS (
		SELECT SiteID, Account
		FROM CustAccounts
		WHERE CustAccountsStatus = 2 
        AND CustAccounts.SiteID IN (SELECT SiteID FROM PurgeParameters) 
        AND EndDate < ANY (SELECT CutOff FROM PurgeParameters))
	-- Select all accounts vacated after the CutOffDate
	, VacantAccountsAfter AS (
		SELECT SiteID, Account
		FROM CustAccounts
		WHERE CustAccountsStatus = 2 
        AND CustAccounts.SiteID IN (SELECT SiteID FROM PurgeParameters) 
        AND EndDate >= ANY (SELECT CutOff FROM PurgeParameters))
	-- Select all active accounts
	, ActiveAccounts AS (
		SELECT CustAccounts.SiteID, CustAccounts.Account
		FROM CustAccounts
		WHERE CustAccounts.CustAccountsStatus IN (1, 5, 6) 
        AND CustAccounts.SiteID IN (SELECT SiteID FROM PurgeParameters))
	-- Join VacantAccounts with ActiveAccounts and only keep the accounts that do NOT exist in ActiveAccounts
	, AccountsFiltered AS (
		SELECT DISTINCT VacantAccounts.Account, VacantAccounts.SiteID 
		FROM VacantAccounts 
        LEFT JOIN ActiveAccounts 
			ON VacantAccounts.Account = ActiveAccounts.Account
            AND VacantAccounts.SiteID = ActiveAccounts.SiteID
		WHERE ActiveAccounts.Account IS NULL
        	AND ActiveAccounts.SiteID IS NULL)
	-- Join AccountsFiltered with VacantAccountsAfter and keep the accounts that do NOT exist in VacantAccountsAfter
	, AccountsToPurge AS (
		SELECT DISTINCT AccountsFiltered.Account, AccountsFiltered.SiteID
		FROM AccountsFiltered 
		LEFT JOIN VacantAccountsAfter 
			ON AccountsFiltered.SiteID = VacantAccountsAfter.SiteID
			AND AccountsFiltered.Account = VacantAccountsAfter.Account
		WHERE VacantAccountsAfter.Account IS NULL 
			AND VacantAccountsAfter.SiteID IS NULL)
	-- Select all accounts that registered a transaction AFTER the Cut Off Date
	, VUIAccounts AS (
		SELECT DISTINCT Account, SiteID
		FROM Trax INNER JOIN TraxDetail ON Trax.TraxID = TraxDetail.TraxID
		WHERE TraxDetail.TraxCode IN (52,122,57) 
			AND Trax.SiteID IN (SELECT SiteID FROM PurgeParameters)  
			AND TraxDetail.TraxFromDate >= (SELECT CutOff FROM PurgeParameters))
	-- Join AccountsToPurge with VUIAccounts and keep the accounts that do NOT exist in VUIAccounts
	, AccountsToPurgeFinal AS (
		SELECT DISTINCT AccountsToPurge.Account, AccountsToPurge.SiteID
		FROM AccountsToPurge 
		LEFT JOIN VUIAccounts ON AccountsToPurge.Account = VUIAccounts.Account
			AND (AccountsToPurge.SiteID = VUIAccounts.SiteID)
		WHERE VUIAccounts.Account IS NULL AND VUIAccounts.SiteID IS NULL)
--Start to build the output
SELECT Accounts.SiteID
	, Accounts.Account
    , Accounts.FirstName
    , Accounts.LastName
    , Spaces.Space
    , CustAccounts.StartDate
    , CustAccounts.EndDate
FROM Accounts 
JOIN (CustAccounts INNER JOIN Spaces ON CustAccounts.ID = Spaces.ID) 
	ON Accounts.Account=CustAccounts.Account
	AND Accounts.SiteID=CustAccounts.SiteID
JOIN AccountsToPurgeFinal
	ON CustAccounts.Account=AccountsToPurgeFinal.Account
	AND Accounts.Account=AccountsToPurgeFinal.Account
JOIN LookupStatus 
	ON CustAccounts.CustAccountsStatus = LookupStatus.StatusID
WHERE  Accounts.SiteID IN 
	(SELECT SiteID FROM PurgeParameters)
AND Accounts.Account IN 
	(SELECT Account FROM AccountsToPurgeFinal)
ORDER BY Accounts.Account, Spaces.Space;


-- This query can be used to validate the final result set prior to removing any data 
SELECT Accounts.SiteID
    , Accounts.Account
    , Accounts.FirstName
    , Accounts.LastName
    , Spaces.Space AS Unit
    , LookupStatus.Name AS Status
    , CustAccounts.StartDate
    , CustAccounts.EndDate
    , IF(Accounts.Account IN 
    	(SELECT Account FROM AccountsToPurgeFinalReport), 'PURGE', 'KEEP') 
    	AS PurgeStatus
    , IF(
    	(CustAccounts.EndDate < (SELECT CutOff FROM PurgeParameters) )
    	AND CustAccounts.CustAccountsStatus = 2, 'Yes', 'No') 
    	AS Qualify
FROM Accounts 
JOIN CustAccounts
	ON Accounts.Account = CustAccounts.Account
	AND Accounts.SiteID = CustAccounts.SiteID
JOIN Spaces 
	ON CustAccounts.ID = Spaces.ID
LEFT JOIN AccountsToPurgeFinalReport
	ON CustAccounts.Account = AccountsToPurgeFinalReport.Account
	AND Accounts.Account = AccountsToPurgeFinalReport.Account
    AND Spaces.Space = AccountsToPurgeFinalReport.Space
JOIN LookupStatus 
	ON CustAccounts.CustAccountsStatus = LookupStatus.ID
ORDER BY Accounts.Account, Spaces.Space;
-- The account records are purged from the source tables and all transaction-related tables based on the Account column, which are not shown. 
