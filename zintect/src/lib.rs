mod instance;

use std::ffi::{CStr, CString, c_char, c_void};

use instance::Instance;

/// Helper to convert C string to Rust &str.
///
/// Returns `None` if the pointer is null or the string is not valid UTF-8.
unsafe fn cstr_to_str<'a>(s: *const c_char) -> Option<&'a str> {
    if s.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(s).to_str().ok() }
    }
}

/// Helper to convert an optional C string parameter.
///
/// Returns `None` if the pointer is null, empty, or not valid UTF-8.
unsafe fn optional_cstr<'a>(s: *const c_char) -> Option<&'a str> {
    unsafe { cstr_to_str(s) }.filter(|s| !s.is_empty())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_create_instance() -> *mut c_void {
    let instace = Box::new(Instance::new());

    Box::into_raw(instace) as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_destroy_instace(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }

    let instance = unsafe { Box::from_raw(handle as *mut Instance) };

    drop(instance);
}

#[unsafe(no_mangle)]
pub extern "C" fn ping_rust(ping: bool) -> bool {
    !ping
}
