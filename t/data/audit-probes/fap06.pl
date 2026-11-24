package C; sub new { bless {}, shift } sub inc { $_[1]++ } package main; my $o=C->new; my @a=(1,2); $o->inc($a[0]); $o->inc($_) for @a; print "@a\n";
