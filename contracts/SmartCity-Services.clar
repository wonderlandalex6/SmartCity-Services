;; title: SmartCity-Services
;; version: 1.0
;; summary: Urban service management platform
;; description: Smart contract for managing city services, subscriptions, and usage tracking

;; traits
(define-trait service-provider-trait
  (
    (provide-service (uint principal) (response bool uint))
  )
)

;; constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-insufficient-balance (err u104))

;; Add to constants
(define-constant referral-reward u100)

;; data vars
(define-data-var service-count uint u0)

;; data maps
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

(define-map service-usage { user: principal, service-id: uint } uint)

(define-map citizen-balances principal uint)

;; Add to data maps section
(define-map service-ratings { service-id: uint, user: principal } uint)
(define-map service-rating-stats uint { total-ratings: uint, sum-ratings: uint })

;; Add to data maps section
(define-map referrals { referrer: principal, referred: principal } bool)
(define-map referral-counts principal uint)

;; public functions

;; Admin functions
(define-public (add-service (name (string-ascii 50)) (description (string-ascii 200)) (price uint) (provider principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let ((service-id (var-get service-count)))
      (map-set services service-id {
        name: name,
        description: description,
        price: price,
        provider: provider,
        active: true
      })
      (var-set service-count (+ service-id u1))
      (ok service-id)
    )
  )
)

(define-public (update-service (service-id uint) (name (string-ascii 50)) (description (string-ascii 200)) (price uint) (active bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (is-some (map-get? services service-id)) err-not-found)
    (let ((service (unwrap-panic (map-get? services service-id))))
      (map-set services service-id {
        name: name,
        description: description,
        price: price,
        provider: (get provider service),
        active: active
      })
      (ok true)
    )
  )
)

;; User functions
(define-public (deposit (amount uint))
  (begin
    (let ((current-balance (default-to u0 (map-get? citizen-balances tx-sender))))
      (map-set citizen-balances tx-sender (+ current-balance amount))
      (ok true)
    )
  )
)

(define-public (subscribe (service-id uint))
  (let (
    (service (unwrap! (map-get? services service-id) err-not-found))
    (user-balance (default-to u0 (map-get? citizen-balances tx-sender)))
    (price (get price service))
    (current-block-height stacks-block-height)
    (subscription-period u1440) ;; ~10 days in blocks (assuming 10 min block time)
  )
    (asserts! (get active service) err-unauthorized)
    (asserts! (>= user-balance price) err-insufficient-balance)
    
    ;; Deduct payment
    (map-set citizen-balances tx-sender (- user-balance price))
    
    ;; Create or update subscription
    (map-set subscriptions { user: tx-sender, service-id: service-id } {
      expiry: (+ current-block-height subscription-period),
      active: true
    })
    
    (ok true)
  )
)

(define-public (use-service (service-id uint))
  (let (
    (service (unwrap! (map-get? services service-id) err-not-found))
    (subscription (unwrap! (map-get? subscriptions { user: tx-sender, service-id: service-id }) err-unauthorized))
    (current-usage (default-to u0 (map-get? service-usage { user: tx-sender, service-id: service-id })))
  )
    ;; Check subscription is active and not expired
    (asserts! (get active subscription) err-unauthorized)
    (asserts! (<= stacks-block-height (get expiry subscription)) err-unauthorized)
    
    ;; Update usage count
    (map-set service-usage { user: tx-sender, service-id: service-id } (+ current-usage u1))
    
    ;; Call service provider (if implemented)
    (ok true)
  )
)

(define-public (rate-service (service-id uint) (rating uint))
    (let (
        (service (unwrap! (map-get? services service-id) err-not-found))
        (current-stats (default-to { total-ratings: u0, sum-ratings: u0 } 
                        (map-get? service-rating-stats service-id)))
    )
        (asserts! (and (>= rating u1) (<= rating u5)) (err u300))
        (map-set service-ratings { service-id: service-id, user: tx-sender } rating)
        (map-set service-rating-stats service-id {
            total-ratings: (+ (get total-ratings current-stats) u1),
            sum-ratings: (+ (get sum-ratings current-stats) rating)
        })
        (ok true)
    )
)

(define-public (subscribe-with-referral (service-id uint) (referrer principal))
    (let (
        (service (unwrap! (map-get? services service-id) err-not-found))
        (user-balance (default-to u0 (map-get? citizen-balances tx-sender)))
        (price (get price service))
        (current-block-height stacks-block-height)
        (subscription-period u1440)
    )
        (asserts! (not (is-eq tx-sender referrer)) (err u400))
        (asserts! (get active service) err-unauthorized)
        (asserts! (>= user-balance price) err-insufficient-balance)
        
        ;; Process referral
        (map-set referrals { referrer: referrer, referred: tx-sender } true)
        (map-set referral-counts referrer 
            (+ (default-to u0 (map-get? referral-counts referrer)) u1))
        
        ;; Add referral bonus
        (map-set citizen-balances referrer 
            (+ (default-to u0 (map-get? citizen-balances referrer)) referral-reward))
        
        ;; Regular subscription process
        (map-set citizen-balances tx-sender (- user-balance price))
        (map-set subscriptions { user: tx-sender, service-id: service-id } {
            expiry: (+ current-block-height subscription-period),
            active: true
        })
        (ok true)
    )
)

;; read only functions
(define-read-only (get-service (service-id uint))
  (map-get? services service-id)
)

(define-read-only (get-subscription (user principal) (service-id uint))
  (map-get? subscriptions { user: user, service-id: service-id })
)

(define-read-only (get-service-usage (user principal) (service-id uint))
  (default-to u0 (map-get? service-usage { user: user, service-id: service-id }))
)

(define-read-only (get-balance (user principal))
  (default-to u0 (map-get? citizen-balances user))
)

(define-read-only (is-subscription-active (user principal) (service-id uint))
  (let (
    (subscription (map-get? subscriptions { user: user, service-id: service-id }))
  )
    (if (is-some subscription)
      (let ((sub (unwrap-panic subscription)))
        (and (get active sub) (<= stacks-block-height (get expiry sub)))
      )
      false
    )
  )
)

(define-read-only (get-service-rating (service-id uint))
    (let (
        (stats (default-to { total-ratings: u0, sum-ratings: u0 } 
                (map-get? service-rating-stats service-id)))
    )
        (if (is-eq (get total-ratings stats) u0)
            u0
            (/ (get sum-ratings stats) (get total-ratings stats))
        )
    )
)

(define-read-only (get-service-price (service-id uint))
    (let ((service (unwrap! (map-get? services service-id) err-not-found)))
        (ok (get price service))
    )
)


;; Add to data maps section
(define-map emergency-access principal bool)
(define-map priority-requests { user: principal, service-id: uint } uint)

;; Add these public functions
(define-public (grant-emergency-access (user principal))
    (begin
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (map-set emergency-access user true)
        (ok true)
    )
)

(define-public (request-priority-service (service-id uint))
    (let (
        (is-emergency (default-to false (map-get? emergency-access tx-sender)))
        (current-requests (default-to u0 
            (map-get? priority-requests { user: tx-sender, service-id: service-id })))
    )
        (asserts! is-emergency (err u500))
        (map-set priority-requests { user: tx-sender, service-id: service-id } 
            (+ current-requests u1))
        (ok true)
    )
)


;; Add to data maps section
(define-map maintenance-schedule uint {
    service-id: uint,
    start-block: uint,
    end-block: uint,
    description: (string-ascii 200)
})
(define-data-var maintenance-count uint u0)

;; Add these public functions
(define-public (schedule-maintenance 
    (service-id uint) 
    (start-block uint) 
    (end-block uint) 
    (description (string-ascii 200)))
    (let (
        (service (unwrap! (map-get? services service-id) err-not-found))
        (maintenance-id (var-get maintenance-count))
    )
        (asserts! (is-eq tx-sender (get provider service)) err-unauthorized)
        (asserts! (> start-block stacks-block-height) (err u600))
        (asserts! (> end-block start-block) (err u601))
        
        (map-set maintenance-schedule maintenance-id {
            service-id: service-id,
            start-block: start-block,
            end-block: end-block,
            description: description
        })
        (var-set maintenance-count (+ maintenance-id u1))
        (ok maintenance-id)
    )
)


;; Add to data maps section
(define-map service-feedback { service-id: uint, user: principal } {
    comment: (string-ascii 500),
    timestamp: uint
})

;; Add this public function
(define-public (submit-feedback (service-id uint) (comment (string-ascii 500)))
    (let (
        (service (unwrap! (map-get? services service-id) err-not-found))
        (subscription (unwrap! (map-get? subscriptions 
            { user: tx-sender, service-id: service-id }) err-unauthorized))
    )
        (asserts! (get active subscription) err-unauthorized)
        (map-set service-feedback { service-id: service-id, user: tx-sender } {
            comment: comment,
            timestamp: stacks-block-height
        })
        (ok true)
    )
)

(define-read-only (get-feedback (service-id uint) (user principal))
    (map-get? service-feedback { service-id: service-id, user: user })
)


(define-map service-bundles uint {
    name: (string-ascii 50),
    services: (list 10 uint),
    discount-percent: uint,
    active: bool
})

(define-data-var bundle-count uint u0)

(define-public (create-service-bundle (name (string-ascii 50)) (service-ids (list 10 uint)) (discount uint))
    (let ((bundle-id (var-get bundle-count)))
        (asserts! (is-eq tx-sender contract-owner) err-owner-only)
        (asserts! (and (>= discount u0) (<= discount u100)) (err u700))
        (map-set service-bundles bundle-id {
            name: name,
            services: service-ids,
            discount-percent: discount,
            active: true
        })
        (var-set bundle-count (+ bundle-id u1))
        (ok bundle-id)
    )
)

(define-private (subscribe-user (service-id uint))
    (let (
        (current-block-height stacks-block-height)
        (subscription-period u1440)
    )
        (map-set subscriptions { user: tx-sender, service-id: service-id } {
            expiry: (+ current-block-height subscription-period),
            active: true
        })
    )
)

(define-public (subscribe-to-bundle (bundle-id uint))
    (let (
        (bundle (unwrap! (map-get? service-bundles bundle-id) err-not-found))
        ;; TODO: Check if user is already subscribed to any service in the bundle
        (total-price  u0)
        (discounted-price (- total-price (* total-price (/ (get discount-percent bundle) u100))))
    )
        (asserts! (get active bundle) err-unauthorized)
        (asserts! (>= (get-balance tx-sender) discounted-price) err-insufficient-balance)
        (map-set citizen-balances tx-sender (- (get-balance tx-sender) discounted-price))
        (map subscribe-user (get services bundle))
        (ok true)
    )
)


(define-map user-points principal uint)
(define-constant points-per-use u10)
(define-constant points-threshold u1000)
(define-constant reward-amount u50)

(define-public (claim-usage-rewards)
    (let (
        (user-point-balance (default-to u0 (map-get? user-points tx-sender)))
    )
        (asserts! (>= user-point-balance points-threshold) err-insufficient-balance)
        (map-set user-points tx-sender (- user-point-balance points-threshold))
        (map-set citizen-balances tx-sender 
            (+ (default-to u0 (map-get? citizen-balances tx-sender)) reward-amount))
        (ok true)
    )
)

(define-public (award-service-points (service-id uint))
    (let (
        (current-points (default-to u0 (map-get? user-points tx-sender)))
    )
        (asserts! (is-subscription-active tx-sender service-id) err-unauthorized)
        (map-set user-points tx-sender (+ current-points points-per-use))
        (ok true)
    )
)

(define-read-only (get-user-points (user principal))
    (default-to u0 (map-get? user-points user))
)