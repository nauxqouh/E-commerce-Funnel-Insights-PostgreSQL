SET SEARCH_PATH = hqtcsdl; 

-- show database
SELECT * FROM users;
SELECT * FROM events;
SELECT * FROM event_identifier;
SELECT * FROM campaign_identifier;
SELECT * FROM page_hierarchy;

-- 1. The percentage of visits that have purchase 'Purchase' event.
SELECT
	ROUND(
		COUNT (DISTINCT visit_id)*100.0/(SELECT COUNT (DISTINCT visit_id) FROM events), 
		2
	) as pct_purchase
FROM events e
JOIN event_identifier e_id ON e_id.event_type = e.event_type
WHERE event_name = 'Purchase';

-- 2. The percentage of accessing checkout page but not purchasing.
WITH checkout_page_visits AS (
	SELECT DISTINCT e.visit_id
	FROM events e
	JOIN page_hierarchy p ON p.page_id = e.page_id
	WHERE page_name = 'Checkout'
),
having_purchase_visits AS (
	SELECT DISTINCT e.visit_id
	FROM events e
	JOIN event_identifier e_id ON e_id.event_type = e.event_type
	WHERE event_name = 'Purchase'
)
SELECT 
	ROUND(
		COUNT(*)*100.0/(SELECT COUNT(*) FROM checkout_page_visits),
		2
	) as checkout_no_purchase_pct
FROM checkout_page_visits c
WHERE c.visit_id NOT IN (SELECT visit_id FROM having_purchase_visits);

-- 3. Finding the 3 most view pages.
SELECT
	page_name,
	COUNT(*) as page_views
FROM events e
JOIN page_hierarchy p ON p.page_id = e.page_id
JOIN event_identifier e_id ON e_id.event_type = e.event_type
WHERE event_name = 'Page View'
GROUP BY page_name
ORDER BY page_views desc
LIMIT 3;

-- 4. The views and adds to cart for each product category
SELECT
	product_category,
	COUNT(CASE WHEN event_name = 'Page View' THEN 1 END) page_views,
	COUNT(CASE WHEN event_name = 'Add to Cart' THEN 1 END) add_to_carts
FROM events e
JOIN event_identifier e_id ON e_id.event_type = e.event_type
JOIN page_hierarchy p ON p.page_id = e.page_id
GROUP BY product_category
HAVING product_category IS NOT NULL;

-- 5. The 3 most purchased product
WITH add_to_cart_products AS (
	SELECT
		DISTINCT visit_id,
		page_name as product_name
	FROM events e
	JOIN event_identifier e_id ON e_id.event_type = e.event_type
	JOIN page_hierarchy p ON p.page_id = e.page_id
	WHERE event_name = 'Add to Cart' 
		AND product_id IS NOT NULL
),
having_purchase_visits AS (
	SELECT DISTINCT e.visit_id
	FROM events e
	JOIN event_identifier e_id ON e_id.event_type = e.event_type
	WHERE event_name = 'Purchase'
)
SELECT
	product_name,
	COUNT(*) as purchase_num
FROM add_to_cart_products
WHERE visit_id IN (SELECT visit_id FROM having_purchase_visits)
GROUP BY product_name
ORDER BY purchase_num desc
LIMIT 3;

-- 6. Create summary table for products
-- How many times was each product viewed?
-- How many times was each product added to the cart?
-- How many times was each product added to the cart but not purchased (abandoned)?
-- How many times was each product purchased?
CREATE TABLE product_events AS
WITH having_purchase_visits AS (
	SELECT DISTINCT e.visit_id
	FROM events e
	JOIN event_identifier e_id ON e_id.event_type = e.event_type
	WHERE event_name = 'Purchase'
)
SELECT 
	product_id,
	page_name as product_name,
	COUNT(CASE WHEN event_name = 'Page View' THEN 1 END) as page_views,
	COUNT(CASE WHEN event_name = 'Add to Cart' THEN 1 END) as add_to_carts,
	COUNT(
		CASE 
			WHEN event_name = 'Add to Cart' 
				AND visit_id NOT IN (SELECT visit_id FROM having_purchase_visits)
			THEN 1
		END
	) as cart_abandonments,
	COUNT(
		CASE 
			WHEN event_name = 'Add to Cart' 
				AND visit_id IN (SELECT visit_id FROM having_purchase_visits)
			THEN 1
		END
	) as purchases
FROM events e
JOIN event_identifier e_id ON e_id.event_type = e.event_type
JOIN page_hierarchy p ON p.page_id = e.page_id
WHERE product_id IS NOT NULL
GROUP BY product_id, page_name
ORDER BY product_id;

SELECT * FROM product_events;

-- 7. Create summary table for product categories.
CREATE TABLE product_category_events AS
SELECT
	product_category,
	SUM(page_views) as page_views,
	SUM(add_to_carts) as add_to_carts,
	SUM(cart_abandonments) as cart_abandonments,
	SUM(purchases) as purchases
FROM product_events pe
JOIN page_hierarchy p ON p.product_id = pe.product_id
GROUP BY product_category;

SELECT * FROM product_category_events;

-- 8. The product has the most views, add to carts and purchases
SELECT product_id, product_name
FROM product_events
ORDER BY 
	page_views desc,
	add_to_carts desc,
	purchases desc
LIMIT 1;

-- Each product for each criteria
SELECT 'Most Page Views' AS criteria, product_name
FROM (
  SELECT product_name
  FROM product_events
  ORDER BY page_views DESC
  LIMIT 1
)
UNION ALL
SELECT 'Most Add to Carts', product_name
FROM (
  SELECT product_name
  FROM product_events
  ORDER BY add_to_carts DESC
  LIMIT 1
)
UNION ALL
SELECT 'Most Purchases', product_name
FROM (
  SELECT product_name
  FROM product_events
  ORDER BY purchases DESC
  LIMIT 1
);


-- 9. The product is most likely to be abandoned (added to cart but not purrchased).
SELECT product_id, product_name
FROM product_events
ORDER BY cart_abandonments desc
LIMIT 1;

-- 10. The product has the highest view to purchase ratio.
SELECT 
	product_id, 
	product_name,
	ROUND(purchases*100.0/page_views, 2) as view_to_purchase_pct
FROM product_events
WHERE page_views > 0
ORDER BY view_to_purchase_pct desc
LIMIT 1;

-- 11. The average conversion rate from view to cart add.
SELECT 
	ROUND(SUM(add_to_carts)/SUM(page_views), 3) as avg_view_to_cart_add
FROM product_events;

-- 12. The average conversion rate from cart add to purchase.
SELECT 
	ROUND(SUM(purchases)/SUM(add_to_carts), 2) as avg_cart_add_to_purchase
FROM product_events;