package O; sub new { bless {n=>1}, shift } sub m { my ($s,$p) = @_; $s->{n} = 9; $p } package main; my $o = O->new; print $o->m($o->{n}), $o->{n}, "\n";
