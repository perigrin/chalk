package C; sub new { bless {n=>1}, shift } sub dbl { my $s=shift; $s->{n}*=2; 0 } package main; my $o=C->new; my @l=($o->{n}, $o->dbl, $o->{n}); print "@l\n";
