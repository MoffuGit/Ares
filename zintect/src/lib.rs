mod runtime;
mod session;

use std::ffi::{c_char, c_void, CStr};

use runtime::Runtime;
use session::{EmitSpanFn, Session};

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
pub unsafe extern "C" fn zintect_session_reset(
    session: *mut c_void,
    runtime: *mut c_void,
) -> bool {
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
    line_index: u32,
    ctx: *mut c_void,
    emit: EmitSpanFn,
) -> bool {
    let session = match unsafe { session_mut(session) } {
        Some(s) => s,
        None => return false,
    };
    let runtime = match unsafe { runtime_ref(runtime) } {
        Some(r) => r,
        None => return false,
    };
    let line = match unsafe { cstr_to_str(line) } {
        Some(s) => s,
        None => return false,
    };
    session.highlight_line(runtime, line, line_index, ctx, emit)
}
