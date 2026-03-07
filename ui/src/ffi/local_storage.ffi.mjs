import { Ok, Error } from "../gleam.mjs";

export function getItem(key) {
  const value = window.localStorage.getItem(key);
  if (value === null) {
    return new Error(undefined);
  }
  return new Ok(value);
}

export function removeItem(key) {
  window.localStorage.removeItem(key);
  return undefined;
}
