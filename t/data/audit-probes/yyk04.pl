package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; sub f { my $o = C->new; "f" } print f(), "E\n";
