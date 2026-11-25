package C; sub new { bless {}, shift } sub DESTROY { print "D\n" } package main; my $o = C->new; print "E";
