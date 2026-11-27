package C; sub new { bless {}, shift } sub m { shift; "@_" } sub k { $main::g++ } package main; our $g=1; my $o=C->new; print $o->m($g, $o->k), "\n";
