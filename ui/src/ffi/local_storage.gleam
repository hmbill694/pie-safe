@external(javascript, "./local_storage.ffi.mjs", "getItem")
pub fn get_item(_key: String) -> Result(String, Nil) {
  Error(Nil)
}

@external(javascript, "./local_storage.ffi.mjs", "removeItem")
pub fn remove_item(_key: String) -> Nil {
  Nil
}
