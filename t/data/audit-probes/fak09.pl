my $x=1; my $f=sub { my $y=$x; sub { $x+=$y; $y++ ; $x } }; my $g=$f->(); $g->(); print $g->(), "\n";
