package C; sub new { bless {}, shift } sub up { $_[0] = 7 } package main; my $o=C->new; $o->up; print "$o\n";
