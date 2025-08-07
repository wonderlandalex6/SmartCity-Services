;; Dynamic Pricing Engine for Smart City Services
;; Automatically adjusts service prices based on demand, loyalty, time, and location

;; Constants for pricing calculations
(define-constant base-multiplier u100)
(define-constant max-surge-multiplier u300)
(define-constant min-discount-multiplier u50)
(define-constant loyalty-tier-1-threshold u5)
(define-constant loyalty-tier-2-threshold u15)
(define-constant loyalty-tier-3-threshold u30)
(define-constant peak-hour-start u8)
(define-constant peak-hour-end u18)
(define-constant weekend-multiplier u120)

;; Error constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-insufficient-balance (err u104))
(define-constant err-invalid-service (err u200))
(define-constant err-invalid-zone (err u201))
(define-constant err-invalid-multiplier (err u202))
(define-constant err-unauthorized-pricing (err u203))
(define-constant err-invalid-time-slot (err u204))

;; Data variables
(define-data-var pricing-engine-active bool true)
(define-data-var global-demand-factor uint u100)
(define-data-var zone-count uint u0)

;; External data maps (simulated for standalone contract)
(define-map services uint {
    name: (string-ascii 50),
    description: (string-ascii 200),
    price: uint,
    provider: principal,
    active: bool
})

(define-map subscriptions { user: principal, service-id: uint } {
    expiry: uint,
    active: bool
})

(define-map citizen-balances principal uint)

;; Pricing zone configuration
(define-map pricing-zones uint {
    name: (string-ascii 30),
    base-multiplier: uint,
    active: bool,
    max-capacity: uint,
    current-usage: uint
})

;; Time-based pricing rules
(define-map time-based-pricing uint {
    start-hour: uint,
    end-hour: uint,
    multiplier: uint,
    days-of-week: (list 7 uint),
    active: bool
})

;; Service demand tracking
(define-map service-demand-data uint {
    current-active-users: uint,
    max-capacity: uint,
    demand-level: uint,
    last-updated: uint,
    surge-active: bool
})

;; User loyalty levels for pricing
(define-map user-loyalty-tiers principal {
    tier: uint,
    total-subscriptions: uint,
    last-subscription: uint,
    discount-percentage: uint
})

;; Geographic zone pricing
(define-map service-zone-pricing { service-id: uint, zone-id: uint } {
    custom-multiplier: uint,
    active: bool
})

;; Historical pricing data
(define-map pricing-history { service-id: uint, timestamp: uint } {
    calculated-price: uint,
    demand-factor: uint,
    loyalty-discount: uint,
    zone-multiplier: uint,
    time-multiplier: uint
})

;; Public functions

;; Initialize pricing zone
(define-public (create-pricing-zone (name (string-ascii 30)) (multiplier uint) (max-capacity uint))
    (let ((zone-id (var-get zone-count)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= multiplier u50) (<= multiplier u200)) err-invalid-multiplier)
        
        (map-set pricing-zones zone-id {
            name: name,
            base-multiplier: multiplier,
            active: true,
            max-capacity: max-capacity,
            current-usage: u0
        })
        
        (var-set zone-count (+ zone-id u1))
        (ok zone-id)
    )
)

;; Set time-based pricing rule
(define-public (set-time-pricing (start-hour uint) (end-hour uint) (multiplier uint) (days (list 7 uint)))
    (let ((time-slot-id (+ start-hour (* end-hour u100))))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= start-hour u0) (<= start-hour u23)) err-invalid-time-slot)
        (asserts! (and (>= end-hour u0) (<= end-hour u23)) err-invalid-time-slot)
        (asserts! (and (>= multiplier u50) (<= multiplier u300)) err-invalid-multiplier)
        
        (map-set time-based-pricing time-slot-id {
            start-hour: start-hour,
            end-hour: end-hour,
            multiplier: multiplier,
            days-of-week: days,
            active: true
        })
        
        (ok time-slot-id)
    )
)

;; Update service demand metrics
(define-public (update-service-demand (service-id uint) (active-users uint) (max-capacity uint))
    (let (
        (service (unwrap! (map-get? services service-id) err-invalid-service))
        (current-data (default-to 
            { current-active-users: u0, max-capacity: u100, demand-level: u100, last-updated: u0, surge-active: false }
            (map-get? service-demand-data service-id)))
    )
        (asserts! (is-eq tx-sender (get provider service)) err-unauthorized-pricing)
        
        (let (
            (utilization-percent (if (> max-capacity u0) 
                (/ (* active-users u100) max-capacity) u0))
            (demand-factor (if (>= utilization-percent u80) 
                (+ u100 (* (- utilization-percent u80) u10)) u100))
            (surge-status (>= utilization-percent u90))
        )
            (map-set service-demand-data service-id {
                current-active-users: active-users,
                max-capacity: max-capacity,
                demand-level: demand-factor,
                last-updated: stacks-block-height,
                surge-active: surge-status
            })
            
            (ok demand-factor)
        )
    )
)

;; Update user loyalty tier
(define-public (update-user-loyalty (user principal))
    (let (
        (current-loyalty (default-to 
            { tier: u0, total-subscriptions: u0, last-subscription: u0, discount-percentage: u0 }
            (map-get? user-loyalty-tiers user)))
        (new-subscription-count (+ (get total-subscriptions current-loyalty) u1))
    )
        ;; Calculate new tier and discount
        (let (
            (new-tier (if (>= new-subscription-count loyalty-tier-3-threshold) u3
                      (if (>= new-subscription-count loyalty-tier-2-threshold) u2
                      (if (>= new-subscription-count loyalty-tier-1-threshold) u1 u0))))
            (discount-percent (if (is-eq new-tier u3) u20
                             (if (is-eq new-tier u2) u15
                             (if (is-eq new-tier u1) u10 u0))))
        )
            (map-set user-loyalty-tiers user {
                tier: new-tier,
                total-subscriptions: new-subscription-count,
                last-subscription: stacks-block-height,
                discount-percentage: discount-percent
            })
            
            (ok new-tier)
        )
    )
)

;; Calculate dynamic price for a service
(define-public (calculate-dynamic-price (service-id uint) (user principal) (zone-id uint))
    (let (
        (service (unwrap! (map-get? services service-id) err-invalid-service))
        (base-price (get price service))
        (zone-data (map-get? pricing-zones zone-id))
        (demand-data (default-to 
            { current-active-users: u0, max-capacity: u100, demand-level: u100, last-updated: u0, surge-active: false }
            (map-get? service-demand-data service-id)))
        (user-loyalty (default-to 
            { tier: u0, total-subscriptions: u0, last-subscription: u0, discount-percentage: u0 }
            (map-get? user-loyalty-tiers user)))
    )
        ;; Calculate zone multiplier
        (let (
            (zone-multiplier (if (is-some zone-data) 
                (get base-multiplier (unwrap-panic zone-data)) base-multiplier))
            
            ;; Calculate time-based multiplier
            (current-hour (mod stacks-block-height u24))
            (time-multiplier (if (and (>= current-hour peak-hour-start) 
                                    (<= current-hour peak-hour-end))
                u130 u100))
            
            ;; Apply demand surge
            (demand-multiplier (get demand-level demand-data))
            
            ;; Apply loyalty discount
            (loyalty-discount (get discount-percentage user-loyalty))
            
            ;; Calculate final price
            (price-before-loyalty (/ (* (* (* base-price zone-multiplier) time-multiplier) demand-multiplier) 
                                  (* base-multiplier base-multiplier)))
            (loyalty-reduction (/ (* price-before-loyalty loyalty-discount) u100))
            (final-price (- price-before-loyalty loyalty-reduction))
        )
            ;; Store pricing history
            (map-set pricing-history { service-id: service-id, timestamp: stacks-block-height } {
                calculated-price: final-price,
                demand-factor: demand-multiplier,
                loyalty-discount: loyalty-discount,
                zone-multiplier: zone-multiplier,
                time-multiplier: time-multiplier
            })
            
            (ok final-price)
        )
    )
)

;; Subscribe with dynamic pricing
(define-public (subscribe-with-dynamic-pricing (service-id uint) (zone-id uint))
    (let (
        (calculated-price-result (calculate-dynamic-price service-id tx-sender zone-id))
        (dynamic-price (unwrap! calculated-price-result calculated-price-result))
        (user-balance (default-to u0 (map-get? citizen-balances tx-sender)))
        (current-block-height stacks-block-height)
        (subscription-period u1440)
    )
        (asserts! (>= user-balance dynamic-price) err-insufficient-balance)
        
        ;; Process payment with dynamic price
        (map-set citizen-balances tx-sender (- user-balance dynamic-price))
        
        ;; Create subscription
        (map-set subscriptions { user: tx-sender, service-id: service-id } {
            expiry: (+ current-block-height subscription-period),
            active: true
        })
        
        ;; Update user loyalty
        (unwrap-panic (update-user-loyalty tx-sender))
        
        (ok dynamic-price)
    )
)

;; Set custom zone pricing for specific service
(define-public (set-service-zone-pricing (service-id uint) (zone-id uint) (multiplier uint))
    (let ((service (unwrap! (map-get? services service-id) err-invalid-service)))
        (asserts! (is-eq tx-sender (get provider service)) err-unauthorized-pricing)
        (asserts! (is-some (map-get? pricing-zones zone-id)) err-invalid-zone)
        (asserts! (and (>= multiplier u50) (<= multiplier u300)) err-invalid-multiplier)
        
        (map-set service-zone-pricing { service-id: service-id, zone-id: zone-id } {
            custom-multiplier: multiplier,
            active: true
        })
        
        (ok true)
    )
)

;; Toggle pricing engine on/off
(define-public (toggle-pricing-engine (active bool))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (var-set pricing-engine-active active)
        (ok active)
    )
)

;; Read-only functions

;; Get current dynamic price for service (read-only version)
(define-read-only (get-current-price (service-id uint) (user principal) (zone-id uint))
    (if (var-get pricing-engine-active)
        (let (
            (service (unwrap! (map-get? services service-id) err-invalid-service))
            (base-price (get price service))
            (zone-data (map-get? pricing-zones zone-id))
            (demand-data (default-to 
                { current-active-users: u0, max-capacity: u100, demand-level: u100, last-updated: u0, surge-active: false }
                (map-get? service-demand-data service-id)))
            (user-loyalty (default-to 
                { tier: u0, total-subscriptions: u0, last-subscription: u0, discount-percentage: u0 }
                (map-get? user-loyalty-tiers user)))
        )
            ;; Calculate zone multiplier
            (let (
                (zone-multiplier (if (is-some zone-data) 
                    (get base-multiplier (unwrap-panic zone-data)) base-multiplier))
                
                ;; Calculate time-based multiplier
                (current-hour (mod stacks-block-height u24))
                (time-multiplier (if (and (>= current-hour peak-hour-start) 
                                        (<= current-hour peak-hour-end))
                    u130 u100))
                
                ;; Apply demand surge
                (demand-multiplier (get demand-level demand-data))
                
                ;; Apply loyalty discount
                (loyalty-discount (get discount-percentage user-loyalty))
                
                ;; Calculate final price
                (price-before-loyalty (/ (* (* (* base-price zone-multiplier) time-multiplier) demand-multiplier) 
                                      (* base-multiplier base-multiplier)))
                (loyalty-reduction (/ (* price-before-loyalty loyalty-discount) u100))
                (final-price (- price-before-loyalty loyalty-reduction))
            )
                (ok final-price)
            )
        )
        (let ((service (unwrap! (map-get? services service-id) err-invalid-service)))
            (ok (get price service))
        )
    )
)

;; Get user loyalty information
(define-read-only (get-user-loyalty-info (user principal))
    (default-to 
        { tier: u0, total-subscriptions: u0, last-subscription: u0, discount-percentage: u0 }
        (map-get? user-loyalty-tiers user)
    )
)

;; Get service demand metrics
(define-read-only (get-service-demand-info (service-id uint))
    (default-to 
        { current-active-users: u0, max-capacity: u100, demand-level: u100, last-updated: u0, surge-active: false }
        (map-get? service-demand-data service-id)
    )
)

;; Get pricing zone information
(define-read-only (get-pricing-zone (zone-id uint))
    (map-get? pricing-zones zone-id)
)

;; Get pricing history for service
(define-read-only (get-pricing-history (service-id uint) (timestamp uint))
    (map-get? pricing-history { service-id: service-id, timestamp: timestamp })
)

;; Check if surge pricing is active for service
(define-read-only (is-surge-pricing-active (service-id uint))
    (let ((demand-data (map-get? service-demand-data service-id)))
        (if (is-some demand-data)
            (get surge-active (unwrap-panic demand-data))
            false
        )
    )
)

;; Get time-based pricing rule
(define-read-only (get-time-pricing-rule (start-hour uint) (end-hour uint))
    (let ((time-slot-id (+ start-hour (* end-hour u100))))
        (map-get? time-based-pricing time-slot-id)
    )
)

;; Calculate loyalty discount amount
(define-read-only (calculate-loyalty-discount (user principal) (amount uint))
    (let (
        (loyalty-info (get-user-loyalty-info user))
        (discount-percent (get discount-percentage loyalty-info))
    )
        (/ (* amount discount-percent) u100)
    )
)




