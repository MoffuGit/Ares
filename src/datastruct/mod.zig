const BlockingQueue = @import("./blocking_queue.zig");
const BPlusTree = @import("b_plus_tree.zig");

test {
    _ = BlockingQueue;
    _ = BPlusTree;
}

//NOTE:
//when deleting,
//first we need to find the value,
//if we do this:
//we remove it and then check for underflowing
//if this is happening
//we first try to take from the siblings
//if is not possible, we merge with one of the sibling
//remember to update the keys values, i think this would happen all the way to the root node
//
// pub fn delete(self: *Self, key: K, alloc: Allocator) !V {
//     switch (self.*) {
//         .Leaf => |*leaf| {
//             var i: u16 = 0;
//             while (i < leaf.len) {
//                 switch (comp(key, leaf.keys[i])) {
//                     .eq => {
//                         const removed_value = leaf.items[i];
//
//                         var j: u16 = i;
//                         while (j < leaf.len - 1) {
//                             leaf.keys[j] = leaf.keys[j + 1];
//                             leaf.items[j] = leaf.items[j + 1];
//                             j += 1;
//                         }
//                         leaf.len -= 1;
//                         return removed_value;
//                     },
//                     .lt => break,
//                     .gt => i += 1,
//                 }
//             }
//             return error.NotFound;
//         },
//         .Internal => |*internal| {
//             var child_idx: u16 = 0;
//             while (child_idx < internal.len) {
//                 if (comp(key, internal.keys[child_idx]) == .lt) {
//                     break;
//                 }
//                 child_idx += 1;
//             }
//             // Adjust child_idx for the correct child to descend into based on key comparison logic
//             // If keys[idx] is the smallest key of childs[idx], then find logic `childs[idx-1]` is wrong.
//             // The find method does: `return internal.childs[idx - 1].find(key);`
//             // So for deletion, we follow that logic.
//             // If `idx` is 0, it means the key is smaller than `internal.keys[0]`, so go to `childs[0]`.
//             // If `idx` is `internal.len`, it means key is larger than all internal keys, go to `childs[internal.len - 1]`.
//             // Otherwise, key is between `internal.keys[idx-1]` and `internal.keys[idx]`, go to `childs[idx-1]`.
//             // The `while` loop sets `child_idx` to the index of the first key greater than or equal to `key`.
//             // So the target child is `internal.childs[child_idx]`.
//
//             // The find logic:
//             // var idx: u16 = 1;
//             // while (idx < internal.len) { if (comp(key, internal.keys[idx]) == .lt) { break; } idx += 1; }
//             // return internal.childs[idx - 1].find(key);
//             // This means `internal.keys[idx]` is the boundary *before* `internal.childs[idx]`.
//             // Let's re-align the deletion to this `find` pattern.
//
//             var search_idx: u16 = 1;
//             while (search_idx < internal.len) {
//                 switch (comp(key, internal.keys[search_idx])) {
//                     .eq => {
//                         search_idx += 1;
//                         break;
//                     },
//                     .gt => {
//                         search_idx += 1;
//                     },
//                     .lt => {
//                         break;
//                     },
//                 }
//             }
//             child_idx = search_idx - 1; // This is the child to descend into
//
//             const removed_value = try internal.childs[child_idx].delete(key, alloc);
//
//             if (internal.childs[child_idx].is_underflowing()) {
//                 try self.rebalance_child(child_idx, alloc);
//             }
//
//             // Update parent's key if necessary (if the smallest key in the child changed)
//             // This logic is crucial for B+ trees where internal keys are copies of leaf keys.
//             // If a key was removed from `internal.childs[child_idx]` and it was its first key,
//             // or if a merge happened, the representative key in the parent might need update.
//             // After rebalancing, the child might have a new minimum key.
//             // If `child_idx` is still valid (not merged away), update its key in the parent.
//             if (child_idx < internal.len) {
//                 internal.keys[child_idx] = internal.childs[child_idx].keys()[0];
//             }
//
//             return removed_value;
//         },
//     }
// }
//
// fn rebalance_child(self: *Self, child_idx: u16, alloc: Allocator) !void {
//     var internal = &self.Internal;
//     var underflowing_child = internal.childs[child_idx];
//
//     // Try to redistribute from left sibling
//     if (child_idx > 0) {
//         const left_sibling_idx = child_idx - 1;
//         var left_sibling = internal.childs[left_sibling_idx];
//
//         if (left_sibling.len() > BASE) {
//             if (underflowing_child.is_leaf()) {
//                 var uf_leaf = &underflowing_child.Leaf;
//                 var ls_leaf = &left_sibling.Leaf;
//
//                 // Shift existing elements in underflowing_child to make space at index 0
//                 var i: u16 = uf_leaf.len;
//                 while (i > 0) : (i -= 1) {
//                     uf_leaf.keys[i] = uf_leaf.keys[i - 1];
//                     uf_leaf.items[i] = uf_leaf.items[i - 1];
//                 }
//                 // Move item from left sibling to underflowing child
//                 uf_leaf.keys[0] = ls_leaf.keys[ls_leaf.len - 1];
//                 uf_leaf.items[0] = ls_leaf.items[ls_leaf.len - 1];
//                 uf_leaf.len += 1;
//                 ls_leaf.len -= 1;
//
//                 // Update key in parent
//                 internal.keys[child_idx] = uf_leaf.keys[0];
//             } else { // Internal nodes
//                 var uf_int = &underflowing_child.Internal;
//                 var ls_int = &left_sibling.Internal;
//
//                 // Shift existing elements in underflowing_child to make space at index 0
//                 var i: u16 = uf_int.len;
//                 while (i > 0) : (i -= 1) {
//                     uf_int.keys[i] = uf_int.keys[i - 1];
//                     uf_int.childs[i] = uf_int.childs[i - 1];
//                 }
//                 // Move child from left sibling to underflowing child
//                 uf_int.keys[0] = ls_int.keys[ls_int.len - 1];
//                 uf_int.childs[0] = ls_int.childs[ls_int.len - 1];
//                 uf_int.len += 1;
//                 ls_int.len -= 1;
//
//                 // Update key in parent
//                 internal.keys[child_idx] = uf_int.keys[0];
//             }
//             return; // Rebalancing successful
//         }
//     }
//
//     // Try to redistribute from right sibling
//     if (child_idx < internal.len - 1) {
//         const right_sibling_idx = child_idx + 1;
//         var right_sibling = internal.childs[right_sibling_idx];
//
//         if (right_sibling.len() > BASE) {
//             if (underflowing_child.is_leaf()) {
//                 var uf_leaf = &underflowing_child.Leaf;
//                 var rs_leaf = &right_sibling.Leaf;
//
//                 // Move item from right sibling to underflowing child
//                 uf_leaf.keys[uf_leaf.len] = rs_leaf.keys[0];
//                 uf_leaf.items[uf_leaf.len] = rs_leaf.items[0];
//                 uf_leaf.len += 1;
//
//                 // Shift right sibling elements left
//                 var j: u16 = 0;
//                 while (j < rs_leaf.len - 1) {
//                     rs_leaf.keys[j] = rs_leaf.keys[j + 1];
//                     rs_leaf.items[j] = rs_leaf.items[j + 1];
//                     j += 1;
//                 }
//                 rs_leaf.len -= 1;
//
//                 // Update key in parent
//                 internal.keys[right_sibling_idx] = rs_leaf.keys[0];
//             } else { // Internal nodes
//                 var uf_int = &underflowing_child.Internal;
//                 var rs_int = &right_sibling.Internal;
//
//                 // Move child from right sibling to underflowing child
//                 uf_int.keys[uf_int.len] = rs_int.keys[0];
//                 uf_int.childs[uf_int.len] = rs_int.childs[0];
//                 uf_int.len += 1;
//
//                 // Shift right sibling elements left
//                 var j: u16 = 0;
//                 while (j < rs_int.len - 1) {
//                     rs_int.keys[j] = rs_int.keys[j + 1];
//                     rs_int.childs[j] = rs_int.childs[j + 1];
//                     j += 1;
//                 }
//                 rs_int.len -= 1;
//
//                 // Update key in parent
//                 internal.keys[right_sibling_idx] = rs_int.keys[0];
//             }
//             return; // Rebalancing successful
//         }
//     }
//
//     // If redistribution is not possible, merge
//     if (child_idx > 0) { // Merge with left sibling
//         const left_sibling_idx = child_idx - 1;
//         var left_sibling = internal.childs[left_sibling_idx];
//
//         try left_sibling.merge_into(underflowing_child);
//
//         underflowing_child.destroy(alloc); // Deallocate the merged (underflowing) child
//
//         // Shift internal's children and keys to the left, removing the `underflowing_child` entry
//         var j: u16 = child_idx;
//         while (j < internal.len - 1) {
//             internal.keys[j] = internal.keys[j + 1];
//             internal.childs[j] = internal.childs[j + 1];
//             j += 1;
//         }
//         internal.len -= 1;
//     } else if (internal.len > 1) { // Merge with right sibling (if no left or left was also minimal)
//         const right_sibling_idx = child_idx + 1;
//         var right_sibling = internal.childs[right_sibling_idx];
//
//         try underflowing_child.merge_into(right_sibling);
//
//         right_sibling.destroy(alloc); // Deallocate the merged (right_sibling) child
//
//         // Shift internal's children and keys to the left, removing the `right_sibling` entry
//         var j: u16 = right_sibling_idx;
//         while (j < internal.len - 1) {
//             internal.keys[j] = internal.keys[j + 1];
//             internal.childs[j] = internal.childs[j + 1];
//             j += 1;
//         }
//         internal.len -= 1;
//     } else {
//         // This case should ideally only happen for the root, which is handled in BPlusTree.remove
//         // For any other internal node, it should always have siblings to merge with unless it's the only child of the root.
//         // If it's the last child of a root, the root will underflow and collapse.
//         panic("Node %d is underflowing and cannot redistribute or merge. This should be a root collapsing scenario.", .{child_idx});
//     }
// }
//
// fn merge_into(self: *Self, other: *Self) !void {
//     switch (self.*) {
//         .Leaf => |*self_leaf| {
//             assert(other.is_leaf());
//             const other_leaf = &other.Leaf;
//
//             const new_len = self_leaf.len + other_leaf.len;
//             assert(new_len <= CAPACITY); // Merge for deletion should not overflow CAPACITY
//
//             @memcpy(self_leaf.keys[self_leaf.len..new_len], other_leaf.keys[0..other_leaf.len]);
//             @memcpy(self_leaf.items[self_leaf.len..new_len], other_leaf.items[0..other_leaf.len]);
//             self_leaf.len = new_len;
//         },
//         .Internal => |*self_int| {
//             assert(!other.is_leaf());
//             const other_int = &other.Internal;
//
//             const new_len = self_int.len + other_int.len;
//             assert(new_len <= CAPACITY); // Merge for deletion should not overflow CAPACITY
//
//             @memcpy(self_int.keys[self_int.len..new_len], other_int.keys[0..other_int.len]);
//             @memcpy(self_int.childs[self_int.len..new_len], other_int.childs[0..other_int.len]);
//             self_int.len = new_len;
//         },
//     }
// }
//
// filepath: src/datastruct/b_plus_tree.zig
// ...existing code...
//           pub fn remove(self: *Self, key: K) !V {
//               const removed_value = try self.root.delete(key, self.alloc);
//
//               // Handle root collapse: if the root is an internal node with only one child,
//               // that child becomes the new root, and the old root is deallocated.
//               if (!self.root.is_leaf() and self.root.len() == 1) {
//                   const old_root = self.root;
//                   self.root = old_root.Internal.childs[0];
//                   old_root.alloc.destroy(old_root); // Only destroy the root container, children are re-parented
//               }
//
//               return removed_value;
//           }
// // ...existing code...
