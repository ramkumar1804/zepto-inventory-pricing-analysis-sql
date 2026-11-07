drop table if exists zepto;

create table zepto (
sku_id SERIAL PRIMARY KEY,
category VARCHAR(120),
name VARCHAR(150) NOT NULL,
mrp NUMERIC(8,2),
discountPercent NUMERIC(5,2),
availableQuantity INTEGER,
discountedSellingPrice NUMERIC(8,2),
weightInGms INTEGER,
outOfStock BOOLEAN,	
quantity INTEGER
);

--DATA EXPLORATION

--COUNT OF ROWS
select count(*) from zepto;

--SAMPLE DATA
SELECT * FROM zepto
LIMIT 10;

--NULL VALUES
SELECT * FROM zepto
WHERE name IS NULL
OR
category IS NULL
OR
mrp IS NULL
OR
discountPercent IS NULL
OR
discountedSellingPrice IS NULL
OR
weightInGms IS NULL
OR
availableQuantity IS NULL
OR
outOfStock IS NULL
OR
quantity IS NULL;

--DIFFERENT PRODUCT CATEGORIES
SELECT DISTINCT category
FROM zepto
ORDER BY category;

--PRODUCTS IN STOCK VS OUT OF STOCK
SELECT outOfStock, COUNT(sku_id)
FROM zepto
GROUP BY outOfStock;

--PRODUCT NAMES PRESENT MULTIPLE TIMES
SELECT name, COUNT(sku_id) AS "Number of SKUs"
FROM zepto
GROUP BY name
HAVING count(sku_id) > 1
ORDER BY count(sku_id) DESC;

--DATA CLEANING

--PRODUCTS WITH PRICE = 0
SELECT * FROM zepto
WHERE mrp = 0 OR discountedSellingPrice = 0;

DELETE FROM zepto
WHERE mrp = 0;

--CONVERT PAISE TO RUPEES
UPDATE zepto
SET mrp = mrp / 100.0,
discountedSellingPrice = discountedSellingPrice / 100.0;

SELECT mrp, discountedSellingPrice FROM zepto;

--DATA ANALYSIS

-- Q1. Find the top 10 best-value products based on the discount percentage.

SELECT DISTINCT name, mrp, discountPercent
FROM zepto
ORDER BY discountPercent DESC
LIMIT 10;

--Q2.What are the Products with High MRP but Out of Stock

SELECT DISTINCT name,mrp
FROM zepto
WHERE outOfStock = TRUE and mrp > 300
ORDER BY mrp DESC;

--Q3.Calculate Estimated Revenue for each category

SELECT category,
SUM(discountedSellingPrice * availableQuantity) AS total_revenue
FROM zepto
GROUP BY category
ORDER BY total_revenue;

-- Q4. Find all products where MRP is greater than ₹500 and discount is less than 10%.

SELECT DISTINCT name, mrp, discountPercent
FROM zepto
WHERE mrp > 500 AND discountPercent < 10
ORDER BY mrp DESC, discountPercent DESC;

-- Q5. Identify the top 5 categories offering the highest average discount percentage.

SELECT category,
ROUND(AVG(discountPercent),2) AS avg_discount
FROM zepto
GROUP BY category
ORDER BY avg_discount DESC
LIMIT 5;

-- Q6. Find the price per gram for products above 100g and sort by best value.

SELECT DISTINCT name, weightInGms, discountedSellingPrice,
ROUND(discountedSellingPrice/weightInGms,2) AS price_per_gram
FROM zepto
WHERE weightInGms >= 100
ORDER BY price_per_gram;

--Q7.Group the products into categories like Low, Medium, Bulk.

SELECT DISTINCT name, weightInGms,
CASE WHEN weightInGms < 1000 THEN 'Low'
	WHEN weightInGms < 5000 THEN 'Medium'
	ELSE 'Bulk'
	END AS weight_category
FROM zepto;

--Q8.What is the Total Inventory Weight Per Category 

SELECT category,
SUM(weightInGms * availableQuantity) AS total_weight
FROM zepto
GROUP BY category
ORDER BY total_weight;

-- Q9. Detect products tagged under multiple categories (data quality)

SELECT name, mrp, weightInGms, COUNT(DISTINCT category) AS categories_tagged
FROM zepto
GROUP BY name, mrp, discountPercent, availableQuantity,
         discountedSellingPrice, weightInGms, outOfStock, quantity
HAVING COUNT(DISTINCT category) > 1
ORDER BY categories_tagged DESC;

-- Q10. Deduplicated view for product-level analysis

CREATE OR REPLACE VIEW zepto_unique AS
SELECT DISTINCT ON (name, mrp, discountPercent, availableQuantity,
                    discountedSellingPrice, weightInGms, outOfStock, quantity) *
FROM zepto
ORDER BY name, mrp, discountPercent, availableQuantity,
         discountedSellingPrice, weightInGms, outOfStock, quantity, sku_id;

-- Q11. Stock-out rate per category

SELECT category, COUNT(*) AS total_skus,
       SUM(CASE WHEN outOfStock THEN 1 ELSE 0 END) AS oos_skus,
       ROUND(100.0 * SUM(CASE WHEN outOfStock THEN 1 ELSE 0 END) / COUNT(*), 2) AS oos_rate_pct
FROM zepto
GROUP BY category
ORDER BY oos_rate_pct DESC;

-- Q12. Revenue share per category (window function)

SELECT category,
       SUM(discountedSellingPrice * availableQuantity) AS revenue,
       ROUND(100.0 * SUM(discountedSellingPrice * availableQuantity)
             / SUM(SUM(discountedSellingPrice * availableQuantity)) OVER (), 2) AS revenue_share_pct
FROM zepto
GROUP BY category
ORDER BY revenue DESC;

-- Q13. Top 3 products by estimated revenue in each category (ROW_NUMBER)

WITH ranked AS (
  SELECT category, name, weightInGms,
         discountedSellingPrice * availableQuantity AS sku_revenue,
         ROW_NUMBER() OVER (PARTITION BY category
                            ORDER BY discountedSellingPrice * availableQuantity DESC) AS rnk
  FROM zepto)
SELECT * FROM ranked WHERE rnk <= 3 ORDER BY category, rnk;

-- Q14. Discount bands vs stock-out rate

SELECT CASE WHEN discountPercent = 0 THEN '0%'
            WHEN discountPercent < 10 THEN '1-9%'
            WHEN discountPercent < 20 THEN '10-19%'
            ELSE '20%+' END AS discount_band,
       COUNT(*) AS skus,
       ROUND(AVG(mrp), 2) AS avg_mrp,
       ROUND(100.0 * SUM(CASE WHEN outOfStock THEN 1 ELSE 0 END) / COUNT(*), 2) AS oos_rate_pct
FROM zepto
GROUP BY 1
ORDER BY MIN(discountPercent);

-- Q15. Pareto: categories making up ~80% of revenue (CTE + cumulative window)

WITH cat_rev AS (
  SELECT category, SUM(discountedSellingPrice * availableQuantity) AS revenue
  FROM zepto GROUP BY category),
pareto AS (
  SELECT category, revenue,
         ROUND(100.0 * SUM(revenue) OVER (ORDER BY revenue DESC)
               / SUM(revenue) OVER (), 2) AS cumulative_pct
  FROM cat_rev)
SELECT * FROM pareto ORDER BY revenue DESC;

-- Q16. Same product, different pack sizes: price-per-gram gap

WITH ppg AS (
  SELECT name, weightInGms, discountedSellingPrice / weightInGms AS price_per_gram
  FROM zepto WHERE weightInGms > 0)
SELECT name, COUNT(*) AS pack_variants,
       ROUND(MIN(price_per_gram), 4) AS min_ppg,
       ROUND(MAX(price_per_gram), 4) AS max_ppg,
       ROUND(MAX(price_per_gram) / MIN(price_per_gram), 2) AS price_gap_x
FROM ppg
GROUP BY name
HAVING COUNT(*) > 1 AND MIN(price_per_gram) > 0
ORDER BY price_gap_x DESC
LIMIT 10;

