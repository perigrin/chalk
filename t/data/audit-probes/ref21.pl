my $x=1; my $f=sub { $x=2 }; my $y = $x==1 ? do { $f->(); $x } : 0; print "$y\n";
