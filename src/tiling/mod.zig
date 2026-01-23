//NOTE:
//on the future the tiling "window" manager will be here
//it will handle my splits and it will manage them,
//some event as well, like drag and who know what else
//but what it should not do is handle the render of the content on
//the splits, that will be work of the Element that uses that split,
//this element can be the code editor, the tree view, the git diff
//anything
//
//i don't really know how to impl this but i have the following system
//that i can use as a guide: https://github.com/rockorager/prise/blob/9b4ef8370ee7ead531af96f4ae48e53cdb3298e9/src/lua/tiling.lua#L2842
//
//what i see at the start is that a split contains a children:
//---@field children (Pane|Split)[]
//that means that at the start we have a Pane,
//then, this pane can convert to a Split,
//this split will have two Panes, every pane can be converted to a split
//this means that is a tree of splits and panes
//
//because i know what the structure is, this will be really easy to impl
//then i will need a floating window, that is easy as well, is will be
//an absolute element
