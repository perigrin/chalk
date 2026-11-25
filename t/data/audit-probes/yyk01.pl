package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; { my $o = C->new; } print "E\n";
