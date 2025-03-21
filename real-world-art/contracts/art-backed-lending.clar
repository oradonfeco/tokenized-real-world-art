;; Art-Backed Lending Protocol
;; - Enables NFT shareholders to use their art shares as collateral for loans
;; - Creates liquidity from relatively illiquid art assets
;; - Maintains ownership while accessing capital
;; - Generates additional value streams beyond appreciation/exhibitions

(define-constant CONTRACT_OWNER tx-sender)

;; Error codes
(define-constant ERR_UNAUTHORIZED (err u2001))
(define-constant ERR_INVALID_LOAN (err u2002))
(define-constant ERR_INSUFFICIENT_COLLATERAL (err u2003))
(define-constant ERR_LOAN_NOT_ACTIVE (err u2004))
(define-constant ERR_LOAN_ALREADY_ACTIVE (err u2005))
(define-constant ERR_REPAYMENT_FAILED (err u2006))
(define-constant ERR_LIQUIDATION_FAILED (err u2007))
(define-constant ERR_INVALID_AMOUNT (err u2008))
(define-constant ERR_LOAN_NOT_DEFAULTED (err u2009))

;; Loan status constants
(define-constant LOAN_STATUS_OFFERED u1)
(define-constant LOAN_STATUS_ACTIVE u2)
(define-constant LOAN_STATUS_REPAID u3)
(define-constant LOAN_STATUS_DEFAULTED u4)
(define-constant LOAN_STATUS_LIQUIDATED u5)

;; Contract for tokenized art - replace with actual contract address when deploying
(define-constant ART_CONTRACT 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.tokenized-art)

;; Data Structures
(define-map loan-offers uint {
    lender: principal,
    interest-rate: uint,  ;; Annual interest rate in basis points (e.g., 500 = 5%)
    duration: uint,       ;; Loan duration in days
    min-collateral-ratio: uint,  ;; Minimum collateral-to-loan ratio in basis points (e.g., 15000 = 150%)
    max-amount: uint,     ;; Maximum loan amount in STX
    status: uint          ;; Offer status
})

(define-map active-loans uint {
    loan-offer-id: uint,
    borrower: principal,
    lender: principal,
    principal-amount: uint,
    interest-rate: uint,
    start-block: uint,
    end-block: uint,
    collateral-ratio: uint,
    status: uint,
    collateral-artwork-id: uint,
    collateral-shares: (list 10 uint)  ;; List of share IDs used as collateral
})

(define-map artwork-valuations uint uint)  ;; Artwork ID -> Valuation in STX per share

;; Counters for IDs
(define-data-var next-loan-offer-id uint u1)
(define-data-var next-loan-id uint u1)

;; Events
(define-data-var loan-created-event bool false)
(define-data-var loan-repaid-event bool false)
(define-data-var loan-liquidated-event bool false)

;; Helper function to calculate blocks from days
(define-private (days-to-blocks (days uint))
    ;; Assuming ~10 minute blocks, 144 blocks per day
    (* days u144)
)

;; Helper function to get minimum of two uints
(define-private (min-uint (a uint) (b uint))
    (if (<= a b) a b)
)

;; Helper function to check if a loan is defaulted
(define-private (is-loan-defaulted (loan-id uint))
    (match (map-get? active-loans loan-id)
        loan-data (and 
            (is-eq (get status loan-data) LOAN_STATUS_ACTIVE)
            (> stacks-block-height (get end-block loan-data))
        )
        false
    )
)

;; Helper function to calculate total repayment amount with interest
(define-private (calculate-repayment-amount (loan-id uint))
    (match (map-get? active-loans loan-id)
        loan-data (let (
                (principal (get principal-amount loan-data))
                (rate (get interest-rate loan-data))
                (duration-blocks (- (get end-block loan-data) (get start-block loan-data)))
                (elapsed-blocks (- (min-uint stacks-block-height (get end-block loan-data)) (get start-block loan-data)))
            )
                ;; Calculate interest: principal * rate * time / 10000 / 365 days in blocks
                (let (
                    (interest-per-year (/ (* principal rate) u10000))
                    (interest-per-block (/ interest-per-year (* u144 u365)))
                    (interest-amount (* interest-per-block elapsed-blocks))
                )
                    (+ principal interest-amount)
                )
            )
        u0  ;; Return 0 if loan not found - this should never happen in practice
    )
)

;; Create a loan offer (by lenders)
(define-public (create-loan-offer (interest-rate uint) (duration uint) (min-collateral-ratio uint) (max-amount uint))
    (let ((offer-id (var-get next-loan-offer-id)))
        (begin
            ;; Validate inputs
            (asserts! (> interest-rate u0) ERR_INVALID_LOAN)
            (asserts! (> duration u0) ERR_INVALID_LOAN)
            (asserts! (>= min-collateral-ratio u12500) ERR_INVALID_LOAN)  ;; Minimum 125% collateral ratio
            (asserts! (> max-amount u0) ERR_INVALID_LOAN)
            
            ;; Create the loan offer
            (map-set loan-offers offer-id {
                lender: tx-sender,
                interest-rate: interest-rate,
                duration: duration,
                min-collateral-ratio: min-collateral-ratio,
                max-amount: max-amount,
                status: LOAN_STATUS_OFFERED
            })
            
            ;; Increment the offer ID counter
            (var-set next-loan-offer-id (+ offer-id u1))
            
            (ok offer-id)
        )
    )
)

;; Cancel a loan offer (by lender)
(define-public (cancel-loan-offer (offer-id uint))
    (match (map-get? loan-offers offer-id)
        offer-data (begin
            ;; Ensure sender is the lender
            (asserts! (is-eq tx-sender (get lender offer-data)) ERR_UNAUTHORIZED)
            ;; Ensure offer is still in offered status
            (asserts! (is-eq (get status offer-data) LOAN_STATUS_OFFERED) ERR_LOAN_NOT_ACTIVE)
            
            ;; Update offer status
            (map-set loan-offers offer-id (merge offer-data { status: u0 }))
            
            (ok true)
        )
        ERR_INVALID_LOAN
    )
)

;; Set artwork valuation (by contract owner or authorized oracle)
(define-public (set-artwork-valuation (artwork-id uint) (valuation-per-share uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
        (map-set artwork-valuations artwork-id valuation-per-share)
        (ok true)
    )
)

;; Take a loan using art shares as collateral
(define-public (take-loan (offer-id uint) (amount uint) (artwork-id uint) (share-ids (list 10 uint)))
    (match (map-get? loan-offers offer-id)
        offer-data (let (
            (loan-id (var-get next-loan-id))
            (share-count (len share-ids))
        )
            (begin
                ;; Validate the loan request
                (asserts! (is-eq (get status offer-data) LOAN_STATUS_OFFERED) ERR_LOAN_NOT_ACTIVE)
                (asserts! (<= amount (get max-amount offer-data)) ERR_INVALID_AMOUNT)
                (asserts! (> share-count u0) ERR_INSUFFICIENT_COLLATERAL)
                
                ;; Calculate collateral value
                (let (
                    (share-value (default-to u0 (map-get? artwork-valuations artwork-id)))
                    (total-collateral-value (* share-count share-value))
                    (collateral-ratio (/ (* total-collateral-value u10000) amount))
                )
                    ;; Ensure sufficient collateral
                    (asserts! (>= collateral-ratio (get min-collateral-ratio offer-data)) ERR_INSUFFICIENT_COLLATERAL)
                    
                    ;; Transfer the loan amount to borrower
                    (try! (stx-transfer? amount (get lender offer-data) tx-sender))
                    
                    ;; Lock the collateral shares
                    ;; Note: In a real implementation, you would call the art contract to transfer shares to this contract
                    ;; For each share in share-ids, transfer from tx-sender to this contract
                    
                    ;; Create the active loan
                    (map-set active-loans loan-id {
                        loan-offer-id: offer-id,
                        borrower: tx-sender,
                        lender: (get lender offer-data),
                        principal-amount: amount,
                        interest-rate: (get interest-rate offer-data),
                        start-block: stacks-block-height,
                        end-block: (+ stacks-block-height (days-to-blocks (get duration offer-data))),
                        collateral-ratio: collateral-ratio,
                        status: LOAN_STATUS_ACTIVE,
                        collateral-artwork-id: artwork-id,
                        collateral-shares: share-ids
                    })
                    
                    ;; Update loan offer status
                    (map-set loan-offers offer-id (merge offer-data { status: LOAN_STATUS_ACTIVE }))
                    
                    ;; Increment loan ID counter
                    (var-set next-loan-id (+ loan-id u1))
                    (var-set loan-created-event true)
                    
                    (ok loan-id)
                )
            )
        )
        ERR_INVALID_LOAN
    )
)

;; Repay a loan
(define-public (repay-loan (loan-id uint))
    (match (map-get? active-loans loan-id)
        loan-data (begin
            ;; Ensure loan is active
            (asserts! (is-eq (get status loan-data) LOAN_STATUS_ACTIVE) ERR_LOAN_NOT_ACTIVE)
            ;; Ensure sender is the borrower
            (asserts! (is-eq tx-sender (get borrower loan-data)) ERR_UNAUTHORIZED)
            
            ;; Calculate repayment amount with interest
            (let ((repayment-amount (calculate-repayment-amount loan-id)))
                ;; Transfer repayment to lender
                (try! (stx-transfer? repayment-amount tx-sender (get lender loan-data)))
                
                ;; Return collateral to borrower
                ;; Note: In a real implementation, you would call the art contract to transfer shares back
                ;; For each share in collateral-shares, transfer from this contract to borrower
                
                ;; Update loan status
                (map-set active-loans loan-id (merge loan-data { status: LOAN_STATUS_REPAID }))
                (var-set loan-repaid-event true)
                
                (ok true)
            )
        )
        ERR_INVALID_LOAN
    )
)

;; Liquidate a defaulted loan
(define-public (liquidate-loan (loan-id uint))
    (match (map-get? active-loans loan-id)
        loan-data (begin
            ;; Ensure sender is the lender
            (asserts! (is-eq tx-sender (get lender loan-data)) ERR_UNAUTHORIZED)
            ;; Ensure loan is defaulted
            (asserts! (is-loan-defaulted loan-id) ERR_LOAN_NOT_DEFAULTED)
            
            ;; Transfer collateral to lender
            ;; Note: In a real implementation, you would call the art contract to transfer shares to lender
            ;; For each share in collateral-shares, transfer from this contract to lender
            
            ;; Update loan status
            (map-set active-loans loan-id (merge loan-data { status: LOAN_STATUS_LIQUIDATED }))
            (var-set loan-liquidated-event true)
            
            (ok true)
        )
        ERR_INVALID_LOAN
    )
)

;; Get loan details
(define-read-only (get-loan-details (loan-id uint))
    (map-get? active-loans loan-id)
)

;; Get loan offer details
(define-read-only (get-loan-offer-details (offer-id uint))
    (map-get? loan-offers offer-id)
)

;; Get current repayment amount for a loan
(define-read-only (get-repayment-amount (loan-id uint))
    (ok (calculate-repayment-amount loan-id))
)

;; Check if a loan is in default
(define-read-only (check-loan-default (loan-id uint))
    (ok (is-loan-defaulted loan-id))
)

;; Get artwork valuation
(define-read-only (get-artwork-valuation (artwork-id uint))
    (default-to u0 (map-get? artwork-valuations artwork-id))
)