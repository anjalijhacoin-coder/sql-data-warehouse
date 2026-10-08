CREATE OR ALTER  PROCEDURE silver.load_silver  AS
BEGIN
DECLARE @start_time DATETIME  , @end_time DATETIME , @batch_start_time DATETIME, @batch_end_time DATETIME; 

BEGIN TRY
--silver.crm_cust_info
SET @batch_start_time= GETDATE();

PRINT '================================================';
		PRINT 'Loading silver Layer';
		PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';

		SET @start_time = GETDATE();
PRINT'>>TRUNCATING THE TABLE : silver.crm_cust_info'
TRUNCATE TABLE silver.crm_cust_info

PRINT'>>INSERTING DATA INTO : silver.crm_cust_info'
INSERT INTO silver.crm_cust_info(cust_id
      ,cust_key
      ,cust_firstname
      ,cust_lastname
      ,cust_maritalstatus
      ,cust_gndr
      ,cust_create_date)

SELECT (cust_id)
      ,cust_key
      ,TRIM(cust_firstname) AS cust_firstname
      ,TRIM(cust_lastname) AS cust_lastname
      ,
     ( CASE 
      WHEN upper(TRIM(cust_maritalstatus)) =('M')THEN'MARRIED'
        WHEN upper(TRIM(cust_maritalstatus)) =('S') THEN 'SINGLE'
        ELSE 'n\a'
        END)AS cust_maritalstatus--Normalise marital status values to readable format
    ,
     ( CASE 
      WHEN upper(TRIM(cust_gndr)) =('M') THEN 'MALE'
      WHEN upper(TRIM(cust_gndr ))=('F') THEN 'FEMALE'
      ELSE 'n/a'
      END) AS cust_gndr,--Normalise gender values as readable format

 
 cust_create_date
  FROM
 (SELECT * ,ROW_NUMBER() OVER(PARTITION BY cust_id ORDER BY cust_create_date desc ) AS flag_last
 from [bronze].[crm_cust_info] WHERE cust_id IS NOT NULL)t
 WHERE flag_last=1;

 SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';


------------------------------------------------------------
--silver.crm_prd_info
SET @start_time=GETDATE();

 PRINT'>>TRUNCATING THE TABLE :  silver.crm_prd_info'
TRUNCATE TABLE  silver.crm_prd_info

PRINT'>>INSERTING DATA INTO :  silver.crm_prd_info'
INSERT INTO silver.crm_prd_info([prd_id]
      ,[cat_id]
      ,[prd_key]
      ,[prd_nm]
      ,[prd_cost]
      ,[prd_line]
      ,[prd_start_dt]
      ,[prd_end_dt]
      ,[dwh_create_date])
      

 SELECT prd_id,
 REPLACE(SUBSTRING(prd_key,1,5),'-','_') AS cat_id,
 SUBSTRING(prd_key,7,LEN(prd_key)) AS prd_key,
 prd_nm,     
 ISNULL( prd_cost,0)AS prd_cost,
 CASE
 WHEN UPPER(prd_line) ='R' THEN 'Road'
 WHEN UPPER(prd_line) ='M' THEN 'Mountain'
 WHEN UPPER(prd_line) ='S' THEN 'Other Sales'
 WHEN UPPER(prd_line) ='T' THEN 'Touring'
 ELSE 'n/a'
 END AS prd_line,

       
 CAST(prd_start_dt AS DATE),
 CAST
   (LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)-1
   AS DATE) AS prd_end_dt,
   GETDATE() AS dwh_create_date
      
  FROM bronze.crm_prd_info
  SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';


------------------------------------------------------------
-- silver.crm_sales_details
SET @start_time=GETDATE();
PRINT'>>TRUNCATING THE TABLE : silver.crm_sales_details '
TRUNCATE TABLE silver.crm_sales_details

PRINT'>>INSERTING DATA INTO : silver.crm_sales_details'

INSERT INTO silver.crm_sales_details(
 sls_ord_num 
      ,sls_prd_key  
      ,sls_cust_id 
      ,sls_order_dt 
      ,sls_ship_dt 
      ,sls_due_dt 
      ,sls_sales 
      ,sls_quantity 
      ,sls_price 
      ) 
      SELECT sls_ord_num
      ,sls_prd_key
      ,sls_cust_id
      ,CASE 
       WHEN  sls_order_dt=0 OR LEN(sls_order_dt)!=8 THEN NULL
       ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE)
       END
       AS sls_order_dt,
     
     CASE 
       WHEN sls_ship_dt=0 OR LEN(sls_ship_dt)!=8 THEN NULL
       ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE)
       END 
      AS sls_ship_dt
      , 
     CASE 
       WHEN sls_due_dt=0 OR LEN(sls_due_dt)!=8 THEN NULL
       ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE)
       END 
       AS sls_due_dt
     ,CASE 
       WHEN  sls_sales IS NULL OR  sls_sales<=0 OR  sls_sales != sls_quantity * ABS(sls_price )THEN sls_quantity * ABS(sls_price)
       ELSE  sls_sales
       END AS sls_sales--Recalculate sales if if original value is missing or incorrect
      ,sls_quantity
      ,CASE
 WHEN sls_price IS NULL OR   sls_price<=0 OR   sls_price != sls_sales/sls_quantity THEN  sls_sales/NULLIF(sls_quantity,0)
       ELSE   sls_price
       END AS sls_price--Derive price if original  value is invalid
      
     
  FROM [bronze].[crm_sales_details]
  SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';
 ------------------------------------------------------------
        PRINT '------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '------------------------------------------------';
		
		
--silver.erp_cust_az12
SET @start_time = GETDATE();
  

PRINT'>>TRUNCATING THE TABLE : silver.erp_cust_az12 '
TRUNCATE TABLE silver.erp_cust_az12

PRINT'>>INSERTING DATA INTO : silver.erp_cust_az12'


INSERT INTO silver.erp_cust_az12(cid,
                                 bdate,
                                 gen)

SELECT 
CASE 
WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid,4,LEN(cid))--Remove NAS% prefix If Present
ELSE cid
END AS cid ,
      CASE 
      WHEN bdate  > GETDATE() THEN NULL--Set Future Birtdates To Null
      ELSE bdate
      END AS bdate,
     CASE 
     WHEN UPPER(TRIM(gen)) IN ('FEMALE' ,'F') THEN 'Female'
     WHEN UPPER(TRIM(gen)) IN ('MALE' ,'M' )  THEN 'Male'
      ELSE 'n/a'
     END AS gen--Normalise Gender Values And Handle Unknown Cases
  FROM bronze.erp_cust_az12
  SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';
  
------------------------------------------------------------
--silver.erp_loc_a101
SET @start_time=GETDATE();

PRINT'>>TRUNCATING THE TABLE :silver.erp_loc_a101'
TRUNCATE TABLE silver.erp_loc_a101

PRINT'>>INSERTING DATA INTO : silver.erp_loc_a101'
INSERT INTO silver.erp_loc_a101(cid,cntry)

SELECT 
REPLACE(cid,'-','') AS cid,
CASE 
WHEN TRIM(cntry) IN ('US' , 'USA') THEN 'United states'
WHEN TRIM(cntry) =  '' OR cntry IS NULL THEN 'n/a'
WHEN TRIM(cntry) = 'DE' THEN 'Germany'
ELSE TRIM(cntry)
END
cntry 
FROM bronze.erp_loc_a101--Normalise & Handle Missing Or Blank Country Codes
SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';
------------------------------------------------------------

--silver.erp_px_cat_g1v2
SET @start_time=GETDATE();

PRINT'>>TRUNCATING TABLE silver.erp_px_cat_g1v2'

TRUNCATE TABLE silver.erp_px_cat_g1v2
PRINT'>>INSERTING DATA INTO:silver.erp_px_cat_g1v2'

INSERT INTO silver.erp_px_cat_g1v2
(id,
cat,
subcat,
maintenance)

SELECT  
id ,
cat,
subcat,
maintenance
FROM bronze.erp_px_cat_g1v2
SET @end_time = GETDATE();
		PRINT '>> Load Duration: ' + CAST(DATEDIFF(second, @start_time, @end_time) AS NVARCHAR) + ' seconds';
		PRINT '>> -------------';


		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT ' >> Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='
	END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING BRONZE LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END;
EXEC silver.load_silver
