my $x=1; sub f { $x } sub inc { $_[0]++ } inc(f()); print "$x\n";
