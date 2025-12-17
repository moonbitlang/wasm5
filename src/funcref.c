int apply_func_ref(int (*f)(void*), void* rt) {
  return f(rt);
}