package O; sub new { bless {v=>0}, shift } sub inc { ++$_[0]{v} } package main; my $o = O->new; my $m = "inc"; my @l = ($o->$m, $o->$m, $o->{v}); print "@l\n";
