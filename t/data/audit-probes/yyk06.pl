package C; sub new { bless {}, shift } sub DESTROY { print "D" } package main; C->new; print "E\n";
