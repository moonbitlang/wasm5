(component
  ;; Core module that returns the next color in a cycle
  (core module $impl
    ;; next_color(current) -> next
    ;; red(0) -> green(1) -> blue(2) -> red(0)
    (func $next_color (export "next_color") (param i32) (result i32)
      (i32.rem_u
        (i32.add (local.get 0) (i32.const 1))
        (i32.const 3)
      )
    )
  )

  (core instance $inst (instantiate $impl))

  ;; Enum type: color with red, green, blue
  (type $color (enum "red" "green" "blue"))
  (type $next-color-type (func (param "current" $color) (result $color)))

  (alias core export $inst "next_color" (core func $core-next-color))

  (func $next-color (type $next-color-type)
    (canon lift (core func $core-next-color)))

  (export "next-color" (func $next-color))
)
