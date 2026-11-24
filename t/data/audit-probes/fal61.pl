our $x="a"; my @o; for my $i (1..3) { my $y=$x; $x.=$i; push @o,$y } print "@o\n";
