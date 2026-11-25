# E-Commerce-Data-Analysis-SQL-Automation-Python-EDA-Power-BI

Project Overview

Developed an end to end e-commerce analytics solution to transform raw transactional data into actionable business insights. The project combines advanced SQL analysis, Python based exploratory and statistical analysis, analytical data modelling, and interactive Power BI reporting to evaluate business performance, customer purchasing behaviour, product performance, seller performance, and delivery operations.

The objective was to identify key business trends, understand customer value drivers, evaluate operational performance, and provide evidence based recommendations to support management decision making.

Technology Stack

SQL Server: Data exploration, transformation, advanced queries, business KPIs, cohort analysis, and automation.

Python: Pandas, NumPy, Matplotlib, Seaborn, and SciPy for EDA, segmentation, and statistical analysis.

Power BI: Data modelling, DAX, KPI reporting, and interactive dashboards.

SQL Server Agent: Scheduled monthly SQL job execution and automated recurring reporting.

Key Analytical Work

1. SQL – Business Intelligence & Automation

Performed relational data exploration, joins, aggregations, CTEs, and window-function analysis.

Developed business queries for sales, orders, customers, products, and sellers.

Conducted customer cohort and retention analysis.

Implemented recurring monthly SQL automation using SQL Server Agent, scheduling reporting queries to execute at the beginning of each month.

Reduced dependency on manual execution and established a repeatable monthly reporting workflow.

2. Python – Customer & Operational Analytics

Conducted data cleaning, exploratory analysis, and feature preparation.

Implemented RFM-based customer segmentation.

Compared one-time and repeat purchasers using purchase frequency and monetary value.

Evaluated delivery performance against customer review scores.

Aggregated merchandise value at the order-product-category level.

Assessed category sample sizes for reliable statistical comparisons.

3. Statistical Analysis

Applied the Mann–Whitney U test to evaluate monetary-value differences between one-time and repeat customers.

Calculated rank-biserial correlation to measure effect size.

Compared average review scores across late and on-time deliveries.

Evaluated product-category order counts, mean values, and median values to identify suitable groups for further testing.

4. Power BI – Management Reporting

Developed an interactive business intelligence dashboard.

Focused on business KPIs, sales performance, customer behaviour, product categories, delivery performance, and customer satisfaction.

Designed reporting to support management-level monitoring and business decisions.

Key Business Insights & Findings

The project investigated several business-critical relationships:

Business Area

Key Finding / Analytical Outcome

Customer value

Compared median monetary value between one-time and repeat purchasers.

Customer behaviour

Used purchase frequency to distinguish repeat purchasing from one-time transactions.

Statistical significance

Applied the Mann–Whitney U test to evaluate whether customer monetary values differ significantly.

Effect size

Used rank-biserial correlation to quantify the magnitude and direction of the customer-group difference.

Delivery performance

Classified delivered orders as late or on time using actual versus estimated delivery dates.

Customer satisfaction

Compared average review scores across delivery-performance groups.

Product performance

Aggregated merchandise value across product categories at the order level.

Analytical reliability

Evaluated category-level sample sizes and value distributions before further statistical comparisons.
