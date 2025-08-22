;; Access Control Library
;; A reusable library providing role-based access control patterns
;; for Stacks blockchain smart contracts

;; Define the contract owner
(define-constant contract-owner tx-sender)

;; Error constants
(define-constant err-owner-only (err u100))
(define-constant err-unauthorized (err u101))
(define-constant err-invalid-role (err u102))
(define-constant err-already-has-role (err u103))
(define-constant err-does-not-have-role (err u104))

;; Role constants
(define-constant ADMIN_ROLE "admin")
(define-constant MODERATOR_ROLE "moderator")
(define-constant USER_ROLE "user")

;; Data structures
;; Map to store roles for each principal
(define-map user-roles 
  { user: principal, role: (string-ascii 20) } 
  { granted: bool, granted-at: uint, granted-by: principal })

;; Map to track role hierarchy and permissions
(define-map role-permissions 
  (string-ascii 20) 
  { level: uint, can-grant: (list 10 (string-ascii 20)) })

;; Initialize role permissions during contract deployment
(map-set role-permissions ADMIN_ROLE 
  { level: u3, can-grant: (list ADMIN_ROLE MODERATOR_ROLE USER_ROLE) })
(map-set role-permissions MODERATOR_ROLE 
  { level: u2, can-grant: (list USER_ROLE) })
(map-set role-permissions USER_ROLE 
  { level: u1, can-grant: (list) })

;; Grant the contract owner admin role automatically
(map-set user-roles 
  { user: contract-owner, role: ADMIN_ROLE }
  { granted: true, granted-at: stacks-block-height, granted-by: contract-owner })

;; Function 1: Grant Role
;; Allows authorized users to grant roles to other principals
(define-public (grant-role (user principal) (role (string-ascii 20)))
  (let (
    (granter-role-key { user: tx-sender, role: ADMIN_ROLE })
    (granter-mod-key { user: tx-sender, role: MODERATOR_ROLE })
    (target-key { user: user, role: role })
    (granter-admin (default-to { granted: false, granted-at: u0, granted-by: tx-sender } 
                                (map-get? user-roles granter-role-key)))
    (granter-mod (default-to { granted: false, granted-at: u0, granted-by: tx-sender } 
                              (map-get? user-roles granter-mod-key)))
    (role-perms (map-get? role-permissions role))
    (existing-role (map-get? user-roles target-key))
  )
    ;; Validate that the role exists
    (asserts! (is-some role-perms) err-invalid-role)
    
    ;; Check if user already has this role
    (asserts! (is-none existing-role) err-already-has-role)
    
    ;; Authorization check: either admin can grant any role, 
    ;; or moderator can grant user role only
    (asserts! (or 
      (get granted granter-admin)
      (and (get granted granter-mod) (is-eq role USER_ROLE))
    ) err-unauthorized)
    
    ;; Grant the role
    (map-set user-roles target-key
      { granted: true, granted-at: stacks-block-height, granted-by: tx-sender })
    
    (ok true)
  ))

;; Function 2: Has Role Check
;; Checks if a principal has a specific role and returns detailed information
(define-read-only (has-role (user principal) (role (string-ascii 20)))
  (let (
    (role-key { user: user, role: role })
    (role-info (map-get? user-roles role-key))
    (role-perms (map-get? role-permissions role))
  )
    (match role-info
      info (ok { 
        has-role: (get granted info), 
        granted-at: (get granted-at info),
        granted-by: (get granted-by info),
        role-level: (match role-perms perms (get level perms) u0)
      })
      (ok { 
        has-role: false, 
        granted-at: u0, 
        granted-by: tx-sender,
        role-level: u0 
      })
    )
  ))

;; Helper function: Get all role permissions (read-only)
(define-read-only (get-role-info (role (string-ascii 20)))
  (map-get? role-permissions role))

;; Helper function: Revoke role (bonus utility function)
(define-public (revoke-role (user principal) (role (string-ascii 20)))
  (let (
    (granter-role-key { user: tx-sender, role: ADMIN_ROLE })
    (target-key { user: user, role: role })
    (granter-admin (default-to { granted: false, granted-at: u0, granted-by: tx-sender } 
                                (map-get? user-roles granter-role-key)))
    (existing-role (map-get? user-roles target-key))
  )
    ;; Only admins can revoke roles
    (asserts! (get granted granter-admin) err-unauthorized)
    
    ;; Check if user has this role
    (asserts! (is-some existing-role) err-does-not-have-role)
    
    ;; Revoke the role by deleting the entry
    (map-delete user-roles target-key)
    
    (ok true)
  ))