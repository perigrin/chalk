package C; sub new { bless {n=>0}, shift } sub inc { $_[0]{n}++ } package main; my $o=C->new; my $m="inc"; $o->$m() for 1..3; print $o->{n},"\n";
