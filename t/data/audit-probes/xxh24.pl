package O; sub new { bless {n=>1}, shift } sub m { $_[0]{n} = 9; my ($s,$p) = @_; $p } package main; my $o = O->new; print $o->m($o->{n}), "\n";
