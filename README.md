Rewrite of Rust's B-tree implementation to C3 for better clarity and safety.
Reviewing unsafe code in Rust is harder because rules (especially aliasing rules)
are more complex in Rust than rules in C or C3.

Code in C and C3 is usually shorter than code in Rust.
This is especially true for code in unsafe Rust.

`rust/node.rs` is a copy of Rust's `library/alloc/src/collections/btree/node.rs`
from commit 810e4c1bc62a4801a4c29fe6c975630acbd78370.
`btree.c3l/node.c3` is a code translated to C3.
Comments were mostly preserved if they made sense in C3.
Code which made no sense in C3 was ignored. That was mostly

- Functions whose only purpose was to change phantom type parameters
  (marker parameters in case of `node.rs`).
  For example `NodeRef.borrow_mut`, `NodeRef.borrow_valmut` and `NodeRef.into_dying`
  have same body which does nothing and only differ in return type.
- Functions which when transalted to C3 became too simple.
