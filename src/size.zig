pub const CellSize = struct {
    width: u32,
    height: u32,
};

pub const Size = struct {
    screen: ScreenSize,
    cell: CellSize,
    pub fn grid(self: Size) GridSize {
        return .init(self.screen.subPadding(self.padding), self.cell);
    }
};

pub const ScreenSize = struct {
    width: u32,
    height: u32,
};

pub const GridSize = struct {
    pub const Unit = u16;

    columns: Unit = 0,
    rows: Unit = 0,

    /// Initialize a grid size based on a screen and cell size.
    pub fn init(screen: ScreenSize, cell: CellSize) GridSize {
        var result: GridSize = undefined;
        result.update(screen, cell);
        return result;
    }

    /// Update the columns/rows for the grid based on the given screen and
    /// cell size.
    pub fn update(self: *GridSize, screen: ScreenSize, cell: CellSize) void {
        const cell_width: f32 = @floatFromInt(cell.width);
        const cell_height: f32 = @floatFromInt(cell.height);
        const screen_width: f32 = @floatFromInt(screen.width);
        const screen_height: f32 = @floatFromInt(screen.height);
        const calc_cols: Unit = @intFromFloat(screen_width / cell_width);
        const calc_rows: Unit = @intFromFloat(screen_height / cell_height);
        self.columns = @max(1, calc_cols);
        self.rows = @max(1, calc_rows);
    }

    /// Returns true if two sizes are equal.
    pub fn equals(self: GridSize, other: GridSize) bool {
        return self.columns == other.columns and self.rows == other.rows;
    }
};
