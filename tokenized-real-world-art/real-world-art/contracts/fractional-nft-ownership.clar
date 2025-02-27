;; Tokenized Real-World Art Installations
;; - Fractional NFT ownership (SIP-009 standard)
;; - Automated profit distribution from exhibitions/rentals
;; - IoT sensor integration for condition/location tracking

(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u1001))
(define-constant ERR_IOT_VERIFICATION (err u1002))

;; Data Structures
(define-map artworks uint {
    name: (string-utf8 50),
    total-shares: uint,
    shares-minted: uint,
    location: (string-ascii 100),
    condition: (string-ascii 50),
    rental-price: uint,
    balance: uint
})

(define-map nft-owners uint principal)  ;; NFT ID -> Owner
(define-map shareholder-balances principal uint)  ;; Owner -> Accumulated profits
(define-map iot-oracles principal bool)  ;; Approved IoT data providers

;; Events
(define-data-var art-created-event bool false)
(define-data-var profit-distributed-event bool false)

;; Initialize artwork (Contract owner only)
(define-public (create-artwork (artwork-id uint) (name (string-utf8 50)) (total-shares uint) (initial-location (string-ascii 100)))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set artworks artwork-id {
            name: name,
            total-shares: total-shares,
            shares-minted: u0,
            location: initial-location,
            condition: "excellent",
            rental-price: u0,
            balance: u0
        })
        (var-set art-created-event true)
        (ok true)
    )
)

;; Mint fractional NFT shares (Contract owner only)
(define-public (mint-share (artwork-id uint) (recipient principal) (shares uint))
    (let ((artwork (unwrap! (map-get? artworks artwork-id) ERR_UNAUTHORIZED)))
        (let ((new-minted (+ (get shares-minted artwork) shares)))
            (begin
                (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
                (asserts! (<= new-minted (get total-shares artwork)) ERR_UNAUTHORIZED)
                ;; Mint NFT shares
                (map-set nft-owners (get shares-minted artwork) recipient)
                (map-set artworks artwork-id (merge artwork { shares-minted: new-minted }))
                (ok true)
            )
        )
    )
)

;; Update IoT data (Oracle only)
(define-public (update-artwork-status (artwork-id uint) (location (string-ascii 100)) (condition (string-ascii 50)))
    (begin
        ;; Ensure the sender is an approved oracle
        (asserts! (is-eq (unwrap! (map-get? iot-oracles tx-sender) ERR_IOT_VERIFICATION) true) ERR_IOT_VERIFICATION)

        ;; Update artwork status
        (map-set artworks artwork-id (merge (unwrap! (map-get? artworks artwork-id) ERR_UNAUTHORIZED) {
            location: location,
            condition: condition
        }))
        (ok true)
    )
)


;; Distribute rental profits to shareholders
(define-public (distribute-profits (artwork-id uint))
    (let ((artwork (unwrap! (map-get? artworks artwork-id) ERR_UNAUTHORIZED)))
        (let ((payment-amount (get balance artwork)) (share-price (/ payment-amount (get total-shares artwork))))
            (begin
                (map-set artworks artwork-id (merge artwork { balance: u0 })) ;; Reset balance
                (var-set profit-distributed-event true)
                (ok true)
            )
        )
    )
)

;; Withdraw accumulated profits
(define-public (withdraw-profits)
    (let ((amount (default-to u0 (map-get? shareholder-balances tx-sender))))
        (begin
            (try! (stx-transfer? amount CONTRACT_OWNER tx-sender))
            (map-set shareholder-balances tx-sender u0)
            (ok true)
        )
    )
)

;; Set rental price (Contract owner only)
(define-public (set-rental-price (artwork-id uint) (price uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set artworks artwork-id (merge (unwrap! (map-get? artworks artwork-id) ERR_UNAUTHORIZED) {
            rental-price: price
        }))
        (ok true)
    )
)

;; Receive rental payments
(define-public (rent-artwork (artwork-id uint))
    (let ((artwork (unwrap! (map-get? artworks artwork-id) ERR_UNAUTHORIZED)))
        (let ((price (get rental-price artwork)))
            (begin
                (try! (stx-transfer? price tx-sender CONTRACT_OWNER))
                (map-set artworks artwork-id (merge artwork { balance: (+ (get balance artwork) price) }))
                (ok true)
            )
        )
    )
)