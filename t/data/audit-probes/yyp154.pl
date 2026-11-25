package C; sub new { bless {n=>1}, shift } sub m { shift; "@_" } package main; my $o=C->new; print $o->m($o->{n}, $o->{n}++), "\n";
