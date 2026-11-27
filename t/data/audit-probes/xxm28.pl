package K; sub new { bless {}, shift } sub k { \$_[1] } package main; my $o = K->new; my @r; for my $i (1..3) { my $x = $i; push @r, $o->k($x) } print join(",", map { $$_ } @r), "\n";
