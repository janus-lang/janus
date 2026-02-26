/// Zig 0.16 compat: blocking Mutex and Condition variable.
/// Replaces std.Thread.Mutex and std.Thread.Condition (removed in 0.16).
/// Uses pthread internally (requires libc linkage).
const std = @import("std");

pub const Mutex = struct {
    inner: std.c.pthread_mutex_t = std.c.PTHREAD_MUTEX_INITIALIZER,

    pub fn lock(self: *Mutex) void {
        const rc = std.c.pthread_mutex_lock(&self.inner);
        std.debug.assert(rc == .SUCCESS);
    }

    pub fn unlock(self: *Mutex) void {
        const rc = std.c.pthread_mutex_unlock(&self.inner);
        std.debug.assert(rc == .SUCCESS);
    }

    pub fn tryLock(self: *Mutex) bool {
        return std.c.pthread_mutex_trylock(&self.inner) == .SUCCESS;
    }
};

pub const Condition = struct {
    inner: std.c.pthread_cond_t = std.c.PTHREAD_COND_INITIALIZER,

    /// Block until signaled. Atomically releases mutex, sleeps, re-acquires.
    pub fn wait(self: *Condition, mutex: *Mutex) void {
        const rc = std.c.pthread_cond_wait(&self.inner, &mutex.inner);
        std.debug.assert(rc == .SUCCESS);
    }

    /// Wake one waiting thread.
    pub fn signal(self: *Condition) void {
        const rc = std.c.pthread_cond_signal(&self.inner);
        std.debug.assert(rc == .SUCCESS);
    }

    /// Wake all waiting threads.
    pub fn broadcast(self: *Condition) void {
        const rc = std.c.pthread_cond_broadcast(&self.inner);
        std.debug.assert(rc == .SUCCESS);
    }
};
