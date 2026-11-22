package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++ } package main; my $o=C->new; my $m = C->can("inc"); $o->$m(); print $o->{n}, "\n";
