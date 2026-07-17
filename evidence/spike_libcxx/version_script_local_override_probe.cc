namespace std {
inline namespace __Cr {
__attribute__((visibility("default"))) void __libcpp_verbose_abort(
    const char*,
    ...) {}
__attribute__((visibility("default"))) void keep_probe() {}
}  // namespace __Cr
}  // namespace std

extern "C" __attribute__((visibility("default"))) void ewk_probe() {}
