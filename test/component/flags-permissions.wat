(component
  ;; Core module that toggles a specific permission bit
  (core module $impl
    ;; toggle_read(flags) -> flags ^ READ_BIT
    ;; READ = bit 0
    (func $toggle_read (export "toggle_read") (param i32) (result i32)
      (i32.xor (local.get 0) (i32.const 1))
    )

    ;; has_write(flags) -> (flags & WRITE_BIT) != 0
    ;; WRITE = bit 1
    (func $has_write (export "has_write") (param i32) (result i32)
      (i32.and
        (i32.shr_u (local.get 0) (i32.const 1))
        (i32.const 1)
      )
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Flags type: permissions with read, write, execute
  (type $permissions (flags "read" "write" "execute"))
  (type $toggle-read-type (func (param "perms" $permissions) (result $permissions)))
  (type $has-write-type (func (param "perms" $permissions) (result bool)))

  (alias core export $inst "toggle_read" (core func $core-toggle-read))
  (alias core export $inst "has_write" (core func $core-has-write))

  (func $toggle-read (type $toggle-read-type)
    (canon lift (core func $core-toggle-read)))

  (func $has-write (type $has-write-type)
    (canon lift (core func $core-has-write)))

  (export "toggle-read" (func $toggle-read))
  (export "has-write" (func $has-write))
)
