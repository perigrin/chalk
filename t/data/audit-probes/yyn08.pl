sub a { b() + 1 } sub b { c() + 1 } sub c { die "deep\n" } my $r = eval { a() }; print defined $r ? "d" : "u", $@;
