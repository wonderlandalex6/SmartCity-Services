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


