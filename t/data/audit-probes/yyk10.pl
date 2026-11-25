package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; for my $i (1..2) { my $o = C->new; print $i } print "\n";
