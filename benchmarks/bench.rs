use std::collections::BTreeSet;

fn main() {
    let mut set : BTreeSet<i32> = BTreeSet::new();

    for i in 1..=50_000_000 {
        set.insert(i);
    }

    println!("After insertion: {}", set.len());

    for i in (2..=50_000_000).step_by(2) {
        set.remove(&i);
    }

    println!("After removal: {}", set.len());
}
