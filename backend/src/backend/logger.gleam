import logging

pub fn configure() -> Nil {
  logging.configure()
  logging.set_level(logging.Info)
}

pub fn log_info(msg: String) -> Nil {
  logging.log(logging.Info, msg)
}

pub fn log_warn(msg: String) -> Nil {
  logging.log(logging.Warning, msg)
}

pub fn log_error(msg: String) -> Nil {
  logging.log(logging.Error, msg)
}
