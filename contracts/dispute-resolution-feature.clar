(define-constant dispute-filing-fee u25)
(define-constant arbitration-threshold u72)
(define-constant max-evidence-length u1000)
(define-constant dispute-timeout u4320)
(define-constant err-insufficient-balance (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-not-found (err u106))
(define-constant err-owner-only (err u107))
(define-constant err-service-unavailable (err u108))
(define-constant err-service-rating-too-low (err u109))
(define-constant err-service-uptime-too-low (err u110)) 
;; Map to track citizen balances
(define-map citizen-balances principal uint)

;; Map to track registered services
(define-map services uint {
    provider: principal,
    name: (string-ascii 100),
    description: (string-ascii 200),
    created-at: uint
})

;; Map to track user subscriptions to services
(define-map subscriptions { user: principal, service-id: uint } {
    active: bool
})

(define-data-var dispute-count uint u0)
(define-data-var arbitrator-address principal tx-sender)

(define-map service-disputes uint {
    complainant: principal,
    service-id: uint,
    evidence: (string-ascii 1000),
    dispute-type: (string-ascii 30),
    amount-disputed: uint,
    timestamp: uint,
    status: (string-ascii 20),
    resolution-deadline: uint
})

(define-map dispute-votes { dispute-id: uint, voter: principal } {
    vote: bool,
    timestamp: uint,
    rationale: (string-ascii 200)
})

(define-map dispute-resolution uint {
    winner: principal,
    compensation-amount: uint,
    resolution-type: (string-ascii 30),
    resolved-at: uint,
    arbitrator: principal
})

(define-map dispute-evidence { dispute-id: uint, evidence-id: uint } {
    submitter: principal,
    content: (string-ascii 500),
    timestamp: uint
})

(define-data-var evidence-count uint u0)

(define-public (file-service-dispute (service-id uint) (dispute-type (string-ascii 30)) (evidence (string-ascii 1000)) (amount uint))
    (let (
        (dispute-id (var-get dispute-count))
        (user-balance (default-to u0 (map-get? citizen-balances tx-sender)))
        (subscription (unwrap! (map-get? subscriptions { user: tx-sender, service-id: service-id }) err-unauthorized))
        (service (unwrap! (map-get? services service-id) err-not-found))
    )
        (asserts! (get active subscription) err-unauthorized)
        (asserts! (>= user-balance dispute-filing-fee) err-insufficient-balance)
        (asserts! (> amount u0) (err u900))
        
        (map-set citizen-balances tx-sender (- user-balance dispute-filing-fee))
        
        (map-set service-disputes dispute-id {
            complainant: tx-sender,
            service-id: service-id,
            evidence: evidence,
            dispute-type: dispute-type,
            amount-disputed: amount,
            timestamp: stacks-block-height,
            status: "pending",
            resolution-deadline: (+ stacks-block-height dispute-timeout)
        })
        
        (var-set dispute-count (+ dispute-id u1))
        (ok dispute-id)
    )
)

(define-public (submit-dispute-evidence (dispute-id uint) (evidence-content (string-ascii 500)))
    (let (
        (dispute (unwrap! (map-get? service-disputes dispute-id) err-not-found))
        (evidence-id (var-get evidence-count))
        (service (unwrap! (map-get? services (get service-id dispute)) err-not-found))
    )
        (asserts! (or (is-eq tx-sender (get complainant dispute)) 
                      (is-eq tx-sender (get provider service))) err-unauthorized)
        (asserts! (is-eq (get status dispute) "pending") (err u901))
        (asserts! (< stacks-block-height (get resolution-deadline dispute)) (err u902))
        
        (map-set dispute-evidence { dispute-id: dispute-id, evidence-id: evidence-id } {
            submitter: tx-sender,
            content: evidence-content,
            timestamp: stacks-block-height
        })
        
        (var-set evidence-count (+ evidence-id u1))
        (ok evidence-id)
    )
)

(define-public (vote-on-dispute (dispute-id uint) (vote bool) (rationale (string-ascii 200)))
    (let (
        (dispute (unwrap! (map-get? service-disputes dispute-id) err-not-found))
        (voter-balance (default-to u0 (map-get? citizen-balances tx-sender)))
    )
        (asserts! (is-eq (get status dispute) "pending") (err u901))
        (asserts! (< stacks-block-height (get resolution-deadline dispute)) (err u902))
        (asserts! (not (is-eq tx-sender (get complainant dispute))) (err u903))
        (asserts! (> voter-balance u100) (err u904))
        
        (map-set dispute-votes { dispute-id: dispute-id, voter: tx-sender } {
            vote: vote,
            timestamp: stacks-block-height,
            rationale: rationale
        })
        
        (ok true)
    )
)

(define-public (resolve-dispute-automated (dispute-id uint))
    (let (
        (dispute (unwrap! (map-get? service-disputes dispute-id) err-not-found))
        (service (unwrap! (map-get? services (get service-id dispute)) err-not-found))
        (service-rating (get-service-rating (get service-id dispute)))
        (service-uptime (default-to u100 (get-service-uptime (get service-id dispute))))
    )
        (asserts! (is-eq (get status dispute) "pending") (err u901))
        (asserts! (>= stacks-block-height (get resolution-deadline dispute)) (err u905))
        
        (let (
            (auto-resolution (if (and (< service-rating u3) (< service-uptime u90)) true false))
            (winner (if auto-resolution (get complainant dispute) (get provider service)))
            (compensation (if auto-resolution (get amount-disputed dispute) u0))
        )
            (map-set service-disputes dispute-id (merge dispute { status: "resolved" }))
            
            (map-set dispute-resolution dispute-id {
                winner: winner,
                compensation-amount: compensation,
                resolution-type: "automated",
                resolved-at: stacks-block-height,
                arbitrator: (var-get arbitrator-address)
            })
            
            (if auto-resolution
                (map-set citizen-balances (get complainant dispute)
                    (+ (default-to u0 (map-get? citizen-balances (get complainant dispute))) compensation))
                true
            )
            
            (ok auto-resolution)
        )
    )
)

;; Dummy implementation for get-service-rating to resolve compile error
(define-read-only (get-service-rating (service-id uint))
    u5
)

;; Dummy implementation for get-service-uptime to resolve compile error
(define-read-only (get-service-uptime (service-id uint))
    (some u100)
)

(define-public (resolve-dispute-manual (dispute-id uint) (winner principal) (compensation uint))
    (let (
        (dispute (unwrap! (map-get? service-disputes dispute-id) err-not-found))
        (service (unwrap! (map-get? services (get service-id dispute)) err-not-found))
    )
        (asserts! (is-eq tx-sender (var-get arbitrator-address)) err-unauthorized)
        (asserts! (is-eq (get status dispute) "pending") (err u901))
        (asserts! (or (is-eq winner (get complainant dispute)) 
                      (is-eq winner (get provider service))) (err u906))
        
        (map-set service-disputes dispute-id (merge dispute { status: "resolved" }))
        
        (map-set dispute-resolution dispute-id {
            winner: winner,
            compensation-amount: compensation,
            resolution-type: "manual",
            resolved-at: stacks-block-height,
            arbitrator: tx-sender
        })
        
        (if (> compensation u0)
            (map-set citizen-balances winner
                (+ (default-to u0 (map-get? citizen-balances winner)) compensation))
            true
        )
        
        (ok true)
    )
)

(define-public (appeal-dispute-resolution (dispute-id uint) (appeal-evidence (string-ascii 500)))
    (let (
        (dispute (unwrap! (map-get? service-disputes dispute-id) err-not-found))
        (resolution (unwrap! (map-get? dispute-resolution dispute-id) err-not-found))
        (user-balance (default-to u0 (map-get? citizen-balances tx-sender)))
        (appeal-fee (* dispute-filing-fee u2))
    )
        (asserts! (is-eq (get status dispute) "resolved") (err u907))
        (asserts! (not (is-eq (get winner resolution) tx-sender)) (err u908))
        (asserts! (>= user-balance appeal-fee) err-insufficient-balance)
        (asserts! (< (- stacks-block-height (get resolved-at resolution)) u1440) (err u909))
        
        (map-set citizen-balances tx-sender (- user-balance appeal-fee))
        
        (map-set service-disputes dispute-id (merge dispute { status: "appealed" }))
        
        (ok true)
    )
)

(define-public (set-arbitrator (new-arbitrator principal))
    (begin
        (asserts! (is-eq tx-sender tx-sender) err-owner-only)
        (var-set arbitrator-address new-arbitrator)
        (ok true)
    )
)

(define-read-only (get-dispute-details (dispute-id uint))
    (map-get? service-disputes dispute-id)
)

(define-read-only (get-dispute-resolution (dispute-id uint))
    (map-get? dispute-resolution dispute-id)
)

(define-read-only (get-dispute-evidence (dispute-id uint) (evidence-id uint))
    (map-get? dispute-evidence { dispute-id: dispute-id, evidence-id: evidence-id })
)

(define-read-only (get-dispute-vote (dispute-id uint) (voter principal))
    (map-get? dispute-votes { dispute-id: dispute-id, voter: voter })
)




(define-read-only (is-dispute-active (dispute-id uint))
    (let ((dispute (map-get? service-disputes dispute-id)))
        (if (is-some dispute)
            (let ((dispute-data (unwrap-panic dispute)))
                (and (is-eq (get status dispute-data) "pending")
                     (< stacks-block-height (get resolution-deadline dispute-data)))
            )
            false
        )
    )
)
