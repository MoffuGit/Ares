mod instance;
mod runtime;

use std::ffi::{CStr, c_char, c_void};

use runtime::Runtime;

use crate::instance::Instance;

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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_create_runtime() -> *mut c_void {
    let runtime = Box::new(Runtime::new());

    Box::into_raw(runtime) as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_destroy_runtime(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }

    let runtime = unsafe { Box::from_raw(handle as *mut Runtime) };

    drop(runtime);
}

unsafe fn runtime_ref<'a>(handle: *mut c_void) -> Option<&'a Runtime> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &*(handle as *const Runtime) })
    }
}

unsafe fn instance_ref<'a>(handle: *mut c_void) -> Option<&'a Instance> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &*(handle as *const Instance) })
    }
}
#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_create_instance() -> *mut c_void {
    let instance = Box::new(Instance::new());

    Box::into_raw(instance) as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_destroy_instance(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }

    let instance = unsafe { Box::from_raw(handle as *mut Instance) };

    drop(instance);
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_initial_parse(
    runtime: *mut c_void,
    instance: *mut c_void,
    buffer: *const c_char,
    extension: *const c_char,
) {
    let runtime = unsafe { runtime_ref(runtime).unwrap() };
    let instance = unsafe { instance_ref(instance).unwrap() };
    let buffer = match unsafe { cstr_to_str(buffer) } {
        Some(s) => s,
        None => panic!("aaaaaa"),
    };
    let extension = match unsafe { cstr_to_str(extension) } {
        Some(s) => s,
        None => panic!("aaaaaa"),
    };

    instance.initial_parse(runtime, buffer, extension);
}
