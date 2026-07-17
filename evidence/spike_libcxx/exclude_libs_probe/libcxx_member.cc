namespace std {
inline namespace __Cr {

__attribute__((weak, visibility("default"))) void __libcpp_verbose_abort(
    const char*, ...) {
  __builtin_trap();
}

}  // namespace __Cr
}  // namespace std
