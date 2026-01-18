(component
  ;; Component that shares memory between two core modules

  ;; First core module: provides memory and a function to write to it
  (core module $provider
    (memory $mem (export "memory") 1)

    ;; Write value to memory at offset
    (func $write (export "write") (param i32 i32)
      (i32.store (local.get 0) (local.get 1))
    )

    ;; Read value from memory at offset
    (func $read (export "read") (param i32) (result i32)
      (i32.load (local.get 0))
    )
  )

  (core instance $provider-inst (instantiate $provider))

  ;; Alias the exported memory
  (alias core export $provider-inst "memory" (core memory $shared-mem))

  ;; Second core module: uses the shared memory
  (core module $consumer
    (import "env" "memory" (memory 1))

    ;; Double the value at offset
    (func $double (export "double") (param i32)
      (local $val i32)
      (local.set $val (i32.load (local.get 0)))
      (i32.store (local.get 0) (i32.mul (local.get $val) (i32.const 2)))
    )
  )

  ;; Create import instance with shared memory
  (core instance $env-exports
    (export "memory" (memory $shared-mem))
  )

  (core instance $consumer-inst (instantiate $consumer
    (with "env" (instance $env-exports))
  ))

  ;; Alias and lift functions
  (alias core export $provider-inst "write" (core func $core-write))
  (alias core export $provider-inst "read" (core func $core-read))
  (alias core export $consumer-inst "double" (core func $core-double))

  ;; Define component types
  (type $write-type (func (param "offset" s32) (param "value" s32)))
  (type $read-type (func (param "offset" s32) (result s32)))
  (type $double-type (func (param "offset" s32)))

  ;; Lift and export
  (func $write (type $write-type) (canon lift (core func $core-write)))
  (func $read (type $read-type) (canon lift (core func $core-read)))
  (func $double (type $double-type) (canon lift (core func $core-double)))

  (export "write" (func $write))
  (export "read" (func $read))
  (export "double" (func $double))
)
