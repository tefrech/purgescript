-- GOAL OF THIS TOOL:
-- Isolate customer records who had vacated ALL of their leases prior to the Cut Off date 
-- and purge all related transaction records

USE dam;
CREATE TABLE PurgeParameters (SiteID Text(3), CutOff Date);
DROP TABLE CustAcctPurgeFinalReport;
CREATE TABLE CustAcctPurgeFinalReport (
	SiteID Text
    , CustomerAccount Int
    , CustomerFirstName Text
    , CustomerLastName Text
    , UnitMask Text
    , CustomerUnitMoveInDate Date
    , CustomerUnitMoveOutDate Date
    );
CREATE TABLE ResultsCheck (
	SiteID Text
    , CustomerAccount Int
    , CustomerFirstName Text
    , CustomerLastName Text
    , UnitMask Text
    , CustomerUnitStatus Text
    , CustomerUnitMoveInDate Date
    , CustomerUnitMoveOutDate Date
    , PurgeStatus Text
    , Qualify Text
    );

DELETE FROM CustAcctPurgeFinalReport;

INSERT INTO PurgeParameters ( SiteID, CutOff )
VALUES ('XXL', '2016-01-01');

SELECT * FROM purgeparameters;

-- Building the report of who''s going to be purged

INSERT INTO CustAcctPurgeFinalReport
WITH 
	-- Select all vacant leases
	CustAcctVacant AS (
		SELECT SiteID, CustomerAccount
		FROM CustomerUnits
		WHERE CustomerUnitStatus = 2 
        AND CustomerUnits.SiteID IN (SELECT SiteID FROM PurgeParameters) 
        AND CustomerUnitMoveOutDate < ANY (SELECT CutOff FROM PurgeParameters))
	-- Select all leases vacated after the CutOff
	, CustAcctVacantAfter AS (
		SELECT SiteID, CustomerAccount
		FROM CustomerUnits
		WHERE CustomerUnitStatus = 2 
        AND CustomerUnits.SiteID IN (SELECT SiteID FROM PurgeParameters) 
        AND CustomerUnitMoveOutDate >= ANY (SELECT CutOff FROM PurgeParameters))
	-- Select all occupied leases
	, CustAcctOccupied AS (
		SELECT CustomerUnits.SiteID, CustomerUnits.CustomerAccount
		FROM CustomerUnits
		WHERE CustomerUnits.CustomerUnitStatus IN (1, 5, 6) 
        AND CustomerUnits.SiteID IN (SELECT SiteID FROM PurgeParameters))
	-- Join CustAcctVacant with CustAcctOccupied and only keep the customers that do NOT exist in CustAcctOccupied
	, AcctFiltered AS (
		SELECT DISTINCT CustAcctVacant.CustomerAccount, CustAcctVacant.SiteID 
		FROM CustAcctVacant 
        LEFT JOIN CustAcctOccupied 
			ON CustAcctVacant.CustomerAccount = CustAcctOccupied.CustomerAccount
            AND CustAcctVacant.SiteID = CustAcctOccupied.SiteID
		WHERE CustAcctOccupied.CustomerAccount IS NULL
        	AND CustAcctOccupied.SiteID IS NULL)
	-- Join AcctFiltered with CustAcctVacantAfter and keep the customers that do NOT exist in CustAcctVacantAfter
	, CustAcctPurge AS (
		SELECT DISTINCT AcctFiltered.CustomerAccount, AcctFiltered.SiteID
		FROM AcctFiltered 
		LEFT JOIN CustAcctVacantAfter 
			ON AcctFiltered.SiteID = CustAcctVacantAfter.SiteID
			AND AcctFiltered.CustomerAccount = CustAcctVacantAfter.CustomerAccount
		WHERE CustAcctVacantAfter.CustomerAccount IS NULL 
			AND CustAcctVacantAfter.SiteID IS NULL)
	-- Select all customer records that registered a "Vacant Unit Income," "Reversal," or "Uncollected" transaction AFTER the CutOff
	, VUIAccounts AS (
		SELECT DISTINCT CustomerAccount, SiteID
		FROM Transactions INNER JOIN TransactionDetail ON Transactions.TransactionID=TransactionDetail.TransactionID
		WHERE TransactionDetail.TransactionCode IN (52,122,57) 
			AND Transactions.SiteID IN (SELECT SiteID FROM PurgeParameters)  
			AND TransactionDetail.TransactionFromDate >= (SELECT CutOff FROM PurgeParameters))
	-- Join CustAcctPurge with VUIAccounts and keep the customers that do NOT exist in VUIAccounts
	, CustAcctPurgeFinal AS (
		SELECT DISTINCT CustAcctPurge.CustomerAccount, CustAcctPurge.SiteID
		FROM CustAcctPurge 
		LEFT JOIN VUIAccounts ON CustAcctPurge.CustomerAccount = VUIAccounts.CustomerAccount
			AND (CustAcctPurge.SiteID = VUIAccounts.SiteID)
		WHERE VUIAccounts.CustomerAccount IS NULL AND VUIAccounts.SiteID IS NULL)
--Start to build the output
SELECT Customers.SiteID
	, Customers.CustomerAccount AS Acct
    , Customers.CustomerFirstName AS First_Name
    , Customers.CustomerLastName AS Last_Name
    , Units.UnitMask AS Unit
    , CustomerUnits.CustomerUnitMoveInDate AS Move_In_Date
    , CustomerUnits.CustomerUnitMoveOutDate AS Move_Out_Date
FROM Customers 
INNER JOIN (CustomerUnits INNER JOIN Units ON CustomerUnits.UnitID = Units.UnitID) 
	ON Customers.CustomerAccount=CustomerUnits.CustomerAccount
	AND Customers.SiteID=CustomerUnits.SiteID
JOIN CustAcctPurgeFinal
	ON CustomerUnits.CustomerAccount=CustAcctPurgeFinal.CustomerAccount
	AND Customers.CustomerAccount=CustAcctPurgeFinal.CustomerAccount
-- Adding the category description, as users do not know the IDs
INNER JOIN lookupunitstatus 
	ON CustomerUnits.CustomerUnitStatus = lookupunitstatus.UnitStatusID
WHERE  Customers.SiteID IN 
	(SELECT SiteID FROM PurgeParameters)
AND Customers.CustomerAccount IN 
	(SELECT CustomerAccount FROM CustAcctPurgeFinal)
ORDER BY Customers.CustomerAccount, Units.UnitMask
;

SELECT * FROM CustAcctpurgeFinalReport;


-- INSERT INTO ResultsCheck
SELECT Customers.SiteID
    , Customers.CustomerAccount
    , Customers.CustomerFirstName
    , Customers.CustomerLastName
    , Units.UnitMask AS Unit
    , lookupunitstatus.UnitStatusName AS Status
    , CustomerUnits.CustomerUnitMoveInDate
    , CustomerUnits.CustomerUnitMoveOutDate
    , IF(Customers.CustomerAccount IN 
    	(SELECT CustomerAccount FROM CustAcctPurgeFinalReport), 'PURGE', 'KEEP') 
    	AS PurgeStatus
    , IF(
    	(CustomerUnits.CustomerUnitMoveOutDate < (SELECT CutOff FROM PurgeParameters)) 
    	AND CustomerUnits.CustomerUnitStatus = 2, 'Yes', 'No') 
    	AS Qualify
FROM Customers 
INNER JOIN CustomerUnits
	ON Customers.CustomerAccount = CustomerUnits.CustomerAccount
	AND Customers.SiteID = CustomerUnits.SiteID
INNER JOIN Units 
	ON CustomerUnits.UnitID = Units.UnitID
LEFT JOIN CustAcctPurgeFinalReport
	ON CustomerUnits.CustomerAccount = CustAcctPurgeFinalReport.CustomerAccount
	AND Customers.CustomerAccount = CustAcctPurgeFinalReport.CustomerAccount
    AND Units.UnitMask = custacctpurgefinalreport.unitmask
INNER JOIN lookupunitstatus 
	ON CustomerUnits.CustomerUnitStatus = lookupunitstatus.UnitStatusID
#WHERE  Customers.SiteID IN 
#	(SELECT SiteID FROM PurgeParameters)
#AND Customers.CustomerAccount IN 
#	(SELECT CustomerAccount FROM CustAcctPurgeFinalReport)
ORDER BY Customers.CustomerAccount, Units.UnitMask
;
DELETE FROM resultscheck;
SELECT * FROM resultscheck;

ALTER TABLE units DROP COLUMN CustomerAccount;
