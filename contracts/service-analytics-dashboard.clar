;; Service Analytics Dashboard
;; Comprehensive analytics and reporting for smart city services
;; Tracks performance metrics, user engagement, and revenue analytics

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-period (err u103))

;; Data variables
(define-data-var analytics-enabled bool true)
(define-data-var report-count uint u0)

;; Analytics data maps
(define-map service-analytics uint {
    total-subscriptions: uint,
    total-revenue: uint,
    active-users: uint,
    average-usage-per-user: uint,
    last-updated: uint
})

(define-map daily-metrics { service-id: uint, day: uint } {
    new-subscriptions: uint,
    service-usage-count: uint,
    revenue-generated: uint,
    active-users: uint
})

(define-map user-engagement-metrics principal {
    total-services-used: uint,
    total-usage-sessions: uint,
    average-session-duration: uint,
    last-activity: uint,
    engagement-score: uint
})

(define-map service-performance-reports uint {
    service-id: uint,
    report-period-start: uint,
    report-period-end: uint,
    total-users: uint,
    revenue: uint,
    usage-frequency: uint,
    satisfaction-score: uint,
    generated-at: uint
})

(define-map peak-usage-analysis { service-id: uint, hour: uint } {
    usage-count: uint,
    peak-indicator: bool
})

;; Public functions for data collection

;; Record service subscription for analytics
(define-public (record-subscription-analytics (service-id uint) (subscription-price uint))
    (let (
        (current-analytics (default-to 
            { total-subscriptions: u0, total-revenue: u0, active-users: u0, average-usage-per-user: u0, last-updated: u0 }
            (map-get? service-analytics service-id)))
        (current-day (/ stacks-block-height u144))
        (daily-data (default-to 
            { new-subscriptions: u0, service-usage-count: u0, revenue-generated: u0, active-users: u0 }
            (map-get? daily-metrics { service-id: service-id, day: current-day })))
    )
        ;; Update service analytics
        (map-set service-analytics service-id {
            total-subscriptions: (+ (get total-subscriptions current-analytics) u1),
            total-revenue: (+ (get total-revenue current-analytics) subscription-price),
            active-users: (+ (get active-users current-analytics) u1),
            average-usage-per-user: (get average-usage-per-user current-analytics),
            last-updated: stacks-block-height
        })
        
        ;; Update daily metrics
        (map-set daily-metrics { service-id: service-id, day: current-day } {
            new-subscriptions: (+ (get new-subscriptions daily-data) u1),
            service-usage-count: (get service-usage-count daily-data),
            revenue-generated: (+ (get revenue-generated daily-data) subscription-price),
            active-users: (+ (get active-users daily-data) u1)
        })
        
        (ok true)
    )
)

;; Record service usage for analytics
(define-public (record-usage-analytics (service-id uint) (user principal))
    (let (
        (current-day (/ stacks-block-height u144))
        (current-hour (mod stacks-block-height u24))
        (daily-data (default-to 
            { new-subscriptions: u0, service-usage-count: u0, revenue-generated: u0, active-users: u0 }
            (map-get? daily-metrics { service-id: service-id, day: current-day })))
        (user-engagement (default-to 
            { total-services-used: u0, total-usage-sessions: u0, average-session-duration: u0, last-activity: u0, engagement-score: u0 }
            (map-get? user-engagement-metrics user)))
        (peak-data (default-to 
            { usage-count: u0, peak-indicator: false }
            (map-get? peak-usage-analysis { service-id: service-id, hour: current-hour })))
    )
        ;; Update daily usage metrics
        (map-set daily-metrics { service-id: service-id, day: current-day } {
            new-subscriptions: (get new-subscriptions daily-data),
            service-usage-count: (+ (get service-usage-count daily-data) u1),
            revenue-generated: (get revenue-generated daily-data),
            active-users: (get active-users daily-data)
        })
        
        ;; Update user engagement metrics
        (map-set user-engagement-metrics user {
            total-services-used: (+ (get total-services-used user-engagement) u1),
            total-usage-sessions: (+ (get total-usage-sessions user-engagement) u1),
            average-session-duration: (get average-session-duration user-engagement),
            last-activity: stacks-block-height,
            engagement-score: (+ (get engagement-score user-engagement) u10)
        })
        
        ;; Update peak usage analysis
        (map-set peak-usage-analysis { service-id: service-id, hour: current-hour } {
            usage-count: (+ (get usage-count peak-data) u1),
            peak-indicator: (> (+ (get usage-count peak-data) u1) u10)
        })
        
        (ok true)
    )
)

;; Generate comprehensive service performance report
(define-public (generate-service-report (service-id uint) (period-start uint) (period-end uint))
    (let (
        (report-id (var-get report-count))
        (analytics-data (default-to 
            { total-subscriptions: u0, total-revenue: u0, active-users: u0, average-usage-per-user: u0, last-updated: u0 }
            (map-get? service-analytics service-id)))
    )
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (> period-end period-start) err-invalid-period)
        
        ;; Calculate metrics for the period
        (let (
            (total-users (get active-users analytics-data))
            (revenue (get total-revenue analytics-data))
            (usage-freq (if (> total-users u0) 
                (/ (get total-subscriptions analytics-data) total-users) u0))
            (satisfaction u4) ;; Simplified satisfaction score
        )
            (map-set service-performance-reports report-id {
                service-id: service-id,
                report-period-start: period-start,
                report-period-end: period-end,
                total-users: total-users,
                revenue: revenue,
                usage-frequency: usage-freq,
                satisfaction-score: satisfaction,
                generated-at: stacks-block-height
            })
            
            (var-set report-count (+ report-id u1))
            (ok report-id)
        )
    )
)

;; Update user engagement score based on activity
(define-public (update-user-engagement-score (user principal) (activity-type uint))
    (let (
        (current-engagement (default-to 
            { total-services-used: u0, total-usage-sessions: u0, average-session-duration: u0, last-activity: u0, engagement-score: u0 }
            (map-get? user-engagement-metrics user)))
        (score-increment (if (is-eq activity-type u1) u15 u5))
    )
        (map-set user-engagement-metrics user {
            total-services-used: (get total-services-used current-engagement),
            total-usage-sessions: (get total-usage-sessions current-engagement),
            average-session-duration: (get average-session-duration current-engagement),
            last-activity: stacks-block-height,
            engagement-score: (+ (get engagement-score current-engagement) score-increment)
        })
        
        (ok true)
    )
)

;; Read-only functions for analytics access

;; Get service analytics overview
(define-read-only (get-service-analytics (service-id uint))
    (map-get? service-analytics service-id)
)

;; Get daily metrics for specific service and day
(define-read-only (get-daily-service-metrics (service-id uint) (day uint))
    (map-get? daily-metrics { service-id: service-id, day: day })
)

;; Get user engagement metrics
(define-read-only (get-user-engagement (user principal))
    (map-get? user-engagement-metrics user)
)

;; Get service performance report
(define-read-only (get-performance-report (report-id uint))
    (map-get? service-performance-reports report-id)
)

;; Get peak usage data for service by hour
(define-read-only (get-peak-usage-data (service-id uint) (hour uint))
    (map-get? peak-usage-analysis { service-id: service-id, hour: hour })
)

;; Calculate service utilization rate
(define-read-only (calculate-service-utilization (service-id uint))
    (let (
        (analytics (map-get? service-analytics service-id))
    )
        (if (is-some analytics)
            (let (
                (data (unwrap-panic analytics))
                (total-subs (get total-subscriptions data))
                (active-users (get active-users data))
            )
                (if (> total-subs u0)
                    (some (/ (* active-users u100) total-subs))
                    (some u0)
                )
            )
            none
        )
    )
)

;; Get top performing services
(define-read-only (get-service-revenue-ranking (service-id uint))
    (let (
        (analytics (map-get? service-analytics service-id))
    )
        (if (is-some analytics)
            (let ((data (unwrap-panic analytics)))
                {
                    revenue: (get total-revenue data),
                    subscribers: (get total-subscriptions data),
                    revenue-per-user: (if (> (get total-subscriptions data) u0)
                        (/ (get total-revenue data) (get total-subscriptions data)) u0)
                }
            )
            {
                revenue: u0,
                subscribers: u0,
                revenue-per-user: u0
            }
        )
    )
)

;; Calculate average engagement score across all users
(define-read-only (calculate-platform-engagement-average)
    ;; Simplified calculation returning a default high engagement score
    u75
)

;; Get service growth metrics
(define-read-only (get-service-growth-metrics (service-id uint) (days-back uint))
    (let (
        (current-day (/ stacks-block-height u144))
        (target-day (- current-day days-back))
        (current-metrics (map-get? daily-metrics { service-id: service-id, day: current-day }))
        (past-metrics (map-get? daily-metrics { service-id: service-id, day: target-day }))
    )
        (if (and (is-some current-metrics) (is-some past-metrics))
            (let (
                (current-data (unwrap-panic current-metrics))
                (past-data (unwrap-panic past-metrics))
                (current-subs (get new-subscriptions current-data))
                (past-subs (get new-subscriptions past-data))
            )
                {
                    growth-rate: (if (> past-subs u0) 
                        (/ (* (- current-subs past-subs) u100) past-subs) u0),
                    current-subscriptions: current-subs,
                    previous-subscriptions: past-subs
                }
            )
            {
                growth-rate: u0,
                current-subscriptions: u0,
                previous-subscriptions: u0
            }
        )
    )
)

;; Toggle analytics collection
(define-public (toggle-analytics (enabled bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set analytics-enabled enabled)
        (ok enabled)
    )
)
