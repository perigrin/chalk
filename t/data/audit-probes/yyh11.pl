sub c { wantarray ? "L" : "S" } my @l = do { c() }; my @e = eval { c() }; my @s = sub { c() }->(); my $d = do { c() }; print "@l@e@s$d\n";
