my $x=10; { local $_ = 5; $x += $_ } print "$x\n";
