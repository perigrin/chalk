package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; eval { my $o = C->new; die "x\n" }; print "E\n";
