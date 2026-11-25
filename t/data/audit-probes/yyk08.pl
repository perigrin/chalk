package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; my %h = (o => C->new); delete $h{o}; print "E\n";
