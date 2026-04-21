mod runtime;
mod session;
mod theme;

use std::ffi::{CStr, c_char, c_void};

use runtime::Runtime;
use session::Session;

use crate::session::{FffHighlightResult, FffResult};

unsafe fn cstr_to_str<'a>(s: *const c_char) -> Option<&'a str> {
    if s.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(s).to_str().ok() }
    }
}

unsafe fn runtime_ref<'a>(handle: *mut c_void) -> Option<&'a Runtime> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &*(handle as *const Runtime) })
    }
}

unsafe fn runtime_mut<'a>(handle: *mut c_void) -> Option<&'a mut Runtime> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &mut *(handle as *mut Runtime) })
    }
}

unsafe fn session_mut<'a>(handle: *mut c_void) -> Option<&'a mut Session> {
    if handle.is_null() {
        None
    } else {
        Some(unsafe { &mut *(handle as *mut Session) })
    }
}

// --- Runtime ---

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
    let _ = unsafe { Box::from_raw(handle as *mut Runtime) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_runtime_set_theme(
    handle: *mut c_void,
    theme_json: *const c_char,
) -> bool {
    let runtime = match unsafe { runtime_mut(handle) } {
        Some(r) => r,
        None => return false,
    };
    let json = match unsafe { cstr_to_str(theme_json) } {
        Some(s) => s,
        None => return false,
    };
    runtime.set_theme_from_json(json)
}

// --- Session ---

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_create_session() -> *mut c_void {
    let session = Box::new(Session::new());
    Box::into_raw(session) as *mut c_void
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_destroy_session(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let _ = unsafe { Box::from_raw(handle as *mut Session) };
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_session_set_syntax_by_ext(
    session: *mut c_void,
    runtime: *mut c_void,
    ext: *const c_char,
) -> bool {
    let session = match unsafe { session_mut(session) } {
        Some(s) => s,
        None => return false,
    };
    let runtime = match unsafe { runtime_ref(runtime) } {
        Some(r) => r,
        None => return false,
    };
    let ext = match unsafe { cstr_to_str(ext) } {
        Some(s) => s,
        None => return false,
    };
    session.set_syntax_by_ext(runtime, ext)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_session_reset(session: *mut c_void, runtime: *mut c_void) -> bool {
    let session = match unsafe { session_mut(session) } {
        Some(s) => s,
        None => return false,
    };
    let runtime = match unsafe { runtime_ref(runtime) } {
        Some(r) => r,
        None => return false,
    };
    session.reset(runtime)
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn zintect_session_highlight_line(
    session: *mut c_void,
    runtime: *mut c_void,
    line: *const c_char,
) -> FffResult {
    let session = match unsafe { session_mut(session) } {
        Some(s) => s,
        None => return FffResult::err(),
    };
    let runtime = match unsafe { runtime_ref(runtime) } {
        Some(r) => r,
        None => return FffResult::err(),
    };
    let line = match unsafe { cstr_to_str(line) } {
        Some(s) => s,
        None => return FffResult::err(),
    };

    session.highlight_line(runtime, line)
}

/// Free a result returned by any `fff_*` function.
///
/// ## Safety
/// `result_ptr` must be a valid pointer returned by a `fff_*` function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_free_result(result_ptr: *mut FffResult) {
    if result_ptr.is_null() {
        return;
    }

    unsafe {
        _ = Box::from_raw(result_ptr);
        // Note: `handle` is NOT freed here — the caller must free it
        // with the appropriate function (fff_destroy, fff_free_search_result,
        // fff_free_grep_result, fff_free_string, fff_free_scan_progress, etc.).
    }
}

/// Free a result returned by any `fff_*` function.
///
/// ## Safety
/// `result_ptr` must be a valid pointer returned by a `fff_*` function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn fff_free_highlight_result(result_ptr: *mut FffHighlightResult) {
    if result_ptr.is_null() {
        return;
    }

    unsafe {
        let result = Box::from_raw(result_ptr);

        if !result.items.is_null() {
            let count = result.count as usize;
            _ = Vec::from_raw_parts(result.items, count, count);
        }
        // Note: `handle` is NOT freed here — the caller must free it
        // with the appropriate function (fff_destroy, fff_free_search_result,
        // fff_free_grep_result, fff_free_string, fff_free_scan_progress, etc.).
    }
}
