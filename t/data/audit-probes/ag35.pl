package K; sub new { bless { v => 0 }, $_[0] } sub bump { $_[0]{v} = $_[1] + 1; $_[1] } package main; my $o = K->new; print $o->bump(1), $o->{v}, $o->bump(0), $o->{v}, "\n";
