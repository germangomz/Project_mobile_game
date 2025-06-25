SELECT *
FROM mobile_game.sessions;

SELECT *
FROM mobile_game.transactions;

SELECT *
FROM mobile_game.user_info;

SELECT *
FROM mobile_game.users_touches;

-- 1. Revenue по дням и странам
SELECT
	t.event_date AS date,
	ui.country,
	t.product_name,
	sum(t.revenue) AS daily_revenue
FROM mobile_game.transactions t 
JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
GROUP BY t.event_date, t.product_name, ui.country
ORDER BY t.event_date, ui.country;

-- Revenue по сегментам покупателей
SELECT
	t.event_date AS date,
	ui.payer_segment,
	sum(t.revenue) AS daily_revenue
FROM mobile_game.transactions t 
JOIN mobile_game.user_info ui ON t.user_id = ui.user_id
GROUP BY t.event_date, ui.payer_segment
ORDER BY t.event_date, ui.payer_segment;

-- Revenue по каналам
SELECT
	t.event_date AS date,
	ut.channel,
	sum(t.revenue) AS daily_revenue
FROM mobile_game.transactions t 
JOIN mobile_game.users_touches ut ON t.user_id = ut.user_id
GROUP BY t.event_date, ut.channel
ORDER BY t.event_date, ut.channel;

-- 2. DAU по дням и платформам
SELECT 
    DATE(s.session_start_time) AS date,
    ui.platform,
    COUNT(DISTINCT s.user_id) AS dau
FROM 
    mobile_game.sessions s
JOIN 
    mobile_game.user_info ui ON s.user_id = ui.user_id
GROUP BY 
    DATE(s.session_start_time), ui.platform
ORDER BY 
    DATE(s.session_start_time), ui.platform;

-- 3. New installs по дням и каналам (Last Click атрибуция)
WITH last_touch AS (
    SELECT 
        user_id,
        channel,
        touch_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM 
        mobile_game.users_touches
)
SELECT 
    ui.user_start_date AS date,
    lt.channel,
    COUNT(DISTINCT ui.user_id) AS new_installs
FROM 
    mobile_game.user_info ui
LEFT JOIN 
    last_touch lt ON ui.user_id = lt.user_id AND lt.rn = 1
GROUP BY 
    ui.user_start_date, lt.channel
ORDER BY 
    ui.user_start_date, lt.channel;

-- New installs по каналу applovin разрезе payer_segment
WITH last_touch AS (
    SELECT 
        user_id,
        channel,
        touch_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM 
        mobile_game.users_touches
)
SELECT 
    ui.user_start_date AS date,
    ui.payer_segment,
    COUNT(DISTINCT ui.user_id) AS new_installs
FROM 
    mobile_game.user_info ui
LEFT JOIN 
    last_touch lt ON ui.user_id = lt.user_id AND lt.rn = 1
WHERE lt.channel = 'applovin'
GROUP BY 
    ui.user_start_date, payer_segment
ORDER BY 
    ui.user_start_date, payer_segment;

-- 4. Returning users (игравшие более чем через 7 дней после первой сессии)
WITH user_first_session AS (
    SELECT 
        user_id,
        MIN(session_start_time) AS first_session
    FROM 
        mobile_game.sessions
    GROUP BY 
        user_id
),
returning_users AS (
    SELECT 
        s.user_id,
        DATE(s.session_start_time) AS return_date
    FROM 
        mobile_game.sessions s
    JOIN 
        user_first_session ufs ON s.user_id = ufs.user_id
    WHERE 
        DATE(s.session_start_time) > DATE(ufs.first_session) + INTERVAL '7 days'
),
last_touch AS (
    SELECT 
        user_id,
        channel,
        touch_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM 
        mobile_game.users_touches
)
SELECT 
    return_date AS date,
    lt.channel,
    COUNT(DISTINCT ru.user_id) AS returning_users
FROM 
    returning_users ru
LEFT JOIN 
    last_touch lt ON ru.user_id = lt.user_id AND lt.rn = 1
GROUP BY 
    return_date, lt.channel
ORDER BY 
    return_date, lt.channel

-- 5. ARPDAU по дням и платежным сегментам
WITH daily_metrics AS (
    SELECT 
        DATE(s.session_start_time) AS date,
        ui.payer_segment,
        COUNT(DISTINCT s.user_id) AS dau,
        SUM(t.revenue) AS revenue
    FROM 
        mobile_game.sessions s
    LEFT JOIN 
        mobile_game.transactions t ON s.user_id = t.user_id 
        AND DATE(t.event_date) = DATE(s.session_start_time)
    JOIN 
        mobile_game.user_info ui ON s.user_id = ui.user_id
    GROUP BY 
        DATE(s.session_start_time), ui.payer_segment
)
SELECT 
    date,
    payer_segment,
    revenue / NULLIF(dau, 0) AS arpdau
FROM 
    daily_metrics
ORDER BY 
    date, payer_segment;

-- 6. Daily Conversion по странам
SELECT 
    DATE(s.session_start_time) AS date,
    ui.country,
    COUNT(DISTINCT CASE WHEN t.user_id IS NOT NULL THEN s.user_id END) * 100.0 / 
    NULLIF(COUNT(DISTINCT s.user_id), 0) AS conversion_rate
FROM 
    mobile_game.sessions s
LEFT JOIN 
    mobile_game.transactions t ON s.user_id = t.user_id AND 
    DATE(t.event_date) = DATE(s.session_start_time)
JOIN 
    mobile_game.user_info ui ON s.user_id = ui.user_id
GROUP BY 
    DATE(s.session_start_time), ui.country
ORDER BY 
    DATE(s.session_start_time), ui.country;
	
-- Daily Conversion по каналам
WITH last_touch AS (
    SELECT 
        user_id,
        channel,
        touch_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM 
        mobile_game.users_touches
)
SELECT 
    DATE(s.session_start_time) AS date,
    lt.channel,
    COUNT(DISTINCT CASE WHEN t.user_id IS NOT NULL THEN s.user_id END) * 100.0 / 
    NULLIF(COUNT(DISTINCT s.user_id), 0) AS conversion_rate
FROM 
    mobile_game.sessions s
LEFT JOIN 
    mobile_game.transactions t ON s.user_id = t.user_id AND 
    DATE(t.event_date) = DATE(s.session_start_time)
LEFT JOIN 
    last_touch lt ON s.user_id = lt.user_id AND lt.rn = 1
GROUP BY 
    DATE(s.session_start_time), lt.channel
ORDER BY 
	DATE(s.session_start_time), lt.channel;

-- Daily Conversion по сегментам покупателей
SELECT 
    DATE(s.session_start_time) AS date,
    ui.payer_segment,
    COUNT(DISTINCT CASE WHEN t.user_id IS NOT NULL THEN s.user_id END) * 100.0 / 
    NULLIF(COUNT(DISTINCT s.user_id), 0) AS conversion_rate
FROM 
    mobile_game.sessions s
LEFT JOIN 
    mobile_game.transactions t ON s.user_id = t.user_id AND 
    DATE(t.event_date) = DATE(s.session_start_time)
JOIN 
    mobile_game.user_info ui ON s.user_id = ui.user_id
GROUP BY 
    DATE(s.session_start_time), ui.payer_segment
ORDER BY 
    DATE(s.session_start_time), ui.payer_segment;

-- 7. ARPPU по дням и платформам
SELECT 
    t.event_date AS date,
    ui.platform,
    SUM(t.revenue) / NULLIF(COUNT(DISTINCT t.user_id), 0) AS arppu
FROM 
    mobile_game.transactions t
JOIN 
    mobile_game.user_info ui ON t.user_id = ui.user_id
GROUP BY 
    t.event_date, ui.platform
ORDER BY 
    t.event_date, ui.platform;

-- ARPPU по дням и каналам
WITH last_touch AS (
    SELECT 
        user_id,
        channel,
        touch_date,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY touch_date DESC) AS rn
    FROM 
        mobile_game.users_touches
)
SELECT 
    t.event_date AS date,
    lt.channel,
    SUM(t.revenue) / NULLIF(COUNT(DISTINCT t.user_id), 0) AS arppu
FROM 
    mobile_game.transactions t
JOIN 
    last_touch lt ON t.user_id = lt.user_id
GROUP BY 
    t.event_date, lt.channel
ORDER BY 
    t.event_date, lt.channel;

-- Анализ возввращающимся игрокам
WITH 
	-- Определяем возвращающихся игроков (тех, кто играл более чем через 7 дней после первой сессии)
	returning_players AS (
	    SELECT 
	        s.user_id,
	        DATE(s.session_start_time) AS return_date,
	        ui.country
	    FROM 
	        mobile_game.sessions s
	    JOIN (
	        SELECT 
	            user_id, 
	            MIN(session_start_time) AS first_session_date
	        FROM 
	            mobile_game.sessions
	        GROUP BY 
	            user_id
	    ) fs ON s.user_id = fs.user_id
	    JOIN 
	        mobile_game.user_info ui ON s.user_id = ui.user_id
	    WHERE 
	        DATE(s.session_start_time) > DATE(fs.first_session_date) + INTERVAL '7 days'
	),
	
	-- Агрегируем данные по возвращающимся игрокам
	returning_metrics AS (
	    SELECT 
	        rp.return_date AS date,
	        rp.country,
	        COUNT(DISTINCT rp.user_id) AS returning_players,
	        COUNT(DISTINCT t.user_id) AS paying_returning_players,
	        SUM(t.revenue) AS returning_revenue,
	        COUNT(DISTINCT t.user_id) * 100.0 / NULLIF(COUNT(DISTINCT rp.user_id), 0) AS conversion_rate
	    FROM 
	        returning_players rp
	    LEFT JOIN 
	        mobile_game.transactions t ON rp.user_id = t.user_id 
	        AND DATE(t.event_date) = rp.return_date
	    GROUP BY 
	        rp.return_date, rp.country
	)
	 
SELECT 
    date,
    country,
    returning_players,
    paying_returning_players,
    returning_revenue,
    conversion_rate,
    returning_revenue / NULLIF(paying_returning_players, 0) AS arppu_returning
FROM 
    returning_metrics
ORDER BY 
    date, country;