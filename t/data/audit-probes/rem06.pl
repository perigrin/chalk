package C; sub new { bless {n=>1}, shift } sub dbl { my $s=shift; $s->{n}*=2; $s->{n} } package main; my $o=C->new; my $x=$o->{n}; my $y=$o->dbl; print "$x $y $o->{n}\n";
