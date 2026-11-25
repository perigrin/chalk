sub f { $_=9 } for my $x (1) { $_=1; f(); print "$_\n"; }
