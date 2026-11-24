my $x=1; my $f=sub { $x=5 }; my $y=$x; $f->(); print "$y$x\n";
