///[min, max) range
pub const Rngu64 = struct {
    min: u64,
    max: u64,

    pub fn contains(self: *const @This(), int: u64) bool {
        return int >= self.min and int < self.max;
    }

    pub fn dim(self: *const @This()) u64 {
        return if (self.max > self.min) self.max - self.min else 0;
    }
};
