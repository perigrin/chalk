package C; sub new { bless {}, shift } sub m { shift; "@_" } package main; our $g=1; my $o=C->new; print $o->m($g, ++$g), "\n";
