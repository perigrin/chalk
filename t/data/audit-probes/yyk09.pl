package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; my $o = C->new; my $p = $o; undef $o; print "E"; undef $p; print "F\n";
