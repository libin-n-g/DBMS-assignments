DELIMITER $$ 
DROP PROCEDURE IF EXISTS Customer.PrCustomerChurn $$
CREATE PROCEDURE Customer.PrCustomerChurn() -- Replace this with actual database name, Customer and table name (with prefix Pr) that you use
BEGIN -- **************************************************************************************************************

DECLARE VarCurrentTimestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP;
DECLARE VarSourceRowCount, VarTargetRowCount, VarThresholdNbr INTEGER DEFAULT 0;
DECLARE VarTinyIntVal TINYINT;
-- **************************************************************************************************************
SELECT 
  COUNT(*) INTO VarSourceRowCount 
FROM 
  Customer.CustomerChurn_Stage;
-- Replace this with actual database name and table name (e.g., CustomerChurn_Stage) that you use.
SELECT 
  COUNT(*) INTO VarTargetRowCount 
FROM 
  Customer.CustomerChurn;
-- Replace this with actual database name and table name (e.g., CustomerChurn) that you use.
-- (TargetCount * 20%)
SELECT 
  CAST(
    (VarTargetRowCount *.2) AS UNSIGNED INTEGER
  ) INTO VarThresholdNbr 
FROM 
  DUAL;
-- The DUMMY is system table which might vary from database to database. For your database, you need to figure out.
-- ***********************************
-- Fail the Stored Proc if the Source Row Count is less than the Threshold Number (i.e., 20% of the Target Table row count).
-- This ensures that the Target table is not refreshed with incomplete set of Source Data
IF VarSourceRowCount < VarThresholdNbr THEN 
SELECT 
  -129 INTO VarTinyIntVal 
FROM 
  DUAL;
END IF;
-- **************************************************************************************************************
-- DELETE target table rows which are no longer available in source database table.
DELETE FROM 
  Customer.CustomerChurn AS TrgtTbl 
WHERE 
  EXISTS (
    SELECT 
      * 
    FROM 
      (
        SELECT 
          TT.CustomerID -- Primary Key Column(s)
        FROM 
          Customer.CustomerChurn AS TT -- Example table name: CustomerChurn
          LEFT OUTER JOIN Customer.CustomerChurn_Stage AS ST -- Example table name: CustomerChurn_Stage
          ON TT.CustomerId = ST.CustomerId 
        WHERE 
          ST.CustomerId IS NULL
      ) AS SrcTbl 
    WHERE 
      TrgtTbl.CustomerId = SrcTbl.CustomerId
  );
-- **************************UPDATE ROWS THAT CHANGED IN SOURCE******************************************
-- Update the rows for which new version of rows have arrived as part of delta/incremental feed (i.e., change to non-key values).
UPDATE 
  Customer.CustomerChurn AS TrgtTbl 
  INNER JOIN Customer.CustomerChurn_Stage AS SrcTbl 
  ON TrgtTbl.CustomerId = SrcTbl.CustomerId 
SET 
  TrgtTbl.Surname = SrcTbl.Surname,
  TrgtTbl.CreditScore = SrcTbl.CreditScore ,
  TrgtTbl.Geography = SrcTbl.Geography ,
  TrgtTbl.Gender = SrcTbl.Gender ,
  TrgtTbl.Age = SrcTbl.Age ,
  TrgtTbl.Balance = SrcTbl.Balance ,
  TrgtTbl.Exited = SrcTbl.Exited ,
  TrgtTbl.ChangeDtm = VarCurrentTimestamp 
WHERE 
  (
    COALESCE(TrgtTbl.Surname, '*') <> COALESCE(SrcTbl.Surname, '*') 
    OR COALESCE(TrgtTbl.CreditScore, '*') <> COALESCE(SrcTbl.CreditScore, '*') 
    OR COALESCE(TrgtTbl.Geography, '*') <> COALESCE(SrcTbl.Geography, '*') 
    OR COALESCE(TrgtTbl.Gender, '*') <> COALESCE(SrcTbl.Gender, '*') 
    OR COALESCE(TrgtTbl.Age, '*') <> COALESCE(SrcTbl.Age, '*') 
    OR COALESCE(TrgtTbl.Balance, '*') <> COALESCE(SrcTbl.Balance, '*') 
    OR COALESCE(TrgtTbl.Exited, '*') <> COALESCE(SrcTbl.Exited, '*')
  );
-- ****************************INSERT BRAND NEW ROWS INTO TARGET****************************************
-- Identify brand new rows in source table and load into target table.
INSERT INTO Customer.CustomerChurn (
  CustomerId, Surname, CreditScore, 
  Geography, Gender, Age, Balance, Exited, 
  SourceSystemNm, CreateAgentId, CreateDtm, 
  ChangeAgentId, ChangeDtm
) 
SELECT 
  SrcTbl.CustomerId, 
  SrcTbl.Surname, 
  SrcTbl.CreditScore, 
  SrcTbl.Geography, 
  SrcTbl.Gender, 
  SrcTbl.Age, 
  SrcTbl.Balance, 
  SrcTbl.Exited, 
  'Kaggle-CSV' AS SourceSystemNm, 
  current_user() AS CreateAgentId, 
  VarCurrentTimestamp AS CreateDtm, 
  current_user() AS ChangeAgentId, 
  VarCurrentTimestamp AS ChangeDtm 
FROM 
  Customer.CustomerChurn_Stage AS SrcTbl 
  INNER JOIN (
    SELECT 
      ST.CustomerId 
    FROM 
      Customer.CustomerChurn_Stage AS ST 
      LEFT OUTER JOIN Customer.CustomerChurn AS TT ON ST.CustomerId = TT.CustomerId 
    WHERE 
      TT.CustomerId IS NULL
  ) AS ChgdNew ON SrcTbl.CustomerId = ChgdNew.CustomerId;
-- **************************************************************************************************************
END$$ 
DELIMITER ;
