package C; sub new { bless {}, shift } sub m { $_[1] = 7 } package main; my $o=C->new; my $v=1; $o->m($v); print "$v\n";
