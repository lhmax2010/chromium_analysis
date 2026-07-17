namespace std {
inline namespace __Cr {
void __libcpp_verbose_abort(const char*, ...);
}  // namespace __Cr
}  // namespace std

extern "C" __attribute__((visibility("default"))) void probe_anchor() {
  std::__Cr::__libcpp_verbose_abort("probe");
}
