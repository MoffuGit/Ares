const std = @import("std");
const triepkg = @import("../datastruct/trie.zig");
const keystrokepkg = @import("KeyStroke.zig");

const KeyStroke = keystrokepkg.KeyStroke;
const KeyStrokeContext = keystrokepkg.KeyStrokeContext;

const Allocator = std.mem.Allocator;
const KeyStrokeActions = triepkg.Trie(KeyStroke, Action, KeyStrokeContext);

//NOTE:
//the current impl for keymaps has the followings problem,
//lets say we have two different structures that have two different
//actions but they want to share the same keymap,
//or for example, the Command, maybe the owner of this data is the Workspace but
//on a tree level the Command lives as a child of root, not a child of Workspace,
//if Workspace handle all the KeyMaps,
//one options could be making the Workspace the only
//component capable of accessing the keymaps and then, in base of his state
//it would choose what action to make, or another option it could be
//that every strcuture can accees the resolver and resolve his own
//keymaps and actions, for me the second has more sense
//we already have the elemnt tree system for the events,
//but how we can handle the followings case
//
//Workspace -> ctrl+k toggle X
//Command -> ctrl+k j clear input
//Editor -> ctrl+k l open lsp erros
//UndoTree -> ctrl+k j clear tree
//
//the three keymaps have different callbacks
//that need to be handled by different structures
//
//or for example, the enter visual and insert mode
//should not happen on all Elements, only element that are selectable or editable
//should trigger that change
//
//The "Resolver" should be an strcuture that trigger App Events,
//that way any of the structures can subscribe to this events
//when an action gets trigger, all of them can check what action is and if
//is an action that they should handle, there are some structures that should subscribe
//and unsubscribe in base of the focus, there are other structures that should always be subscribe
//but that become really easy to handle
//
//first we should check how to make our Action and Trie capable
//of having the same keymap but with different actions
//
//and then add to app the Key maps action event, and then subscribe and unsubscribe the correct components

pub const Action = enum {
    enter_insert,
    enter_visual,
    enter_normal,

    toggle_left_dock,
    toggle_right_dock,
    toggle_command_palette,

    new_tab,
    close_active_tab,
    next_tab,
    prev_tab,
};

pub const Mode = enum { normal, insert, visual };

pub const Keymaps = struct {
    normal: KeyStrokeActions,
    insert: KeyStrokeActions,
    visual: KeyStrokeActions,

    pub fn init(alloc: std.mem.Allocator) !Keymaps {
        return .{
            .normal = try KeyStrokeActions.init(alloc),
            .insert = try KeyStrokeActions.init(alloc),
            .visual = try KeyStrokeActions.init(alloc),
        };
    }

    pub fn deinit(self: *Keymaps) void {
        self.normal.deinit();
        self.insert.deinit();
        self.visual.deinit();
    }

    pub fn actions(self: *Keymaps, mode: Mode) *KeyStrokeActions {
        return switch (mode) {
            .normal => &self.normal,
            .insert => &self.insert,
            .visual => &self.visual,
        };
    }
};

test {
    _ = keystrokepkg;
}
