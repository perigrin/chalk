my $x=1; my @fs=(sub { $x++ }, sub { $x*=10 }); $_->() for @fs; print "$x\n";
