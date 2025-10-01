use std::collections::BTreeSet;

fn main() {
    let mut set : BTreeSet<i32> = BTreeSet::new();

    for i in 1..=100_000_000 {
        set.insert(i);
    }

    println!("After insertion: {}", set.len());

    let mut sum: u64 = 0;
    for i in set {
        sum += i as u64;
    }

    println!("Sum is: {}", sum);
}
