import std;
import libc;

import btree;

fn int compare_strings(String a, String b, void* ctx)
{
    int res = libc::memcmp(a.ptr, b.ptr, min(a.len, b.len));
    if (res < 0) return -1;
    if (res > 0) return 1;
    if (a.len < b.len) return -1;
    if (a.len > b.len) return 1;
    return 0;
}

fn void main()
{
    btree::Map{String, int} m;

    m.init(&compare_strings);
    m["nose"] = 12;
    m["mouth"] = 13;
    m["arm"] = 7;
    // Value modification.
    m["mouth"] = -1;

    io::printfn("root length %s", m.root.node.len);
    for (int i = 0; i < m.root.node.len; i++)
    {
        io::printfn("key %d %s", i, m.root.node.keys[i]);
        io::printfn("val %d %s", i, m.root.node.vals[i]);
    }
}
