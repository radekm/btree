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
    btree::Map(<String, int>) m;

    m.init(&compare_strings);
    m.@get_slots("nose"; bool existed, String* k, int* v)
    {
        *k = "nose";
        *v = 12;
    };
    m.@get_slots("mouth"; bool existed, String* k, int* v)
    {
        *k = "mouth";
        *v = 13;
    };
    m.@get_slots("arm"; bool existed, String* k, int* v)
    {
        *k = "arm";
        *v = 7;
    };
    // Value modification.
    // We could also replace key with an equivalent one (for example String which we own).
    m.@get_slots("mouth"; bool existed, String* k, int* v)
    {
        *k = "mouth";
        *v = -1;
    };

    io::printfn("root length %s", m.root.node.len);
    for (int i = 0; i < m.root.node.len; i++)
    {
        io::printfn("key %d %s", i, m.root.node.keys[i]);
        io::printfn("val %d %s", i, m.root.node.vals[i]);
    }
}
