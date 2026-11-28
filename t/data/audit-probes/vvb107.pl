package O; sub new { bless {k=>[]}, shift } sub k { push @{$_[0]{k}}, \$_[1] } package main; my $o = O->new; for my $i (1..3) { my $x = $i; $o->k($x) } print join(",", map { $$_ } @{$o->{k}}), "\n";
