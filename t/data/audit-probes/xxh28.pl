package O; sub new { bless {v=>0}, shift } sub inc { $_[0]{v}++ } package main; my $o = O->new; my @l = ($o->{v}, $o->inc, $o->{v}, $o->inc, $o->{v}); print "@l\n";
